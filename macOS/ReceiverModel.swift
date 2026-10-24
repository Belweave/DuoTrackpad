import AppKit
import SwiftUI
import Network
import ApplicationServices
import OSLog

@MainActor
final class ReceiverModel: ObservableObject {
    nonisolated private static let log = Logger(subsystem: "app.duotrackpad", category: "receiver")
    @Published var code = ReceiverModel.newCode()
    @Published var connectedName: String?
    @Published var listening = false
    @Published var trusted = AXIsProcessTrusted()
    @Published var error: String?
    @Published var latency: Double?
    @Published var paused = false
    @Published var pairedCount = 0
    private var listener: NWListener?
    private var channel: PeerChannel?
    private let injector = EventInjector()
    private var failures: [Date] = []
    private var codeDate = Date()
    private var timer: Timer?
    private var sessionID = UUID()
    private let store = PairingStore()
    private var identity: PairingIdentity?
    private var trustedPeers: Set<Data> = []

    init() {
        do {
            identity = try store.identity()
            trustedPeers = Set(try store.peers().map(\.publicKey)); pairedCount = trustedPeers.count
        } catch { self.error = "Keychain pairing could not be loaded. Unlock your Mac and restart Duo Receiver." }
        injector.onControlError = { [weak self] message in Task { @MainActor in self?.error = message } }
        start()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if self.trusted != trusted {
                    self.trusted = trusted
                    let injector = self.injector
                    PeerChannel.queue.async { injector.setTrusted(trusted) }
                    self.channel?.send(.init(.hostStatus, x: trusted ? 1 : 0))
                }
                if self.channel == nil, Date().timeIntervalSince(self.codeDate) > 300 { self.rotateCode() }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.disconnect() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        }
    }

    static func newCode() -> String { String(format: "%08u", UInt32.random(in: 0...99_999_999)) }
    func rotateCode() {
        code = Self.newCode(); codeDate = Date()
        Self.log.info("Pairing code rotated")
    }

    func start() {
        guard identity != nil else { return }
        listener?.cancel(); error = nil
        do {
            let listener = try NWListener(using: PeerChannel.parameters, on: .init(rawValue: Wire.port)!)
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: Wire.service)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready: self.listening = true
                    case .failed(let error): self.listening = false; self.error = error.localizedDescription
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            self.listener = listener; listener.start(queue: PeerChannel.queue)
        } catch { self.error = error.localizedDescription }
    }

    private func accept(_ connection: NWConnection) {
        failures.removeAll { Date().timeIntervalSince($0) > 60 }
        guard channel == nil, !paused, failures.count < 5, let identity else { connection.cancel(); return }
        if Date().timeIntervalSince(codeDate) > 300 { rotateCode() }
        let id = UUID(); sessionID = id
        let channel = PeerChannel(connection: connection, code: code, isHost: true, name: Host.current().localizedName ?? "Mac",
                                  identity: identity, trustedPeers: trustedPeers)
        channel.onTrust = { [weak self] key, name in
            Task { @MainActor in
                guard let self, self.sessionID == id else { return }
                do {
                    try self.store.save(PairedPeer(publicKey: key, name: name, serviceID: key.base64EncodedString()))
                    self.trustedPeers.insert(key); self.pairedCount = self.trustedPeers.count
                } catch { self.error = "Connected, but Keychain could not save this iPhone's pairing." }
            }
        }
        channel.onReady = { [weak self] name in
            Task { @MainActor in
                guard let self, self.sessionID == id else { return }
                self.connectedName = name; self.error = nil; self.failures.removeAll()
                self.channel?.send(.init(.hostStatus, x: self.trusted ? 1 : 0))
            }
        }
        let injector = self.injector
        channel.onInput = { input in injector.consume(input) }
        channel.onLatency = { [weak self] value in
            Task { @MainActor in guard self?.sessionID == id else { return }; self?.latency = value }
        }
        channel.onClose = { [weak self] reason in
            injector.release()
            Task { @MainActor in
                guard let self, self.sessionID == id else { return }
                if self.connectedName == nil {
                    self.failures.append(Date())
                    self.error = self.failures.count >= 5 ? "Too many attempts. Pairing is paused for one minute." : reason
                }
                self.channel = nil; self.connectedName = nil; self.latency = nil; self.rotateCode()
            }
        }
        self.channel = channel; channel.start()
    }

    func disconnect() {
        sessionID = UUID(); channel?.cancel(); channel = nil
        connectedName = nil; latency = nil; rotateCode()
        let injector = self.injector
        PeerChannel.queue.async { injector.release() }
    }
    func togglePause() { paused.toggle(); if paused { disconnect() } }
    func forgetDevices() {
        disconnect()
        do { try store.forgetAll(); trustedPeers.removeAll(); pairedCount = 0 }
        catch { self.error = "Keychain could not remove saved devices." }
    }
    func shutdown() {
        disconnect()
        // Termination must wait for the button-up event rather than abandon queued cleanup.
        let injector = self.injector
        PeerChannel.queue.sync { injector.release() }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        let injector = self.injector, trusted = self.trusted
        PeerChannel.queue.async { injector.setTrusted(trusted) }
        channel?.send(.init(.hostStatus, x: trusted ? 1 : 0))
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}
