import Foundation
import Network
import CryptoKit
import OSLog

/// All channel state is confined to one queue. UIKit never waits for networking.
final class PeerChannel: @unchecked Sendable {
    private static let log = Logger(subsystem: "app.duotrackpad", category: "transport")
    private static let signposter = OSSignposter(subsystem: "app.duotrackpad", category: "input")
    static let queue = DispatchQueue(label: "app.duotrackpad.transport", qos: .userInteractive)
    let connection: NWConnection
    private let code: String
    private let isHost: Bool
    private let name: String
    private let identity: PairingIdentity
    private let trustedPeers: Set<Data>
    private let expectedPeer: Data?
    private var localHello: PairingHello?
    private var remoteIdentity: Data?
    private var rejecting = false
    private let privateKey = Curve25519.KeyAgreement.PrivateKey()
    private var decoder = FrameDecoder()
    private var cipher: SessionCipher?
    private var pending = InputBuffer()
    private let mailbox = InputMailbox()
    private var writing = false
    private var closed = false
    private var authenticated = false
    private var heartbeat: DispatchSourceTimer?
    private var lastReceived = ProcessInfo.processInfo.systemUptime
    private let startedAt = ProcessInfo.processInfo.systemUptime
    var onReady: ((String) -> Void)?
    var onInput: ((Wire.Input) -> Void)?
    var onLatency: ((Double) -> Void)?
    var onClose: ((String) -> Void)?
    var onTrust: ((Data, String) -> Void)?

    static var parameters: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    init(connection: NWConnection, code: String, isHost: Bool, name: String,
         identity: PairingIdentity? = nil, trustedPeers: Set<Data> = [], expectedPeer: Data? = nil) {
        self.connection = connection; self.code = code; self.isHost = isHost; self.name = name
        self.identity = identity ?? (try! PairingIdentity())
        self.trustedPeers = trustedPeers; self.expectedPeer = expectedPeer
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Self.log.info("Socket ready; host: \(self.isHost)")
                do {
                    if !self.isHost { try self.sendHello(resume: self.expectedPeer != nil) }
                    self.receive()
                } catch { self.finish("Could not start pairing.") }
            case .failed(let error): self.finish(error.localizedDescription)
            case .waiting(let error): self.finish("Network unavailable: \(error.localizedDescription). Check Local Network access and the Mac address.")
            case .cancelled: self.finish("Disconnected")
            default: break
            }
        }
        connection.start(queue: Self.queue)
        Self.queue.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, !self.authenticated else { return }
            self.finish("Pairing timed out. Check the code on your Mac.")
        }
    }

    func send(_ input: Wire.Input) {
        guard mailbox.submit(input) else { return }
        Self.queue.async { [weak self] in self?.drainMailbox() }
    }

    private func drainMailbox() {
        do {
            for _ in 0..<64 {
                guard let input = try mailbox.next(), !closed else { return }
                enqueue(input)
            }
            Self.queue.async { [weak self] in self?.drainMailbox() }
        } catch { finish("Connection too slow. Reconnect to resume.") }
    }

    func cancel() { Self.queue.async { [weak self] in self?.finish("Disconnected") } }

    private func sendHello(resume: Bool) throws {
        let hello = PairingHello(ephemeral: privateKey.publicKey.rawRepresentation, identity: identity.publicKey, name: name, resume: resume)
        localHello = hello
        connection.send(content: Wire.frame(try JSONEncoder().encode(hello)), completion: .contentProcessed { [weak self] error in
            if let error { self?.finish(error.localizedDescription) }
        })
    }

    private func enqueue(_ input: Wire.Input) {
        guard !closed, cipher != nil else { return }
        do { try pending.enqueue(input) }
        catch { finish("Connection too slow. Reconnect to resume."); return }
        flush()
    }

    private func flush() {
        guard !closed, !writing, var input = pending.popFirst() else { return }
        // Touch timestamps and system boot-relative time stay on this device.
        if input.kind != .ping && input.kind != .pong { input.timestamp = 0 }
        do {
            let interval = Self.signposter.beginInterval("EncryptAndSubmit")
            let payload = try cipher!.seal(input)
            writing = true
            connection.send(content: Wire.frame(payload), completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                self.writing = false
                if let error { self.finish(error.localizedDescription) } else { self.flush() }
            })
            Self.signposter.endInterval("EncryptAndSubmit", interval)
        } catch { finish("Could not encrypt input.") }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Wire.maxFrame + 4) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            do {
                if let data {
                    for frame in try self.decoder.append(data) { try self.process(frame) }
                }
                if complete || error != nil { self.finish("Connection lost") } else { self.receive() }
            } catch { self.finish("Pairing could not be verified. Enter the current code on your Mac to pair again.") }
        }
    }

    private var peerName = "Device"
    private func process(_ data: Data) throws {
        guard !rejecting else { return }
        lastReceived = ProcessInfo.processInfo.systemUptime
        if cipher == nil {
            let hello = try JSONDecoder().decode(PairingHello.self, from: data)
            if isHost {
                if hello.resume, !trustedPeers.contains(hello.identity) {
                    // Return an explicit mode rejection so a revoked client asks for a code instead of retrying forever.
                    rejecting = true
                    let rejection = PairingHello(ephemeral: privateKey.publicKey.rawRepresentation,
                        identity: identity.publicKey, name: name, resume: false)
                    connection.send(content: Wire.frame(try JSONEncoder().encode(rejection)), completion: .contentProcessed { [weak self] _ in
                        self?.finish("Saved pairing is no longer trusted. Pair again using the current code.")
                    })
                    return
                }
                try sendHello(resume: hello.resume)
            } else if let expectedPeer {
                guard hello.identity == expectedPeer, hello.resume else { throw Wire.Failure.invalidPacket }
            }
            guard let localHello else { throw Wire.Failure.invalidPacket }
            peerName = hello.name
            remoteIdentity = hello.identity
            cipher = SessionCipher(key: try PairingHandshake.key(privateKey: privateKey, identity: identity,
                local: localHello, remote: hello, code: code, isHost: isHost), isHost: isHost)
            enqueue(.init(.ready))
            return
        }
        let input = try cipher!.open(data)
        if !authenticated {
            guard input.kind == .ready else { throw Wire.Failure.invalidPacket }
            authenticated = true
            Self.log.info("Encrypted handshake complete; host: \(self.isHost)")
            onReady?(peerName)
            if let remoteIdentity { onTrust?(remoteIdentity, peerName) }
            startHeartbeat()
            return
        }
        switch input.kind {
        case .ping: enqueue(.init(.pong, timestamp: input.timestamp))
        case .pong: onLatency?((ProcessInfo.processInfo.systemUptime - startedAt - input.timestamp) * 1000)
        case .ready: throw Wire.Failure.invalidPacket
        default:
            let interval = Self.signposter.beginInterval("ApplyInput")
            onInput?(input)
            Self.signposter.endInterval("ApplyInput", interval)
        }
    }

    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: Self.queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.lastReceived > 5 { self.finish("Connection lost"); return }
            self.enqueue(.init(.ping, timestamp: now - self.startedAt))
        }
        heartbeat = timer
        timer.resume()
    }

    private func finish(_ reason: String) {
        guard !closed else { return }
        closed = true
        mailbox.close()
        Self.log.info("Connection closed; host: \(self.isHost), reason: \(reason, privacy: .public)")
        heartbeat?.cancel(); heartbeat = nil
        pending.removeAll(); connection.stateUpdateHandler = nil
        connection.cancel()
        onClose?(reason)
        onReady = nil; onInput = nil; onLatency = nil; onClose = nil; onTrust = nil
    }
}
