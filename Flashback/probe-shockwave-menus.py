#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Find collection titles that reach live play once their preloader finishes.

The launch survey captures each title after a few seconds and calls what it
sees an observation. That under-reports: Beach Soccer and American Football
were both recorded as black-frame failures and neither was broken — they needed
their whole preloader before the title screen would answer a click.

This waits much longer, presses the places those games put their start button,
and records how many of the game object's properties became live. A game that
is still sitting on its title screen keeps a nearly empty game object; one that
has entered play fills it in. That number is a lead, not a pass — a title that
looks promising here still needs its own case in check-shockwave-corpus.py with
a recorded condition before it counts as playable.

Usage:
  probe-shockwave-menus.py MANIFEST OUTPUT [--games ID ...] [--wait 16]
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import time
from pathlib import Path

# Where this engine family puts its start button, as a fraction of the stage.
# Taken from the titles already verified: Air Show and Beach Soccer centre it
# low, American Football sits it mid-right, Basketball Slam bottom-left.
SPOTS = [(0.50, 0.78), (0.50, 0.67), (0.78, 0.67), (0.21, 0.83), (0.50, 0.50)]

# Two signals, because games outside the Miniclip family keep their state under
# their own global names. The first is that family's game object; the second is
# how many globals hold a value at all, which rises when any game builds its
# world regardless of what it calls things.
STATE = """(()=>{
  const globals = JSON.parse(__vm.mcp_get_globals()).globals;
  const state = JSON.parse(__vm.mcp_get_execution_state());
  const named = globals.gGame || globals.gMainManager || globals.g || globals.glob;
  let live = 0, total = 0, name = null;
  if (named && named.datum_id) {
    const datum = JSON.parse(__vm.mcp_inspect_datum(named.datum_id));
    name = datum.value || null;
    const props = datum.properties || {};
    total = Object.keys(props).length;
    live = Object.values(props).filter(p => p.type_name !== 'void').length;
  }
  const values = Object.values(globals);
  const named_globals = values.filter(g => g.type_name !== 'void').length;
  const objects = values.filter(g => g.type_name === 'script_instance').length;
  return {frame: state.current_frame, total_frames: state.total_frames,
          object: name, live: live, properties: total,
          globals: named_globals, instances: objects,
          errors: (window.shockwaveErrors || []).length};
})()"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--app', type=Path, default=Path(__file__).resolve().parent.parent/'Flashback.app')
    parser.add_argument('--games', nargs='+')
    parser.add_argument('--wait', type=float, default=16, help='Seconds to let the preloader run')
    args = parser.parse_args()

    manifest = args.manifest.resolve()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    runtime = args.app.resolve()/'Contents/Resources/Shockwave/dirplayer-polyfill.js'
    (root/'Runtime.json').write_text(json.dumps(
        {'app': str(args.app.resolve()),
         'polyfill_sha256': hashlib.sha256(runtime.read_bytes()).hexdigest()}, indent=2)+'\n')

    cases = json.loads(manifest.read_text())
    if args.games:
        by_id = {case['id']: case for case in cases}
        cases = [by_id[name] for name in args.games]

    results = []
    for case in cases:
        entry = (manifest.parent/case['entry']).resolve()
        source = (manifest.parent/case['import_folder']).resolve()
        assert entry.is_relative_to(manifest.parent) and source.is_relative_to(manifest.parent)
        assert hashlib.sha256(entry.read_bytes()).hexdigest() == case['sha256'], entry
        out = root/case['id']
        out.mkdir()
        # Read the stage first, click each candidate spot, then read again. The
        # steps are the same for every title; only the game decides what a click
        # on empty artwork does, and a click on nothing changes nothing.
        steps = [dict(read=STATE, wait=0)]
        for fraction_x, fraction_y in SPOTS:
            steps.append(dict(click=[fraction_x, fraction_y], hover=0.8, wait=3, fractional=True))
        steps.append(dict(read=STATE, wait=0))
        probe = {'wait': args.wait, 'steps': steps}
        if case.get('parameters'):
            probe['parameters'] = case['parameters']
        if case.get('expected_missing'):
            probe['expectedMissing'] = case['expected_missing']
        (out/'Probe.json').write_text(json.dumps(probe, indent=2)+'\n')
        start = time.monotonic()
        with (out/'Console.txt').open('w') as log:
            try:
                subprocess.run([str(args.app.resolve()/'Contents/MacOS/Flashback'), '--shockwave-probe',
                                str(source), case['entry_relative_to_import_folder'], str(out)],
                               stdout=log, stderr=subprocess.STDOUT,
                               timeout=args.wait + 90, check=False)
            except subprocess.TimeoutExpired:
                pass
        observations = {}
        if (out/'Observations.json').is_file():
            observations = json.loads((out/'Observations.json').read_text())
        before = observations.get('0') or {}
        after = observations.get(str(len(steps)-1)) or {}
        record = dict(id=case['id'], title=case['title'],
                      seconds=round(time.monotonic()-start, 1),
                      before_live=before.get('live'), after_live=after.get('live'),
                      properties=after.get('properties'), object=after.get('object'),
                      frame=after.get('frame'), before_frame=before.get('frame'),
                      before_globals=before.get('globals'), after_globals=after.get('globals'),
                      before_instances=before.get('instances'),
                      after_instances=after.get('instances'),
                      gained=(after.get('live') or 0) - (before.get('live') or 0),
                      gained_globals=(after.get('globals') or 0) - (before.get('globals') or 0),
                      gained_instances=(after.get('instances') or 0) - (before.get('instances') or 0))
        results.append(record)
        (root/'Results.json').write_text(json.dumps(results, indent=2)+'\n')
        print(f"{case['title'][:34]:36} live {record['before_live']}->{record['after_live']}"
              f"  globals {record['before_globals']}->{record['after_globals']}"
              f"  objects {record['before_instances']}->{record['after_instances']}"
              f"  frame {record['before_frame']}->{record['frame']}", flush=True)
        library = out/'Library'
        if library.is_dir():
            shutil.rmtree(library)

    def score(record):
        return max(record.get('gained') or 0, record.get('gained_instances') or 0,
                   (record.get('gained_globals') or 0) // 2)
    leads = [r for r in results if score(r) > 0]
    print(f'\n{len(leads)} of {len(results)} titles gained state after menu input.')
    for record in sorted(leads, key=lambda r: -score(r)):
        print(f"  {record['title'][:40]:42} props +{record.get('gained') or 0:<4}"
              f" objects +{record.get('gained_instances') or 0:<4}"
              f" globals +{record.get('gained_globals') or 0}")


if __name__ == '__main__':
    main()
