"""The generated release must never acquire Xcode's debugging entitlement."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class ProjectTests(unittest.TestCase):
    # Value: protects=notarizable Release build settings; fails_when=Xcode injects get-task-allow into Release;
    # why_new=transport tests and unsigned CI builds cannot detect signing settings; seam=none
    def test_mac_release_disables_debug_entitlement_injection(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            (work / 'scripts').mkdir(); (work / 'release').mkdir()
            shutil.copy2(root / 'scripts/generate-project.py', work / 'scripts')
            shutil.copy2(root / 'release/receiver.json', work / 'release')
            subprocess.run([sys.executable, str(work / 'scripts/generate-project.py')], check=True, capture_output=True)
            data = subprocess.check_output(['plutil', '-convert', 'json', '-o', '-',
                str(work / 'DuoTrackpad.xcodeproj/project.pbxproj')])
            objects = json.loads(data)['objects'].values()
            mac_release = [o['buildSettings'] for o in objects
                if o.get('isa') == 'XCBuildConfiguration' and o.get('name') == 'Release'
                and o.get('buildSettings', {}).get('SDKROOT') == 'macosx']
            self.assertEqual(len(mac_release), 1)
            self.assertEqual(mac_release[0]['CODE_SIGN_INJECT_BASE_ENTITLEMENTS'], 'NO')
            self.assertEqual(mac_release[0]['ENABLE_HARDENED_RUNTIME'], 'YES')
