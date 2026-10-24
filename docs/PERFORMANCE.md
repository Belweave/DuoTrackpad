# Transport performance

Measured locally on 2026-10-24. These changes preserve wire version 1, the 26-byte input
layout, the existing kind raw values, framing, and cipher format. No input kinds were
added by the performance work. Pairing and gesture vocabulary are separate work.

## Changes and bounds

`Wire.Input.data` allocates its exact 26-byte destination and writes the three
big-endian floating-point bit patterns directly. Decoding reads the `Data` storage
with unaligned loads, avoiding an intermediate byte array and three byte reductions.
Length, version, kind, finite-number, and +/-8192 coordinate checks remain in place.
Unaligned reads support `Data` slices whose indices or base addresses are offset.

`FrameDecoder.append(_:) -> [Data]` keeps its existing API. It streams through the
provided chunk with a cursor, validates the four-byte length before reserving payload
storage, and retains at most one incomplete payload (maximum 16,384 bytes) or three
header bytes. Complete frames bypass the accumulation buffer. Processing is O(bytes
received + frames produced), including arbitrary fragmentation; no consumed prefix
must be removed or reparsed on subsequent calls. Do not infer that Foundation's old
`Data.removeFirst` always moved bytes: the benchmark compares actual implementations.
An invalid header permanently fails that decoder; close the connection and create a
fresh decoder for a new connection.

`bufferedByteCount` exposes logical retained bytes for tests. Foundation allocation
rounding and metadata are additional. The argument and returned `[Data]` belong to
the caller; a call returning many frames can allocate proportionally to its input.
This is a bound on retained parser state, not a fixed bound on the entire call's
memory. Keep `NWConnection.receive(maximumLength: Wire.maxFrame + 4)` bounded too.

`InputBuffer` owns a fixed-capacity ring allocated once at initialization. Default
capacity is 64 packets, excluding the channel's one packet already in flight. Enqueue
and pop use O(1) index operations without shifting occupied elements. Storage is
O(capacity). It is a Swift value type: copying a live buffer can cause a one-time
O(capacity) copy on the next mutation. Keep one uniquely owned instance on the channel
queue; it deliberately provides no locking or dispatch of its own.

Only adjacent `.move` packets or adjacent `.scroll` packets merge. Their deltas add
and the newest timestamp survives. Every other kind, including future gesture or
control kinds, is a semantic barrier. Different motion kinds also block merging.
If a sum exceeds +/-8192, the new event becomes a separate packet when capacity
permits. A full queue can still accept a valid adjacent merge. Invalid input and full
capacity throw without mutating the queue. The owner must close on failure rather
than silently drop a drag-end, button, stop, or other barrier. Coalescing preserves
aggregate relative deltas and barriers, not original sample timing or acceleration
history. A future receiver that depends on per-sample timing should revisit this
policy before expanding it to more gesture kinds.

## Exact PeerChannel integration

The performance implementation did not edit `PeerChannel.swift`. The parent's
combined implementation now uses the ring and passes the debug suite. The required
integration, for reference, replaces the array and inline coalescing on its existing
serial queue:

```swift
private var pending = InputBuffer(capacity: 64)

private func enqueue(_ input: Wire.Input) {
    guard !closed, cipher != nil else { return }
    do {
        try pending.enqueue(input)
    } catch {
        finish("Connection too slow or input invalid. Reconnect to resume.")
        return
    }
    flush()
}

private func flush() {
    guard !closed, !writing, let input = pending.popFirst() else { return }
    do {
        let payload = try cipher!.seal(input)
        writing = true
        connection.send(content: Wire.frame(payload), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.writing = false
            if let error { self.finish(error.localizedDescription) } else { self.flush() }
        })
    } catch {
        finish("Could not encrypt input.")
    }
}
```

Keep the parent's authenticated-pairing guards where applicable. Keep
`pending.removeAll()` in `finish`; the ring implements it in O(1). Available API:

```swift
init(capacity: Int = 64)              // Requires capacity > 0.
mutating func enqueue(_ input: Wire.Input) throws
mutating func popFirst() -> Wire.Input?
mutating func removeAll()
let capacity: Int
private(set) var count: Int
var isEmpty: Bool
// Throws InputBuffer.Failure.full or .invalidInput.
```

No timer or batching delay is introduced: call `flush()` immediately and continue
on `.contentProcessed`. Keep `tcp.noDelay = true`. Seal only after popping a packet;
coalescing must precede encryption and sequence-number assignment. Do not merge
through a barrier or reprioritize heartbeats through button/gesture transitions.
The project generator already discovers `Shared/*.swift`; regenerate through the
parent's normal workflow if the new file is absent from either application target.

## Verification and reproducible measurements

Toolchain verified before building: Xcode 27.1 RC, build **27A9275**,
`/Applications/Xcode.app/Contents/Developer`; Apple Swift 6.4
(`swiftlang-6.4.0.34.1`). Host: Apple M3, `Mac15,13`, eight logical CPUs, 24 GiB RAM,
macOS 27.0.1 build 26A434. Builds used two jobs, local execution, and a distinct
disk-backed SwiftPM scratch directory. No Xcode application build, deployment, or
receiver restart was performed by this work.

```sh
xcodebuild -version
swift test --jobs 2 --scratch-path build/performance-spm
DUOTRACKPAD_BENCHMARKS=1 swift test -c release --jobs 2 \
  --scratch-path build/performance-spm
```

Debug verification: 22 tests, zero failures, one benchmark skipped. Release run with
benchmarks enabled: 22 tests, zero failures, zero skips. This includes existing
encrypted socket ordering, pairing-code rejection, heartbeat, replay, tampering,
and directional-key tests. A second debug run after the parent's ring integration,
new pairing flow, and new gesture kinds also passed 22 tests with one benchmark
skipped; output is in `build/performance-spm/integration-tests.log`. The dynamic
barrier test included the new kinds. Future channel edits still require rerunning
the suite.

