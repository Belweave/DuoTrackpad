#!/usr/bin/env python3
"""Checks the actual app and mounted image, independent of the packaging steps."""
import json
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / 'release/receiver.json').read_text())


def run(*command):
    return subprocess.run(command, check=True, capture_output=True).stdout


def verify_app(app, mode):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    for key, expected in [('CFBundleIdentifier', CONFIG['bundleId']),
                          ('CFBundleShortVersionString', CONFIG['version']),
                          ('CFBundleVersion', str(CONFIG['build'])),
                          ('LSMinimumSystemVersion', CONFIG['minimumMacOS'])]:
        if info.get(key) != expected:
            raise SystemExit(f'{key}: expected {expected}, got {info.get(key)}')
    binary = app / 'Contents/MacOS' / info['CFBundleExecutable']
    if run('lipo', '-archs', str(binary)).decode().strip() != CONFIG['architecture']:
        raise SystemExit('Unexpected binary architecture.')
    for resource in ['AppIcon.icns', 'Assets.car', 'PrivacyInfo.xcprivacy']:
        if not (app / 'Contents/Resources' / resource).is_file():
            raise SystemExit(f'Missing app resource: {resource}')
    if mode == 'release':
        run('codesign', '--verify', '--deep', '--strict', str(app))
        signature = subprocess.run(['codesign', '-dvv', str(app)], capture_output=True, text=True, check=True).stderr
        required = ['Authority=Developer ID Application:', f'TeamIdentifier={CONFIG["teamId"]}', 'runtime', 'Timestamp=']
        if not all(value in signature for value in required):
            raise SystemExit('Release requires Developer ID, the expected team, hardened runtime, and a secure timestamp.')
        entitlements = run('codesign', '-d', '--entitlements', ':-', str(app))
        if entitlements.strip() and plistlib.loads(entitlements).get('com.apple.security.get-task-allow', False):
            raise SystemExit('Debug entitlement get-task-allow is not allowed in a release.')
    print(f'App verified: {CONFIG["name"]} {CONFIG["version"]} ({CONFIG["build"]}), {mode}')


def verify_dmg(dmg, mode):
    with tempfile.TemporaryDirectory(prefix='duo-dmg-check-') as mount:
        run('hdiutil', 'attach', str(dmg.resolve()), '-readonly', '-nobrowse', '-mountpoint', mount)
        try:
            volume = Path(mount)
            verify_app(volume / 'Duo Receiver.app', mode)
            applications = volume / 'Applications'
            if not applications.is_symlink() or applications.readlink() != Path('/Applications'):
                raise SystemExit('DMG needs a working Applications shortcut.')
            if not (volume / '.DS_Store').is_file() or not (volume / '.background.tiff').is_file():
                raise SystemExit('DMG is missing its custom Finder layout or artwork.')
            if mode == 'release':
                run('xcrun', 'stapler', 'validate', str(volume / 'Duo Receiver.app'))
        finally:
            run('hdiutil', 'detach', mount)
    print('Disk image contents verified.')


if __name__ == '__main__':
    if len(sys.argv) != 4 or sys.argv[1] not in ('app', 'dmg') or sys.argv[3] not in ('release', 'preview'):
        raise SystemExit('Usage: verify-release.py app|dmg PATH release|preview')
    {'app': verify_app, 'dmg': verify_dmg}[sys.argv[1]](Path(sys.argv[2]), sys.argv[3])
