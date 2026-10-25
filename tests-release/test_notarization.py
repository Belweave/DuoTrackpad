"""Release contracts: never duplicate an upload or publish a rejected archive."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/notarize.py'


class NotarizationTests(unittest.TestCase):
    # Value: protects=upload idempotency and rejection gates; fails_when=resuming uploads twice or accepts Invalid;
    # why_new=Swift tests cover the transport, not the external release boundary; seam=none
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archive = self.root / 'Receiver.dmg'
        self.archive.write_bytes(b'an independently supplied archive')
        self.calls = self.root / 'calls'
        mock = self.root / 'xcrun'
        mock.write_text('#!' + sys.executable + '\n' + '''
import json,os,sys
from pathlib import Path
command=sys.argv[2]
with Path(os.environ['DUO_TEST_CALLS']).open('a') as f: f.write(command+'\\n')
if command=='submit': print(json.dumps({'id':'submission-123','status':'In Progress'}))
elif command=='info': print(json.dumps({'id':'submission-123','status':os.environ.get('DUO_TEST_STATUS','Accepted')}))
elif command=='wait':
 if os.environ.get('DUO_TEST_TIMEOUT'):
  print('Timeout waiting for Apple; submission continues',file=sys.stderr); raise SystemExit(1)
 print(json.dumps({'id':'submission-123','status':os.environ.get('DUO_TEST_WAIT_STATUS','Accepted')}))
elif command=='log': print(json.dumps({'issues':[{'message':'unsigned code'}]}))
else: raise SystemExit(2)
''')
        mock.chmod(0o755)
        self.env = {**os.environ, 'PATH': str(self.root) + os.pathsep + os.environ['PATH'],
                    'DUO_NOTARY_PROFILE': 'test-profile', 'DUO_TEST_CALLS': str(self.calls)}

    def invoke(self):
        return subprocess.run([sys.executable, str(SCRIPT), str(self.archive),
                               '--state-dir', str(self.root / 'receipts')],
                              env=self.env, capture_output=True, text=True)

    def test_accepted_retry_reuses_submission(self):
        self.assertEqual(self.invoke().returncode, 0)
        self.assertEqual(self.invoke().returncode, 0)
        self.assertEqual(self.calls.read_text().splitlines().count('submit'), 1)
        receipt = json.loads((self.root / 'receipts/Receiver.dmg.json').read_text())
        self.assertEqual(receipt['status'], 'Accepted')

    def test_changed_bytes_cannot_reuse_submission(self):
        self.assertEqual(self.invoke().returncode, 0)
        self.archive.write_bytes(b'different release')
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('changed after submission', result.stderr)
        self.assertEqual(self.calls.read_text().splitlines().count('submit'), 1)

    def test_ambiguous_upload_stops_before_resubmission(self):
        self.assertEqual(self.invoke().returncode, 0)
        path = self.root / 'receipts/Receiver.dmg.json'
        receipt = json.loads(path.read_text()); del receipt['id']
        path.write_text(json.dumps(receipt))
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Inspect notarytool history', result.stderr)
        self.assertEqual(self.calls.read_text().splitlines().count('submit'), 1)

    def test_rejected_archive_blocks_release_and_keeps_log(self):
        self.env['DUO_TEST_STATUS'] = 'Invalid'
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Notarization did not pass: Invalid', result.stderr)
        log = json.loads((self.root / 'receipts/Receiver.dmg.log.json').read_text())
        self.assertEqual(log['issues'][0]['message'], 'unsigned code')

    def test_pending_timeout_resumes_without_uploading_again(self):
        self.env.update(DUO_TEST_STATUS='In Progress', DUO_TEST_TIMEOUT='1')
        self.assertNotEqual(self.invoke().returncode, 0)
        del self.env['DUO_TEST_TIMEOUT']
        self.assertEqual(self.invoke().returncode, 0)
        self.assertEqual(self.calls.read_text().splitlines().count('submit'), 1)
        self.assertEqual(self.calls.read_text().splitlines().count('wait'), 2)

    def test_rejection_after_wait_still_blocks_release(self):
        self.env.update(DUO_TEST_STATUS='In Progress', DUO_TEST_WAIT_STATUS='Invalid')
        self.assertNotEqual(self.invoke().returncode, 0)
        receipt=json.loads((self.root / 'receipts/Receiver.dmg.json').read_text())
        self.assertEqual(receipt['status'], 'Invalid')
