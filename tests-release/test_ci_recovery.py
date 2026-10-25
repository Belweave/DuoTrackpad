"""Recovery contracts for remote CI runners and signing secrets."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RecoveryTests(unittest.TestCase):
    # Value: protects=secret cleanup after Keychain errors; fails_when=an earlier error skips private-file deletion;
    # why_new=cleanup errors are outside notarization tests; seam=none
    def test_cleanup_removes_secrets_even_when_security_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory); secrets=work/'duo-receiver-signing';secrets.mkdir()
            for name in ['developer-id.p12','notary.p8','release.keychain-db']:
                (secrets/name).write_bytes(b'private-test-material')
            (secrets/'previous-keychains.txt').write_text('"/tmp/old.keychain-db"')
            security=work/'security'
            security.write_text('#!/bin/sh\nprintf "%s\\n" "$1" >> "$DUO_TEST_SECURITY_CALLS"\nexit 1\n')
            security.chmod(0o755)
            calls=work/'calls'
            env={**os.environ,'RUNNER_TEMP':str(work),'PATH':str(work)+os.pathsep+os.environ['PATH'],
                 'DUO_TEST_SECURITY_CALLS':str(calls)}
            result=subprocess.run(['bash',str(ROOT/'scripts/ci-cleanup-signing.sh')],env=env,capture_output=True)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse(secrets.exists())
            self.assertEqual(calls.read_text().splitlines(),['list-keychains','delete-keychain'])

    # Value: protects=byte-identical resume across runners; fails_when=archives or pending IDs change or secrets leak;
    # why_new=local retry tests do not move files between runners; seam=none
    def test_ci_resume_preserves_archives_and_excludes_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory); source=work/'source'; source.mkdir();(source/'notary').mkdir()
            expected={'candidate.json':b'{"candidate":"test"}', 'Receiver.zip':b'exact signed bytes',
                      'Receiver.dmg':b'exact disk image', 'notary/Receiver.zip.json':b'{"id":"pending"}'}
            for name,data in expected.items(): (source/name).write_bytes(data)
            (source/'notary.p8').write_bytes(b'never upload this')
            archive=work/'resume.tar.gz';destination=work/'new-runner'
            for mode,path in [('save',source),('restore',destination)]:
                subprocess.run([sys.executable,str(ROOT/'scripts/ci-resume.py'),mode,str(path),str(archive)],check=True)
            actual={str(p.relative_to(destination)):p.read_bytes() for p in destination.rglob('*') if p.is_file()}
            self.assertEqual(actual,expected)

    # Value: protects=version tag matches the built commit; fails_when=manual release attaches new bytes to an old tag;
    # why_new=notarization verifies Apple acceptance, not Git provenance; seam=none
    def test_release_ref_rejects_a_tag_for_another_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            work=Path(directory);remote=work/'remote.git';repo=work/'repo'
            def git(*args): return subprocess.check_output(['git',*args],stderr=subprocess.DEVNULL,text=True).strip()
            git('init','--bare',str(remote));git('init',str(repo))
            git('-C',str(repo),'config','user.email','test@example.com')
            git('-C',str(repo),'config','user.name','Release Test')
            git('-C',str(repo),'remote','add','origin',str(remote))
            git('-C',str(repo),'commit','--allow-empty','-m','first')
            first=git('-C',str(repo),'rev-parse','HEAD')
            git('-C',str(repo),'tag','-a','v0.1.0','-m','release')
            git('-C',str(repo),'push','origin','v0.1.0')
            git('-C',str(repo),'commit','--allow-empty','-m','second')
            second=git('-C',str(repo),'rev-parse','HEAD')
            def verify(version,sha):
                return subprocess.run(['bash',str(ROOT/'scripts/verify-release-ref.sh'),version,sha],cwd=repo,capture_output=True)
            self.assertEqual(verify('0.1.0',first).returncode,0)
            self.assertNotEqual(verify('0.1.0',second).returncode,0)
            self.assertEqual(verify('0.1.1',second).returncode,0)
