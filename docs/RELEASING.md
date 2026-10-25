# Release Duo Receiver

The Mac app is distributed as a **Developer ID signed, Apple-notarized DMG**. It needs no Mac App Store listing. App Store Connect supplies the team key for Apple’s notary service. The [iPhone TestFlight app](TESTFLIGHT.md) is separate.

## Download contents

- `DuoReceiver-<version>-arm64.dmg`
- `SHA256SUMS`

The DMG has custom Retina artwork and drag-to-Applications installation. Both app and disk image are notarized and stapled, so the copied app retains its ticket. Releases require passing signature, version, architecture, notarization, Gatekeeper, and mounted-content checks.

## GitHub Actions

**Build and test** runs on main, release branches, and pull requests, without Apple credentials.

**Release Duo Receiver** runs manually from main or for a `v*` tag. The commit must be on main and the tag must match `release/receiver.json`. Both apps are tested and built first. Published releases are not overwritten.

Workflows use Apple Silicon `xcode-27` runners, select `/Applications/Xcode_27.1.app`, and verify **27A9275**. If GitHub retires that version, update the guard deliberately after validating a replacement.

Secrets are in the **receiver-release** environment. Deployment rules permit main and release tags; the workflow also checks tag ancestry. Pull requests cannot run signing. A temporary signing keychain is deleted in an always-run cleanup step.

| Environment secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64 certificate and private-key export |
| `DEVELOPER_ID_P12_PASSWORD` | Password for that export |
| `ASC_PRIVATE_KEY_BASE64` | Base64 App Store Connect team key |
| `ASC_KEY_ID` | Team key ID |
| `ASC_ISSUER_ID` | Team issuer ID |

The Apple key has the Developer role. Names do not restrict these credentials to one app; protect the release workflow and environment. Keep keys out of Git, logs, and public artifacts.

## Publish the next version

1. Change `version` and increment `build` in `release/receiver.json`, for example to `0.1.1`.
2. Update the [release notes](../release/notes.md) and [changelog](../CHANGELOG.md), then regenerate the project.
3. Merge reviewed changes to main after CI passes.
4. Run **Release Duo Receiver** from main, or push the matching version tag.
5. Check the release files and download checksum.

Early 0.x releases are prereleases. A manual workflow run creates the matching Git tag if needed.

## Build locally

```sh
python3 -m venv build/release-venv
build/release-venv/bin/pip install -r release/requirements.txt
export DUO_CODE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export DUO_NOTARY_PROFILE='your-local-notary-profile'
bash scripts/release-macos.sh
```

Set your team in `release/receiver.json` for a fork. A local Keychain profile replaces `ASC_PRIVATE_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID`. Configure it with Apple’s `notarytool store-credentials`, keeping secrets outside the repo.

`bash scripts/release-macos.sh preview` builds an unsigned installer design check. Its filename includes **preview**; the release workflow never publishes it.

## Retry and recovery

Notarization receipts record each archive’s hash and Apple submission ID. Repeating the command with the same inputs resumes that submission. An interrupted upload with no returned ID requires inspecting `notarytool history` first. Changed inputs require a new `DUO_RELEASE_DIR`; pending submissions are preserved.

If a CI run times out during notarization, run the workflow again from the same commit and set **resume_run_id** to the failed run’s numeric ID. It restores the exact submitted archives and receipts from a 30-day artifact, then resumes Apple’s existing submission. A normal retry without that field creates a fresh candidate. Resume files contain no signing credentials. Only a release workflow run for the same repository and commit is accepted.

If a GitHub release exists after an interrupted publish, inspect its assets before acting. Do not automatically delete releases or replace published files. Bump the version for changed binaries.

Revoke **Duo Receiver Release CI** in App Store Connect → Users and Access → Integrations. Manage the Developer ID certificate in Apple Developer → Certificates. Replace the GitHub secrets when rotating credentials. Certificate changes can affect distribution and Accessibility permissions.

Apple references: [Developer ID](https://developer.apple.com/developer-id/), [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [custom workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
