# Security and privacy

Duo Trackpad is an early beta for a trusted local network. It sends input directly from your iPhone to the paired Mac. It does not use a cloud relay, account system, advertising, or analytics service.

## Permissions and stored data

The receiver needs Accessibility to control your Mac, and local-network access to accept a connection. It accepts one connected client at a time. The iPhone keeps preferences locally. Both devices store private identity keys and trusted peer identities in their device-only Keychain.

**Forget** revokes remembered trust. Uninstalling alone does not erase Keychain entries. The receiver uses TCP port 48571. Do not forward that port from a router or expose it to the internet.

## Pairing limitations

Initial pairing uses an eight-digit code and a custom X25519/HKDF handshake. It is not an independently audited password-authenticated key exchange. An active attacker can establish a handshake and attempt offline guesses of the code. Use networks you trust. An audited PAKE or a high-entropy QR flow is needed before claiming resistance to that attack.

Later sessions pin saved identities and use fresh ephemeral agreement, directional ChaCha20-Poly1305 keys, and replay counters. Codes expire and failed attempts are rate-limited. These protections do not remove the initial-pairing limitation.

The apps do not transmit system boot-relative timestamps. Heartbeats contain elapsed connection intervals. See the [protocol](docs/PROTOCOL.md).

## Report a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/Belweave/DuoTrackpad/security/advisories/new). Do not post private keys, pairing transcripts, credentials, or sensitive device data in public issues. For ordinary bugs, open an issue with app versions and reproduction steps.
