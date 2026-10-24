import XCTest
import Network
import CryptoKit
@testable import DuoCore

final class TransportTests: XCTestCase {
    func testSavedIdentityReconnectsAfterCodeRotation() throws {
        let hostIdentity = try PairingIdentity(), clientIdentity = try PairingIdentity()
        for resume in [false, true] {
            let hostReady = expectation(description: "Host authenticated, resume=\(resume)")
            let clientReady = expectation(description: "Client authenticated, resume=\(resume)")
            let listener = try NWListener(using: PeerChannel.parameters, on: .any)
            var server: PeerChannel?, client: PeerChannel?
            listener.newConnectionHandler = { connection in
                let channel = PeerChannel(connection: connection, code: resume ? "87654321" : "01234567", isHost: true,
                    name: "Saved Mac", identity: hostIdentity, trustedPeers: resume ? [clientIdentity.publicKey] : [])
                server = channel
                channel.onReady = { _ in hostReady.fulfill() }
                channel.onTrust = { key, _ in XCTAssertEqual(key, clientIdentity.publicKey) }
                channel.start()
            }
            listener.stateUpdateHandler = { state in
                guard case .ready = state, let port = listener.port else { return }
                let channel = PeerChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: PeerChannel.parameters),
                    code: resume ? "" : "01234567", isHost: false, name: "Saved iPhone", identity: clientIdentity,
                    expectedPeer: resume ? hostIdentity.publicKey : nil)
                client = channel
                channel.onReady = { _ in clientReady.fulfill() }
                channel.onTrust = { key, _ in XCTAssertEqual(key, hostIdentity.publicKey) }
                channel.start()
            }
            listener.start(queue: PeerChannel.queue)
            wait(for: [hostReady, clientReady], timeout: 5)
            client?.cancel(); server?.cancel(); listener.cancel()
            PeerChannel.queue.sync {}
        }
    }

    func testUnrecognizedSavedClientNeverAuthenticates() throws {
        let rejected = expectation(description: "Unknown resume identity rejected")
        let clientRejected = expectation(description: "Client knows it must pair again")
        let hostIdentity = try PairingIdentity(), clientIdentity = try PairingIdentity()
        let listener = try NWListener(using: PeerChannel.parameters, on: .any)
        var server: PeerChannel?, client: PeerChannel?
        listener.newConnectionHandler = { connection in
            let channel = PeerChannel(connection: connection, code: "01234567", isHost: true, name: "Mac", identity: hostIdentity)
            server = channel
            channel.onReady = { _ in XCTFail("Unknown identity resumed") }
            channel.onClose = { _ in rejected.fulfill() }
            channel.start()
        }
        listener.stateUpdateHandler = { state in
            guard case .ready = state, let port = listener.port else { return }
            let channel = PeerChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: PeerChannel.parameters),
                code: "", isHost: false, name: "iPhone", identity: clientIdentity, expectedPeer: hostIdentity.publicKey)
            client = channel; channel.onReady = { _ in XCTFail("Unknown identity resumed") }
            channel.onClose = { reason in XCTAssertTrue(reason.contains("Pairing")); clientRejected.fulfill() }
            channel.start()
        }
        listener.start(queue: PeerChannel.queue)
        wait(for: [rejected, clientRejected], timeout: 5)
        client?.cancel(); server?.cancel(); listener.cancel()
        PeerChannel.queue.sync {}
    }
    func testRealSocketPairingInputOrderingAndHeartbeat() throws {
        let received = expectation(description: "Ordered authenticated input reached receiver")
        let heartbeat = expectation(description: "Round-trip heartbeat")
        heartbeat.assertForOverFulfill = false
        let listener = try NWListener(using: PeerChannel.parameters, on: .any)
        var server: PeerChannel?
        var client: PeerChannel?
        var kinds: [Wire.Kind] = []
        var movement = 0.0
        var scroll = 0.0
        listener.newConnectionHandler = { connection in
            let channel = PeerChannel(connection: connection, code: "01234567", isHost: true, name: "Test Mac")
            server = channel
            channel.onInput = { input in
                XCTAssertEqual(input.timestamp, 0, "Local touch timestamps must not leave the sender")
                kinds.append(input.kind)
                if input.kind == .move { movement += input.x }
                if input.kind == .scroll { scroll += input.y }
                if input.kind == .stop {
                    XCTAssertEqual(kinds.first, .dragStart)
                    XCTAssertEqual(kinds.suffix(5), [.dragEnd, .leftClick, .rightClick, .scroll, .stop])
                    XCTAssertEqual(movement, 125, accuracy: 0.001)
                    XCTAssertEqual(scroll, -6.5, accuracy: 0.001)
                    received.fulfill()
                }
            }
            channel.start()
        }
        listener.stateUpdateHandler = { state in
            guard case .ready = state, let port = listener.port else { return }
            let channel = PeerChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: PeerChannel.parameters), code: "01234567", isHost: false, name: "Test iPhone")
            client = channel
            channel.onReady = { name in
                XCTAssertEqual(name, "Test Mac")
                channel.send(.init(.dragStart))
                for _ in 0..<100 { channel.send(.init(.move, x: 1.25, y: -0.5)) }
                channel.send(.init(.dragEnd)); channel.send(.init(.leftClick)); channel.send(.init(.rightClick))
                channel.send(.init(.scroll, y: -6.5)); channel.send(.init(.stop))
            }
            channel.onLatency = { value in XCTAssertGreaterThanOrEqual(value, 0); heartbeat.fulfill() }
            channel.start()
        }
        listener.start(queue: PeerChannel.queue)
        wait(for: [received, heartbeat], timeout: 8)
        client?.cancel(); server?.cancel(); listener.cancel()
    }

    func testWrongCodeNeverAuthenticates() throws {
        let rejected = expectation(description: "Wrong code closes connection")
        rejected.assertForOverFulfill = false
        let listener = try NWListener(using: PeerChannel.parameters, on: .any)
        var server: PeerChannel?
        var client: PeerChannel?
        listener.newConnectionHandler = { connection in
            let channel = PeerChannel(connection: connection, code: "01234567", isHost: true, name: "Test Mac")
            server = channel
            channel.onReady = { _ in XCTFail("Incorrect pairing code authenticated") }
            channel.onInput = { _ in XCTFail("Unauthenticated input was delivered") }
            channel.onClose = { _ in rejected.fulfill() }
            channel.start()
        }
        listener.stateUpdateHandler = { state in
            guard case .ready = state, let port = listener.port else { return }
            let channel = PeerChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: PeerChannel.parameters), code: "99999999", isHost: false, name: "Test iPhone")
            client = channel
            channel.onReady = { _ in XCTFail("Incorrect pairing code authenticated") }
            channel.start()
        }
        listener.start(queue: PeerChannel.queue)
        wait(for: [rejected], timeout: 8)
        client?.cancel(); server?.cancel(); listener.cancel()
    }
}
