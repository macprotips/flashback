#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Summarize nonvisual evidence from a native Shockwave probe.

This deliberately never promotes activity, animation, or a title screen to a
gameplay pass. Only a probe with an authored game-state assertion can do that.
"""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import urlparse


def _snapshot_order(path):
    name = path.stem.removeprefix('Shockwave-')
    if name == 'Title':
        return (0, 0)
    if name.startswith('Step-'):
        try:
            return (1, int(name[5:]))
        except ValueError:
            pass
    return (2, name)


def _read_json(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return default


def _failure_detail(directory):
    path = directory/'Timeout-details.txt'
    if not path.is_file():
        return {}
    # The native checker may prefix truncation notices before its single-line
    # JSON diagnostic. Search from the end instead of treating those notices as
    # part of the payload.
    for line in reversed(path.read_text(errors='replace').splitlines()):
        if not line.startswith('{'):
            continue
        try:
            return json.loads(line)
        except json.JSONDecodeError:
            continue
    return {}


def _decoded(value, default):
    if isinstance(value, type(default)):
        return value
    if isinstance(value, str):
        try:
            decoded = json.loads(value)
            return decoded if isinstance(decoded, type(default)) else default
        except json.JSONDecodeError:
            pass
    return default


def _missing(directory):
    record = _read_json(directory/'MissingResources.json', {})
    expected = set(record.get('expected') or [])
    observed = record.get('observed') or []
    unexpected = []
    for value in observed:
        path = urlparse(value).path
        relative = path[len('/game/'):] if path.startswith('/game/') else None
        if relative not in expected:
            unexpected.append(value)
    return dict(observed=observed, expected=sorted(expected), unexpected=unexpected)


def analyze_probe(directory):
    directory = Path(directory)
    paths = sorted(directory.glob('Shockwave-*.json'), key=_snapshot_order)
    failure_detail = _failure_detail(directory)
    if not paths and failure_detail:
        # Preserve early initialization failures that occur before the normal
        # timed snapshot. This is exactly where a generic UI error otherwise
        # loses the actionable VM exception and call stack.
        paths = []
        data = dict(
            state=_decoded(failure_detail.get('vm'), {}),
            globals=_decoded(failure_detail.get('globals'), {}),
            audio=failure_detail.get('audio') or {},
            input=failure_detail.get('input') or [],
            errors=failure_detail.get('errors') or [],
            diagnostics=failure_detail.get('diagnostics') or [],
            game=None,
            main=None,
        )
        synthetic = [('Failure', data, None)]
    else:
        synthetic = []
    snapshots = []
    inputs = [(path.stem.removeprefix('Shockwave-'), _read_json(path, {}), path.with_suffix('.png')) for path in paths] + synthetic
    for name, data, image in inputs:
        state = data.get('state') or {}
        globals_ = (data.get('globals') or {}).get('globals') or {}
        audio = data.get('audio') or {}
        owned_state = json.dumps({'game': data.get('game'), 'main': data.get('main')}, sort_keys=True, separators=(',', ':')).encode()
        snapshots.append(dict(
            name=name,
            movie_loaded=bool(state.get('movie_loaded')),
            playing=bool(state.get('is_playing')),
            paused=bool(state.get('is_paused')),
            frame=state.get('current_frame'),
            total_frames=state.get('total_frames'),
            globals=sum(1 for value in globals_.values() if value.get('type_name') != 'void'),
            script_instances=sum(1 for value in globals_.values() if value.get('type_name') == 'script_instance'),
            input_events=len(data.get('input') or []),
            audio_started=int(audio.get('started') or 0),
            audio_non_silent=int(audio.get('nonSilent') or 0),
            errors=[str(value) for value in (data.get('errors') or [])],
            diagnostics=[str(value) for value in (data.get('diagnostics') or [])],
            image_sha256=hashlib.sha256(image.read_bytes()).hexdigest() if image and image.is_file() else None,
            game_state_sha256=hashlib.sha256(owned_state).hexdigest(),
        ))
    result = (directory/'Result.txt').read_text().strip() if (directory/'Result.txt').is_file() else 'No result'
    missing = _missing(directory)
    # A late failure is written to Timeout-details after the most recent timed
    # snapshot. Always merge it; otherwise a probe that had already captured a
    # healthy frame could report FAIL while hiding the exact final exception.
    errors = list(dict.fromkeys(
        [error for snap in snapshots for error in snap['errors']] +
        [str(value) for value in (failure_detail.get('errors') or [])]
    ))
    diagnostics = list(dict.fromkeys(
        [note for snap in snapshots for note in snap['diagnostics']] +
        [str(value) for value in (failure_detail.get('diagnostics') or [])]
    ))
    values = lambda key: [snap[key] for snap in snapshots if snap[key] is not None]
    frames = values('frame')
    image_hashes = values('image_sha256')
    global_counts = values('globals')
    instance_counts = values('script_instances')
    game_state_hashes = values('game_state_sha256')
    signals = dict(
        snapshots=len(snapshots),
        movie_loaded=any(snap['movie_loaded'] for snap in snapshots),
        frame_progress=len(set(frames)) > 1,
        visual_change=len(set(image_hashes)) > 1,
        state_change=len(set(global_counts)) > 1 or len(set(instance_counts)) > 1 or len(set(game_state_hashes)) > 1,
        input_delivered=max(values('input_events') or [0]) > 0,
        non_silent_audio=max(values('audio_non_silent') or [0]) > 0,
    )
    signals['stall_suspected'] = (signals['movie_loaded'] and len(snapshots) > 1 and
                                  not signals['frame_progress'] and not signals['visual_change'] and
                                  not signals['state_change'])
    hard_failure = result.startswith('FAIL:') or bool(errors) or bool(missing['unexpected'])
    if hard_failure:
        assessment = 'FAIL'
    elif result.startswith('PASS: Shockwave recorded gameplay condition'):
        assessment = 'ASSERTED_GAMEPLAY'
    elif signals['stall_suspected']:
        assessment = 'STALLED_EVIDENCE'
    elif signals['movie_loaded'] and any(signals[key] for key in ('frame_progress','visual_change','state_change','input_delivered','non_silent_audio')):
        assessment = 'ACTIVE_EVIDENCE'
    elif signals['movie_loaded']:
        assessment = 'OPENED_UNVERIFIED'
    else:
        assessment = 'NO_EVIDENCE'
    return dict(
        schema_version=1,
        assessment=assessment,
        claim='Only ASSERTED_GAMEPLAY represents a passed authored gameplay condition.',
        result=result,
        signals=signals,
        frames=frames,
        total_frames=values('total_frames'),
        global_counts=global_counts,
        script_instance_counts=instance_counts,
        errors=errors,
        diagnostics=diagnostics,
        failure_console_tail=str(failure_detail.get('console') or '')[-4000:],
        failure_stack=_decoded(failure_detail.get('stack'), {}),
        missing_resources=missing,
        snapshots=snapshots,
    )


def write_health(directory):
    report = analyze_probe(directory)
    (Path(directory)/'Health.json').write_text(json.dumps(report, indent=2, sort_keys=True)+'\n')
    return report


def _self_test():
    import tempfile
    with tempfile.TemporaryDirectory() as name:
        root = Path(name)
        base = dict(state={'movie_loaded': True, 'is_playing': True, 'current_frame': 1, 'total_frames': 10},
                    globals={'globals': {'g': {'type_name': 'script_instance'}}}, audio={'started': 1, 'nonSilent': 0},
                    input=[], errors=[], diagnostics=[])
        (root/'Shockwave-Title.json').write_text(json.dumps(base))
        changed = dict(base)
        changed['state'] = dict(base['state'], current_frame=2)
        changed['input'] = [{'type': 'keydown'}]
        (root/'Shockwave-Step-0.json').write_text(json.dumps(changed))
        (root/'Result.txt').write_text('OBSERVED: opened\n')
        report = analyze_probe(root)
        assert report['assessment'] == 'ACTIVE_EVIDENCE'
        assert report['signals']['frame_progress'] and report['signals']['input_delivered']
        failed = dict(changed, errors=['No handler'])
        (root/'Shockwave-Step-0.json').write_text(json.dumps(failed))
        assert analyze_probe(root)['assessment'] == 'FAIL'
        (root/'Shockwave-Step-0.json').write_text(json.dumps(changed))
        (root/'Timeout-details.txt').write_text('prefix\n'+json.dumps({'errors':['Late timeout failure']})+'\n')
        late = analyze_probe(root)
        assert late['assessment'] == 'FAIL' and late['errors'] == ['Late timeout failure']
        (root/'Timeout-details.txt').unlink()
        (root/'Shockwave-Step-0.json').write_text(json.dumps(changed))
        (root/'Result.txt').write_text('PASS: Shockwave recorded gameplay condition, native input sequence, and game assets\n')
        assert analyze_probe(root)['assessment'] == 'ASSERTED_GAMEPLAY'
    print('PASS: Shockwave health reports separate failures, activity evidence, and asserted gameplay')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, nargs='?')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        _self_test()
        return
    if not args.directory:
        parser.error('DIRECTORY is required unless --self-test is used')
    print(json.dumps(write_health(args.directory), indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
