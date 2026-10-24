import XCTest
import CryptoKit
@testable import DuoCore

final class PerformanceTests: XCTestCase {
    func testInputKnownWireBytesAndSlicedStorage() throws {
        let input = Wire.Input(.move, x: 1, y: -2, timestamp: 0.5)
        let expected = Data([1, 1, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0,
                             0xc0, 0, 0, 0, 0, 0, 0, 0,
                             0x3f, 0xe0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(input.data, expected)
        var sliced = Data(repeating: 0xff, count: 3) + expected
        sliced.removeFirst(3)
        XCTAssertEqual(try Wire.Input(data: sliced), input)
        for input in [Wire.Input(.move, x: -0.0, y: 8192, timestamp: -.greatestFiniteMagnitude),
                      .init(.scroll, x: -8192, y: .leastNonzeroMagnitude)] {
            let decoded = try Wire.Input(data: input.data)
            XCTAssertEqual(decoded.x.bitPattern, input.x.bitPattern)
            XCTAssertEqual(decoded.y.bitPattern, input.y.bitPattern)
            XCTAssertEqual(decoded.timestamp.bitPattern, input.timestamp.bitPattern)
        }
    }

    func testRejectsAllTruncationsAndInvalidNumbers() {
        let bytes = Wire.Input(.move).data
        for count in 0..<Wire.Input.encodedSize {
            XCTAssertThrowsError(try Wire.Input(data: bytes.prefix(count)))
        }
        XCTAssertThrowsError(try Wire.Input(data: bytes + Data([0])))
        var wrongVersion = bytes
        wrongVersion[0] = 255
        XCTAssertThrowsError(try Wire.Input(data: wrongVersion))
        var wrongKind = bytes
        wrongKind[1] = 255
        XCTAssertThrowsError(try Wire.Input(data: wrongKind))
        for value in [Double.nan, .infinity, -.infinity, 8192.00001, -8192.00001] {
            XCTAssertThrowsError(try Wire.Input(data: Wire.Input(.move, x: value).data))
            XCTAssertThrowsError(try Wire.Input(data: Wire.Input(.move, y: value).data))
        }
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try Wire.Input(data: Wire.Input(.ping, timestamp: value).data))
        }
    }

