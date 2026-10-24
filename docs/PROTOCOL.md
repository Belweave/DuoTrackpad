# Duo Trackpad wire protocol, version 1

Bonjour service: `_duotrackpad._tcp`. Default receiver port: TCP 48571. Disable Nagle on both endpoints. The transport uses Network.framework with peer-to-peer discovery enabled; this does not guarantee a direct radio link or replace the same-LAN setup requirement.

Every frame is a four-byte unsigned big-endian payload length followed by that many bytes. Zero lengths and payloads over 16,384 bytes close the connection. A stream parser must support fragmented headers/payloads and multiple frames in one read.

## Handshake

The client sends a version-2 JSON hello first; the receiver replies after choosing the matching authentication mode:

```json
{"version":2,"publicKey":"<base64 ephemeral X25519>","identity":"<base64 persistent X25519 public key>","name":"device name","resume":false}
```

Both keys must be 32 bytes; names are bounded to 128 UTF-8 bytes. For initial pairing, derive input material from ephemeral ECDH and use the eight-digit code as HKDF-SHA256 salt. For resume, the receiver must recognize the client identity, the client must pin the receiver identity, and both must set `resume:true`. Concatenate ephemeral ECDH with persistent-identity ECDH as input material; salt is empty. HKDF info is UTF-8 `DuoTrackpad/2`, client ephemeral key, host ephemeral key, client identity, host identity, and a single byte 0 (pair) or 1 (resume), in that order. Derive 32 bytes, then directional `client` and `host` keys as before. Persist peer trust only after the encrypted ready packet verifies.

Subsequent frames are CryptoKit ChaChaPoly combined boxes: a random 12-byte nonce, ciphertext, and a 16-byte authentication tag. Plaintext is 34 bytes: an unsigned 64-bit big-endian sequence counter followed by the 26-byte input packet below. Each direction starts its counter at zero and increments per message. Require the exact expected sequence number.

Both peers first send an encrypted `ready` packet. Deliver input only after decrypting the peer's ready. A missing handshake times out after 15 seconds. Persist private identity keys and verified peer public keys in device-only Keychain storage. Do not persist ephemeral keys or codes. See README for the short-code handshake's active-attack limitation and the production pairing replacement needed.

## Input packet

| Offset | Size | Meaning |
| --- | --- | --- |
| 0 | 1 | Protocol version, `1` |
| 1 | 1 | Kind |
| 2 | 8 | X, IEEE-754 Float64 bit pattern in big-endian order |
| 10 | 8 | Y, same format |
| 18 | 8 | Sender monotonic timestamp in seconds, same format |

All numbers must be finite. Absolute X/Y values must not exceed 8192. Relative movement uses host logical pointer coordinates: positive X moves right, positive Y down. Scroll values are signed pixel deltas; the client applies its natural-scrolling preference. The timestamp is used only to echo ping/pong, never to compare clocks across devices.

| Kind | Operation |
| --- | --- |
| 1 | Relative pointer move (X, Y) |
| 2 | Pixel scroll (X horizontal, Y vertical) |
| 3 | Left-click |
| 4 | Right-click |
| 5 | Left button down; following moves drag |
| 6 | Left button up |
| 7 | Ping with sender's monotonic timestamp |
| 8 | Pong echoing that timestamp |
| 9 | Ready; only valid as first encrypted message |
| 10 | Stop/release held buttons |
| 11 | Host status: X = 1 means mouse-control permission available, X = 0 means waiting |

Send a ping every second and disconnect after five seconds without authenticated traffic. Receivers must release held buttons whenever a session ends. Aggregate only adjacent move/scroll packets of the same kind; preserve button and control ordering. A new host requires a platform-specific event sink and equivalent session/permission safeguards.

## Added input kinds

The binary input version byte remains 1; handshake version is 2. Appended kinds: 12 scrollBegin; 13 scrollEnd (X/Y are release velocity in pixels/second after client scroll preference); 14 action (X is integer MacAction ID, Y zero); 15 zoom (X log scale delta); 16 rotate (X degrees). Scroll boundaries are coalescing barriers. Gesture command mappings are defined by `Shared/MacAction.swift`; no raw arbitrary keyboard or shell command is accepted. Pointer timestamps now also carry the local touch sampling time for pointer acceleration; never compare them across devices.

## Timestamp privacy

Before encryption the transport zeros timestamps on all non-heartbeat packets. Touch timestamps used by local pointer acceleration are never sent. Ping timestamps are elapsed seconds since channel creation; pong echoes them unchanged. Only the originating channel subtracts that interval to measure RTT. System boot-relative timestamps are not transmitted.
