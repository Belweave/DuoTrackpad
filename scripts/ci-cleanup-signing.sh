#!/bin/bash
set -uo pipefail
: "${RUNNER_TEMP:?GitHub runner required}"
DUO_SECRETS="$RUNNER_TEMP/duo-receiver-signing"
python3 - "$DUO_SECRETS" <<'PY'
from pathlib import Path
import shlex,shutil,subprocess,sys
root=Path(sys.argv[1]); errors=[]
def attempt(command):
    try: subprocess.run(command,check=True,capture_output=True)
    except (OSError,subprocess.CalledProcessError) as error: errors.append(str(error))
try:
    previous=root/'previous-keychains.txt'
    if previous.exists():
        attempt(['security','list-keychains','-d','user','-s',*shlex.split(previous.read_text())])
    keychain=root/'release.keychain-db'
    if keychain.exists(): attempt(['security','delete-keychain',str(keychain)])
finally:
    # Attempt secret-file removal even when Keychain operations fail.
    try:
        if root.exists(): shutil.rmtree(root)
    except OSError as error: errors.append(str(error))
if errors: raise SystemExit('Credential cleanup encountered errors: '+'; '.join(errors))
PY
