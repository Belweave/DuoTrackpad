#!/usr/bin/env python3
"""Refuse to reuse distribution output after any build input changes."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def inputs():
    files = []
    for directory in ['Shared', 'macOS', 'release', 'scripts']:
        files += [p for p in (ROOT / directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}


def main():
    output, mode = Path(sys.argv[1]), sys.argv[2]
    receipt = output / 'candidate.json'
    candidate = {'mode': mode, 'files': inputs(),
                 'toolchain': subprocess.check_output(['xcodebuild', '-version'], text=True).strip()}
    if receipt.exists():
        if json.loads(receipt.read_text()) != candidate:
            raise SystemExit('Release inputs changed. Use a new DUO_RELEASE_DIR to build a fresh candidate; pending notarization is preserved.')
    else:
        receipt.write_text(json.dumps(candidate, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
