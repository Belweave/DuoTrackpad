import XCTest
import CryptoKit
import Security
@testable import DuoCore

final class PairingTests: XCTestCase {
    func testKeychainIdentityAndPeersSurviveStoreRecreation() throws {
        let service = "app.duotrackpad.tests.\(UUID().uuidString)"
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
        let first = PairingStore(service: service)
        let identity = try first.identity()
        let peer = PairedPeer(publicKey: try PairingIdentity().publicKey, name: "Mac", serviceID: "bonjour", address: nil)
        try first.save(peer)
        let recreated = PairingStore(service: service)
        XCTAssertEqual(try recreated.identity().publicKey, identity.publicKey)
        XCTAssertEqual(try recreated.peers(), [peer])
        try recreated.forgetAll()
        XCTAssertEqual(try first.peers(), [])
        XCTAssertEqual(try first.identity().publicKey, identity.publicKey)
    }
    func testFreshSessionAndResumeUseMatchingKeysWithoutOldCode() throws {
        let client = try PairingIdentity(), host = try PairingIdentity()
        let a = Curve25519.KeyAgreement.PrivateKey(), b = Curve25519.KeyAgreement.PrivateKey()
        for resume in [false, true] {
            let ac = PairingHello(ephemeral: a.publicKey.rawRepresentation, identity: client.publicKey, name: "iPhone", resume: resume)
            let bh = PairingHello(ephemeral: b.publicKey.rawRepresentation, identity: host.publicKey, name: "Mac", resume: resume)
            let ak = try PairingHandshake.key(privateKey: a, identity: client, local: ac, remote: bh, code: "01234567", isHost: false)
            let bk = try PairingHandshake.key(privateKey: b, identity: host, local: bh, remote: ac, code: resume ? "87654321" : "01234567", isHost: true)
            var clientCipher = SessionCipher(key: ak, isHost: false), hostCipher = SessionCipher(key: bk, isHost: true)
            XCTAssertEqual(try hostCipher.open(clientCipher.seal(.init(.ready))), .init(.ready))
        }
    }
    func testClaimedIdentityWithoutPrivateKeyCannotResume() throws {
        let client = try PairingIdentity(), host = try PairingIdentity(), attacker = try PairingIdentity()
        let a = Curve25519.KeyAgreement.PrivateKey(), b = Curve25519.KeyAgreement.PrivateKey()
        let ac = PairingHello(ephemeral: a.publicKey.rawRepresentation, identity: client.publicKey, name: "iPhone", resume: true)
        let bh = PairingHello(ephemeral: b.publicKey.rawRepresentation, identity: host.publicKey, name: "Mac", resume: true)
        let forged = try PairingHandshake.key(privateKey: a, identity: attacker, local: ac, remote: bh, code: "", isHost: false)
        let expected = try PairingHandshake.key(privateKey: b, identity: host, local: bh, remote: ac, code: "", isHost: true)
        var sender = SessionCipher(key: forged, isHost: false), receiver = SessionCipher(key: expected, isHost: true)
        XCTAssertThrowsError(try receiver.open(sender.seal(.init(.ready))))
    }
    func testNoResumeDowngrade() throws {
        let client = try PairingIdentity(), host = try PairingIdentity()
        let a = Curve25519.KeyAgreement.PrivateKey(), b = Curve25519.KeyAgreement.PrivateKey()
        let ac = PairingHello(ephemeral: a.publicKey.rawRepresentation, identity: client.publicKey, name: "iPhone", resume: true)
        let bh = PairingHello(ephemeral: b.publicKey.rawRepresentation, identity: host.publicKey, name: "Mac", resume: false)
        XCTAssertThrowsError(try PairingHandshake.key(privateKey: a, identity: client, local: ac, remote: bh, code: "01234567", isHost: false))
    }
}
