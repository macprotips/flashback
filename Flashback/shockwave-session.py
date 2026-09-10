#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Send a command to a native Shockwave test session.

Create OUTPUT/Probe.json with {"interactive":true}, then launch Flashback with
--shockwave-probe SOURCE ENTRY OUTPUT. Pass a step JSON file to this script,
or import send(output, **step). Commands use the regular probe's native input
and read fields, plus snapshot, restart, and finish. Commands.json preserves
the sequence; a session observation is not a gameplay pass.
ArrowUp/Down/Left/Right names are converted to macOS function-key characters.
"""
import json
from pathlib import Path
import sys
import time


def send(output, timeout=30, **step):
    arrows = {'ArrowUp': ('\uf700', 126), 'ArrowDown': ('\uf701', 125),
              'ArrowLeft': ('\uf702', 123), 'ArrowRight': ('\uf703', 124)}
    if step.get('key') in arrows:
        step['key'], step['keyCode'] = arrows[step['key']]
    output = Path(output)
    command = output/'Command.json'
    previous = json.loads(command.read_text()).get('id', -1) if command.exists() else -1
    step = dict(step, id=previous+1)
    step.setdefault('wait', 0)
    pending = output/'Command.pending.json'
    pending.write_text(json.dumps(step))
    pending.replace(command)
    deadline = time.monotonic()+timeout
    while time.monotonic() < deadline:
        try:
            reply = json.loads((output/'Response.json').read_text())
            if reply['id'] == step['id']:
                return reply
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        time.sleep(0.1)
    raise TimeoutError(f"Native test session did not acknowledge command {step['id']}")


if __name__ == '__main__':
    print(json.dumps(send(sys.argv[1], **json.loads(Path(sys.argv[2]).read_text())), indent=2))
