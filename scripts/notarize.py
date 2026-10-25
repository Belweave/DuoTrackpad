#!/usr/bin/env python3
"""Submit once, resume by submission ID, and require Apple's Accepted status."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    parser.add_argument('--state-dir', type=Path, required=True)
    args = parser.parse_args()
    archive = args.archive.resolve(strict=True)
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=True)
    digest = hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest()
    receipt = state / (archive.name + '.json')
    auth = []
    if profile := os.environ.get('DUO_NOTARY_PROFILE'):
        auth = ['--keychain-profile', profile]
    else:
        for variable, flag in [('ASC_PRIVATE_KEY_PATH', '--key'), ('ASC_KEY_ID', '--key-id'), ('ASC_ISSUER_ID', '--issuer')]:
            value = os.environ.get(variable)
            if not value:
                raise SystemExit(f'{variable} is required (or use DUO_NOTARY_PROFILE).')
            auth += [flag, value]

    def run(command, *parameters):
        result = subprocess.run(['xcrun', 'notarytool', command, *parameters, *auth,
                                 '--output-format', 'json'], capture_output=True, text=True)
        if result.returncode:
            raise SystemExit(result.stderr or result.stdout)
        return json.loads(result.stdout)

    if receipt.exists():
        saved = json.loads(receipt.read_text())
        if saved['sha256'] != digest:
            raise SystemExit(f'{archive.name} changed after submission. Use a new output directory; do not overwrite a pending submission.')
        submission_id = saved.get('id')
        if not submission_id:
            raise SystemExit('A previous upload may have started without returning its ID. Inspect notarytool history before retrying.')
    else:
        # Record the attempt first so a dropped response never causes an automatic duplicate.
        saved = {'sha256': digest, 'archive': archive.name, 'status': 'upload-started'}
        receipt.write_text(json.dumps(saved, indent=2) + '\n')
        submitted = run('submit', str(archive))
        submission_id = submitted['id']
        saved.update(id=submission_id, status=submitted.get('status', 'Submitted'))
        receipt.write_text(json.dumps(saved, indent=2) + '\n')
    print(f'{archive.name}: submission {submission_id}', flush=True)
    status = run('info', submission_id)
    if status['status'] == 'In Progress':
        status = run('wait', submission_id, '--timeout', '20m')
    saved.update(status=status['status'])
    receipt.write_text(json.dumps(saved, indent=2) + '\n')
    if status['status'] != 'Accepted':
        log = run('log', submission_id)
        (state / (archive.name + '.log.json')).write_text(json.dumps(log, indent=2) + '\n')
        raise SystemExit(f'Notarization did not pass: {status["status"]}. See {state}.')
    print(f'{archive.name}: Accepted', flush=True)


if __name__ == '__main__':
    main()
