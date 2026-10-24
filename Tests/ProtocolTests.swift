import XCTest
import CryptoKit
@testable import DuoCore

final class ProtocolTests: XCTestCase {
    func testPartialFramesAndMultiplePackets() throws {
        var decoder = FrameDecoder()
        let a = Data("hello".utf8), b = Data("world!".utf8)
        let bytes = Wire.frame(a) + Wire.frame(b)
        XCTAssertTrue(try decoder.append(bytes.prefix(2)).isEmpty)
        XCTAssertTrue(try decoder.append(bytes.dropFirst(2).prefix(4)).isEmpty)
        XCTAssertEqual(try decoder.append(bytes.dropFirst(6)), [a, b])
    }
    func testRejectsOversizeFrames() {
        var decoder = FrameDecoder()
        XCTAssertThrowsError(try decoder.append(Data([0, 1, 0, 0])))
    }
    func testEveryInputRoundTrips() throws {
        for raw in UInt8(1)...11 {
            let input = Wire.Input(Wire.Kind(rawValue: raw)!, x: -23.25, y: 81.75, timestamp: 1234)
            XCTAssertEqual(try Wire.Input(data: input.data), input)
        }
    }
    func testRejectsMalformedAndNonfiniteInput() {
        XCTAssertThrowsError(try Wire.Input(data: Data([1, 1])))
        XCTAssertThrowsError(try Wire.Input(data: Wire.Input(.move, x: .nan).data))
        XCTAssertThrowsError(try Wire.Input(data: Wire.Input(.move, x: 9000).data))
    }
    func testKeyAgreementEncryptionAndDirectionalKeys() throws {
        let a = Curve25519.KeyAgreement.PrivateKey(), b = Curve25519.KeyAgreement.PrivateKey()
        let ak = try Wire.key(privateKey: a, peer: b.publicKey.rawRepresentation, code: "01234567")
        let bk = try Wire.key(privateKey: b, peer: a.publicKey.rawRepresentation, code: "01234567")
        var client = SessionCipher(key: ak, isHost: false), host = SessionCipher(key: bk, isHost: true)
        let input = Wire.Input(.move, x: 13.25, y: -4.75)
        let packet = try client.seal(input)
        XCTAssertEqual(try host.open(packet), input)
        XCTAssertThrowsError(try host.open(packet), "Replays must be rejected")
        XCTAssertEqual(try client.open(host.seal(.init(.ready))), .init(.ready))
        XCTAssertThrowsError(try client.open(packet), "Wrong direction must fail authentication")
    }
    func testWrongCodeAndTamperingFail() throws {
        let a = Curve25519.KeyAgreement.PrivateKey(), b = Curve25519.KeyAgreement.PrivateKey()
        let ak = try Wire.key(privateKey: a, peer: b.publicKey.rawRepresentation, code: "01234567")
        let bk = try Wire.key(privateKey: b, peer: a.publicKey.rawRepresentation, code: "99999999")
        var client = SessionCipher(key: ak, isHost: false), host = SessionCipher(key: bk, isHost: true)
        let packet = try client.seal(.init(.leftClick))
        XCTAssertThrowsError(try host.open(packet))
        var correct = SessionCipher(key: ak, isHost: true)
        var tampered = packet; tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try correct.open(tampered))
        XCTAssertEqual(try correct.open(packet), .init(.leftClick))
    }
}