New adversarial coverage includes every split of a framed payload, bytewise maximum
frames, offset `Data` storage, 2,000-frame bursts and deterministic fragmentation,
zero/oversize/UInt32-max headers followed by a 1 MB body, permanently failed decoders,
all input truncations, exact known wire bytes, invalid floating-point values,
20,000 FIFO/reference operations, wraparound, all known non-motion barriers,
full-queue failure atomicity, wire-limit overflow, newest timestamps, and clear/reuse.

`PerformanceTests.testReleaseBenchmarks` is opt-in and skips debug configurations.
It retains the original input/frame algorithms as local controls, runs one excluded
warm-up and nine timed batches per workload, uses `DispatchTime` monotonic timestamps,
normalizes by operations, and reports median, minimum, maximum, sample count, and
batch size. A checksum keeps decoded outputs observable. Results below are from one
release invocation, with methods run sequentially and no statistical confidence
claim. The full output is in `build/performance-spm/release-benchmarks.log` for this
checkout; rerunning produces fresh values.

| Workload | Original median ns/op | Current median ns/op | Current batch range ns/op |
| --- | ---: | ---: | ---: |
| Decode one 26-byte input | 61.0 | 10.1 | 10.1–10.2 |
| Encode one 26-byte input | 119.1 | 50.8 | 49.9–52.1 |
| Frame parsing, one packet per append | 233.2 | 109.3 | 108.1–112.8 |
| Frame parsing, 64 packets per append | 169.4 | 64.2 | 63.1–64.9 |
| Frame parsing, 4,096 packets per append | 165.6 | 57.3 | 56.2–59.1 |
| Frame parsing, one byte per append | 5969.7 | 1609.4 | 1605.3–1623.9 |
| FIFO pop + enqueue, depth 64 | 25.1 | 5.8 | 5.7–5.9 |
| FIFO pop + enqueue, depth 1,024 | 362.3 | 5.6 | 5.6–5.7 |
| Adjacent-motion enqueue | — | 4.1 | 4.0–4.1 |
| SessionCipher seal + authenticated open | — | 2151.6 | 2142.9–2168.3 |

Frame workloads use a 62-byte payload and four-byte length prefix, matching the
current encrypted packet size. Burst batches process 32,768 frames, including
allocation of returned frame arrays; the bytewise batches process 2,048 frames
from preconstructed one-byte chunks. Input and queue batches use 100,000 operations;
the cipher batch uses 16,384 round trips through in-memory client/host ciphers with
one directional-key setup per batch. One cipher operation includes both seal and
open, not a network round trip. FIFO workloads compare a constant-depth array's
`removeFirst`/append with ring pop/enqueue, using non-coalescible events. Depth 1,024
is an O(1) scaling check, not a proposal to increase the production queue to 1,024.
Adjacent-motion workload alternates +1/-1 deltas to avoid hitting the wire limit.

These tight-loop CPU results exclude touch collection, queue scheduling, radios,
TCP retransmission, socket completion, OS event dispatch, application handling, and
display refresh. They contain no measured touch-to-display latency. Min/max values
are batch-normalized variation, not event-latency percentiles. No resident-memory,
allocation-count, energy, or sustained-device measurement was performed.

## Remaining bottlenecks and follow-up measurements

The ring bounds the channel's pending packets. The parent also added a bounded ingress mailbox, so bursts no longer post an unbounded number of per-event dispatch closures before the transport ring. It uses a short lock, coalesces adjacent movement before scheduling, and has one drain notification outstanding. A full mailbox closes the channel rather than dropping button-up barriers. Those ingress changes were regression-tested but not included in the original microbenchmarks.

One in-flight `NWConnection.send` preserves ordering and naturally accumulates
coalescible motion while busy. Its `.contentProcessed` callback is local networking
progress, not receiver acknowledgment. Kernel/socket buffering and TCP head-of-line
blocking remain. The CPU benchmarks do not justify changing that policy, adding
an in-flight window, or switching transports without device measurements.

CryptoKit seal/open, nonce generation, sequence framing, and remaining `Data`
construction in `SessionCipher` cost more than the measured input encoding/parsing
alone. Retain authentication and strict ordering; profile allocations and actual
receiver event injection before further optimization. The receiver currently calls
its injector directly on the transport queue, so a slow injector can delay receive,
heartbeat, and socket completion work sharing that queue.

For end-to-end evidence, add monotonic local signposts at touch sampling, enqueue,
flush, receive/authentication, and event injection. Report queue residence separately
from heartbeat RTT and CPU costs. Cross-device timestamps require explicit clock
alignment and an uncertainty estimate; subtracting unrelated system uptimes cannot
produce valid one-way latency. Use a high-speed camera or instrumented display
response to measure touch-to-display, and test clean versus congested Wi-Fi plus
slow-receiver/barrier-heavy bursts. No such measurement was fabricated here.

## Parent integration after the benchmark run

The completed app now uses the ring, a lock-protected bounded ingress `InputMailbox` with one outstanding drain notification, cached receiver permission/display geometry, pooled touch-ring layers, and monotonic velocity-based pointer tuning. `PeerChannel` adds Instruments signposts around encryption/submission and input application. These parent changes were not included in the nanosecond baseline above; no extra speedup is inferred for them. Gesture and Keychain resumption regression tests extend the suite beyond the 22-test benchmark snapshot. Handshake version is now 2, while the fixed input layout remains version 1 with appended gesture kinds.