    func testEverySplitIncludingMaxFrameAndNonzeroDataIndices() throws {
        let payload = Data((0..<127).map(UInt8.init))
        let framed = Wire.frame(payload)
        for split in 0...framed.count {
            var decoder = FrameDecoder()
            let first = try decoder.append(framed.prefix(split))
            let second = try decoder.append(framed.dropFirst(split))
            XCTAssertEqual(first + second, [payload])
            XCTAssertEqual(decoder.bufferedByteCount, 0)
        }
        var decoder = FrameDecoder()
        let maximum = Data(repeating: 0x5a, count: Wire.maxFrame)
        var outputs: [Data] = []
        for byte in Wire.frame(maximum) {
            outputs += try decoder.append(Data([byte]))
            XCTAssertLessThanOrEqual(decoder.bufferedByteCount, Wire.maxFrame)
        }
        XCTAssertEqual(outputs, [maximum])
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testLargeBatchAndDeterministicFragmentation() throws {
        let payloads = (0..<2000).map { index in Data(repeating: UInt8(index % 251), count: index % 193 + 1) }
        let bytes = payloads.reduce(into: Data()) { $0.append(Wire.frame($1)) }
        var decoder = FrameDecoder()
        XCTAssertEqual(try decoder.append(bytes), payloads)
        XCTAssertEqual(decoder.bufferedByteCount, 0)
        var state: UInt64 = 0x12345678
        var offset = 0
        var output: [Data] = []
        while offset < bytes.count {
            state = state &* 6364136223846793005 &+ 1
            let end = min(bytes.count, offset + Int(state % 397) + 1)
            output += try decoder.append(bytes[offset..<end])
            XCTAssertLessThanOrEqual(decoder.bufferedByteCount, Wire.maxFrame)
            offset = end
        }
        XCTAssertEqual(output, payloads)
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testInvalidLengthsFailBeforeBodyAccumulationAndStayFailed() throws {
        for header in [Data([0, 0, 0, 0]), Data([0, 0, 0x40, 1]), Data([255, 255, 255, 255])] {
            var decoder = FrameDecoder()
            XCTAssertTrue(try decoder.append(header.prefix(3)).isEmpty)
            XCTAssertThrowsError(try decoder.append(header.suffix(1) + Data(repeating: 1, count: 1_000_000)))
            XCTAssertLessThanOrEqual(decoder.bufferedByteCount, 4)
            XCTAssertThrowsError(try decoder.append(Wire.frame(Data([1]))))
            XCTAssertThrowsError(try decoder.append(Data()))
        }
        var decoder = FrameDecoder()
        XCTAssertThrowsError(try decoder.append(Wire.frame(Data([1])) + Data([0, 0, 0, 0])))
    }

    /// Opt-in microbenchmarks, with the original algorithms retained below as local controls.
    /// Run in release mode; no network/device latency is measured here.
    func testReleaseBenchmarks() throws {
        guard ProcessInfo.processInfo.environment["DUOTRACKPAD_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set DUOTRACKPAD_BENCHMARKS=1 and run swift test -c release --jobs 2")
        }
        #if DEBUG
        throw XCTSkip("Benchmarks require release optimization")
        #else
        let input = Wire.Input(.move, x: 1.25, y: -0.75, timestamp: 1234)
        let encoded = input.data
        let iterations = 100_000
        var checksum = 0.0
        try benchmark("input.decode.legacy", operations: iterations) {
            for _ in 0..<iterations { checksum += try legacyDecode(encoded).x }
        }
        try benchmark("input.decode.current", operations: iterations) {
            for _ in 0..<iterations { checksum += try Wire.Input(data: encoded).x }
        }
        benchmark("input.encode.legacy", operations: iterations) {
            for _ in 0..<iterations { checksum += Double(legacyEncode(input).count) }
        }
        benchmark("input.encode.current", operations: iterations) {
            for _ in 0..<iterations { checksum += Double(input.data.count) }
        }
        let payload = Data(repeating: 0x5a, count: 62) // Current encrypted packet size.
        let frame = Wire.frame(payload)
        let burstCount = 4096
        let burst = (0..<burstCount).reduce(into: Data()) { data, _ in data.append(frame) }
        for count in [1, 64, burstCount] {
            let chunk = Data(burst.prefix(count * frame.count))
            let repeats = max(1, 32_768 / count)
            try benchmark("frame.burst\(count).legacy", operations: count * repeats) {
                var decoder = LegacyFrameDecoder()
                for _ in 0..<repeats { checksum += Double(try decoder.append(chunk).count) }
            }
            try benchmark("frame.burst\(count).current", operations: count * repeats) {
                var decoder = FrameDecoder()
                for _ in 0..<repeats { checksum += Double(try decoder.append(chunk).count) }
            }
        }
        let fragments = frame.map { Data([$0]) }
        let fragmentedCount = 2048
        try benchmark("frame.bytewise.legacy", operations: fragmentedCount) {
            var decoder = LegacyFrameDecoder()
            for _ in 0..<fragmentedCount {
                for fragment in fragments { checksum += Double(try decoder.append(fragment).count) }
            }
        }
        try benchmark("frame.bytewise.current", operations: fragmentedCount) {
            var decoder = FrameDecoder()
            for _ in 0..<fragmentedCount {
                for fragment in fragments { checksum += Double(try decoder.append(fragment).count) }
            }
        }
        for capacity in [64, 1024] {
            let event = Wire.Input(.leftClick)
            try benchmark("fifo.depth\(capacity).ring", operations: iterations) {
                var buffer = InputBuffer(capacity: capacity)
                for _ in 0..<capacity { try buffer.enqueue(event) }
                for _ in 0..<iterations {
                    checksum += buffer.popFirst()!.x
                    try buffer.enqueue(event)
                }
            }
            benchmark("fifo.depth\(capacity).array", operations: iterations) {
                var buffer = Array(repeating: event, count: capacity)
                for _ in 0..<iterations {
                    checksum += buffer.removeFirst().x
                    buffer.append(event)
                }
            }
        }
        try benchmark("fifo.adjacentMotion.ring", operations: iterations) {
            var buffer = InputBuffer()
            for index in 0..<iterations {
                try buffer.enqueue(.init(.move, x: index % 2 == 0 ? 1 : -1))
            }
            checksum += buffer.popFirst()!.x
        }
        let key = SymmetricKey(data: Data(repeating: 0x42, count: 32))
        let cipherCount = 16_384
        try benchmark("cipher.sealOpen.current", operations: cipherCount) {
            var client = SessionCipher(key: key, isHost: false)
            var host = SessionCipher(key: key, isHost: true)
            for _ in 0..<cipherCount { checksum += try host.open(client.seal(input)).x }
        }
        print("BENCH checksum=\(checksum)")
        XCTAssertGreaterThan(checksum, 0)
        #endif
    }
}

private func benchmark(_ name: String, operations: Int, body: () throws -> Void) rethrows {
    try body() // Warm-up, excluded.
    var samples: [Double] = []
    for _ in 0..<9 {
        let start = DispatchTime.now().uptimeNanoseconds
        try body()
        let duration = DispatchTime.now().uptimeNanoseconds - start
        samples.append(Double(duration) / Double(operations))
    }
    samples.sort()
    print(String(format: "BENCH %@ median=%.1f ns/op min=%.1f max=%.1f samples=9 n=%d", name, samples[4], samples[0], samples[8], operations))
}

private func legacyEncode(_ input: Wire.Input) -> Data {
    var bytes = Data([UInt8(Wire.version), input.kind.rawValue])
    for number in [input.x, input.y, input.timestamp] {
        var bits = number.bitPattern.bigEndian
        withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) }
    }
    return bytes
}

private func legacyDecode(_ data: Data) throws -> Wire.Input {
    let bytes = [UInt8](data)
    guard bytes.count == 26, bytes[0] == Wire.version, let kind = Wire.Kind(rawValue: bytes[1]) else { throw Wire.Failure.invalidPacket }
    func number(_ offset: Int) -> Double {
        Double(bitPattern: bytes[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
    }
    let input = Wire.Input(kind, x: number(2), y: number(10), timestamp: number(18))
    guard input.isValid else { throw Wire.Failure.invalidPacket }
    return input
}

private struct LegacyFrameDecoder {
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length <= Wire.maxFrame else { throw Wire.Failure.invalidFrame }
            guard buffer.count >= length + 4 else { break }
            frames.append(Data(buffer.dropFirst(4).prefix(length)))
            buffer.removeFirst(length + 4)
        }
        return frames
    }
}
