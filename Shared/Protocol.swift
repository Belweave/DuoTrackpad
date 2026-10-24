import Foundation
import CryptoKit

// The transport and input vocabulary are independent of the host's event injection API.
enum Wire {
    static let service = "_duotrackpad._tcp"
    static let version = 1
    static let port: UInt16 = 48571
    static let maxFrame = 16_384

    struct Hello: Codable {
        var version: Int = Wire.version
        var publicKey: Data
        var name: String
    }

    enum Kind: UInt8 {
        case move = 1, scroll, leftClick, rightClick, dragStart, dragEnd, ping, pong, ready, stop, hostStatus
        case scrollBegin, scrollEnd, action, zoom, rotate
    }

    struct Input: Equatable {
        var kind: Kind
        var x: Double = 0
        var y: Double = 0
        var timestamp: Double = 0

        static let encodedSize = 26

        var isValid: Bool {
            x.isFinite && y.isFinite && timestamp.isFinite && abs(x) <= 8192 && abs(y) <= 8192
        }

        var data: Data {
            var data = Data(count: Self.encodedSize)
            data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                bytes[0] = UInt8(Wire.version)
                bytes[1] = kind.rawValue
                bytes.storeBytes(of: x.bitPattern.bigEndian, toByteOffset: 2, as: UInt64.self)
                bytes.storeBytes(of: y.bitPattern.bigEndian, toByteOffset: 10, as: UInt64.self)
                bytes.storeBytes(of: timestamp.bitPattern.bigEndian, toByteOffset: 18, as: UInt64.self)
            }
            return data
        }

        init(_ kind: Kind, x: Double = 0, y: Double = 0, timestamp: Double = 0) {
            self.kind = kind; self.x = x; self.y = y; self.timestamp = timestamp
        }

        init(data: Data) throws {
            self = try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                guard bytes.count == Self.encodedSize, bytes[0] == Wire.version,
                      let kind = Kind(rawValue: bytes[1]) else { throw Failure.invalidPacket }
                func number(_ offset: Int) -> Double {
                    Double(bitPattern: UInt64(bigEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self)))
                }
                let input = Self(kind, x: number(2), y: number(10), timestamp: number(18))
                guard input.isValid else { throw Failure.invalidPacket }
                return input
            }
        }
    }

    enum Failure: Error { case invalidPacket, invalidFrame, invalidSequence }

    static func key(privateKey: Curve25519.KeyAgreement.PrivateKey, peer: Data, code: String) throws -> SymmetricKey {
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: peer))
        return secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(code.utf8), sharedInfo: Data("DuoTrackpad/1".utf8), outputByteCount: 32)
    }

    static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var result = withUnsafeBytes(of: &length) { Data($0) }
        result.append(payload)
        return result
    }
}

/// Incremental framing with at most one incomplete frame retained, independent of receive chunk size.
/// Confine mutation to the channel queue. After a framing error, discard the decoder with the connection.
struct FrameDecoder {
    private var header: UInt32 = 0
    private var headerByteCount = 0
    private var expectedLength = 0
    private var payload = Data()
    private var failed = false

    /// Logical retained bytes; output frames belong to the caller, not the decoder.
    var bufferedByteCount: Int { headerByteCount + payload.count }

    mutating func append(_ data: Data) throws -> [Data] {
        guard !failed else { throw Wire.Failure.invalidFrame }
        return try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var frames: [Data] = []
            var cursor = 0
            while cursor < bytes.count {
                if expectedLength == 0 {
                    if headerByteCount == 0, bytes.count - cursor >= 4 {
                        header = UInt32(bigEndian: bytes.loadUnaligned(fromByteOffset: cursor, as: UInt32.self))
                        cursor += 4
                        headerByteCount = 4
                    } else {
                        while headerByteCount < 4, cursor < bytes.count {
                            header = (header << 8) | UInt32(bytes[cursor])
                            headerByteCount += 1
                            cursor += 1
                        }
                        guard headerByteCount == 4 else { break }
                    }
                    guard header > 0, header <= UInt32(Wire.maxFrame) else {
                        failed = true
                        payload = Data()
                        throw Wire.Failure.invalidFrame
                    }
                    expectedLength = Int(header)
                    header = 0
                    headerByteCount = 0
                }

                let available = bytes.count - cursor
                if payload.isEmpty, available >= expectedLength {
                    // Complete frames bypass the accumulation buffer, including coalesced TCP receives.
                    frames.append(Data(bytes: bytes.baseAddress!.advanced(by: cursor), count: expectedLength))
                    cursor += expectedLength
                    expectedLength = 0
                } else {
                    let count = min(expectedLength - payload.count, available)
                    if count > 0 {
                        if payload.isEmpty { payload.reserveCapacity(expectedLength) }
                        payload.append(bytes.baseAddress!.advanced(by: cursor).assumingMemoryBound(to: UInt8.self), count: count)
                        cursor += count
                    }
                    if payload.count == expectedLength {
                        frames.append(payload)
                        payload = Data()
                        expectedLength = 0
                    }
                }
            }
            return frames
        }
    }
}

// Separate direction keys prevent nonce reuse between the client and receiver.
struct SessionCipher {
    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private var outgoing: UInt64 = 0
    private var incoming: UInt64 = 0

    init(key: SymmetricKey, isHost: Bool) {
        func directional(_ name: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(inputKeyMaterial: key, info: Data(name.utf8), outputByteCount: 32)
        }
        sendKey = directional(isHost ? "host" : "client")
        receiveKey = directional(isHost ? "client" : "host")
    }

    mutating func seal(_ input: Wire.Input) throws -> Data {
        var counter = outgoing.bigEndian
        var payload = withUnsafeBytes(of: &counter) { Data($0) }
        payload.append(input.data)
        outgoing += 1
        return try ChaChaPoly.seal(payload, using: sendKey).combined
    }

    mutating func open(_ data: Data) throws -> Wire.Input {
        let plaintext = try ChaChaPoly.open(.init(combined: data), using: receiveKey)
        guard plaintext.count == 34 else { throw Wire.Failure.invalidPacket }
        let sequence = plaintext.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard sequence == incoming else { throw Wire.Failure.invalidSequence }
        let input = try Wire.Input(data: Data(plaintext.dropFirst(8)))
        incoming += 1
        return input
    }
}
