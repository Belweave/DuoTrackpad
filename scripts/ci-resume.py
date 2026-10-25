#!/usr/bin/env python3
"""Preserve only exact submitted archives and receipts, never credentials or build caches."""
from pathlib import Path
import sys
import tarfile

mode, directory, archive = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
if mode == 'save':
    if (directory / 'candidate.json').is_file():
        with tarfile.open(archive, 'w:gz') as output:
            paths = [directory / 'candidate.json', *directory.glob('*.zip'),
                     *directory.glob('*.dmg'), *directory.glob('notary/*.json')]
            for path in paths:
                if path.is_file(): output.add(path, arcname=str(path.relative_to(directory)), recursive=False)
elif mode == 'restore':
    directory.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as source:
        for member in source.getmembers():
            name = Path(member.name)
            allowed = (name == Path('candidate.json') or
                       (len(name.parts) == 1 and name.suffix in ('.dmg', '.zip')) or
                       (len(name.parts) == 2 and name.parts[0] == 'notary' and name.suffix == '.json'))
            if not allowed or not member.isfile(): raise SystemExit('Unexpected resume archive entry.')
        source.extractall(directory, filter='data')
else:
    raise SystemExit('Usage: ci-resume.py save|restore OUTPUT_DIR ARCHIVE')
