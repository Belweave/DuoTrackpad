import SwiftUI
import Network
import UIKit

struct NearbyMac: Identifiable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    var address: String? {
        if case .hostPort(let host, _) = endpoint { return "\(host)" }
        return nil
    }
}

@MainActor
final class TrackpadModel: ObservableObject {
    @Published var hosts: [NearbyMac] = []
    @Published var status = "Find your Mac"
    @Published var connected = false
    @Published var connecting = false
    @Published var hostName = ""
    @Published var latency: Double?
    @Published var hostPermission: Bool?
    @Published var showSettings = false
    @Published var error: String?
    @Published var discoveryError: String?
    @Published private(set) var savedMac: PairedPeer?
    @AppStorage("sensitivity") var sensitivity = 1.6
    @AppStorage("naturalScroll") var naturalScroll = true
    @AppStorage("haptics") var haptics = true
    @AppStorage("pointerAcceleration") var pointerAcceleration = true
    @AppStorage("scrollSpeed") var scrollSpeed = 1.0
    @AppStorage("threeFingerDrag") var threeFingerDrag = false
    private let store = PairingStore()
    private var identity: PairingIdentity?
    private var browser: NWBrowser?
    private var channel: PeerChannel?
    private var generation = UUID()
    private var retry: Task<Void, Never>?
    private var retryCount = 0
    private var active = true
    private var wantsConnection = true
    private var pointer = PointerResponse()

    init() {
        do { identity = try store.identity(); savedMac = try store.peers().last }
        catch { self.error = "Saved pairing could not be read from Keychain. Unlock your iPhone and try again." }
    }

    func activate() { active = true; browse(); reconnect() }
    func suspend() { active = false; closeChannel(); browser?.cancel(); browser = nil }

    func browse() {
        browser?.cancel()
        let browser = NWBrowser(for: .bonjour(type: Wire.service, domain: nil), using: PeerChannel.parameters)
        discoveryError = nil
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let hosts = results.compactMap { result -> NearbyMac? in
                guard case let .service(name, type, domain, _) = result.endpoint else { return nil }
                return NearbyMac(id: name + type + domain, name: name, endpoint: result.endpoint)
            }.sorted { $0.name < $1.name }
            Task { @MainActor in self?.hosts = hosts; self?.reconnect() }
        }
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error), .waiting(let error):
                Task { @MainActor in self?.discoveryError = "Local discovery: \(error.localizedDescription). Check Local Network access in Settings." }
            default: break
            }
        }
        self.browser = browser
        browser.start(queue: PeerChannel.queue)
    }

    func reconnect() {
        guard active, wantsConnection, !connected, !connecting, retry == nil, let savedMac else { return }
        if let host = hosts.first(where: { $0.id == savedMac.serviceID }) {
            open(host, code: "", expectedPeer: savedMac.publicKey)
        } else if let address = savedMac.address {
            open(NearbyMac(id: savedMac.serviceID, name: savedMac.name,
                endpoint: .hostPort(host: .init(address), port: .init(rawValue: Wire.port)!)), code: "", expectedPeer: savedMac.publicKey)
        } else { status = "Looking for \(savedMac.name)…" }
    }

    func connectAddress(_ address: String, code: String) {
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host.utf8.count <= 253 else { error = "Enter your Mac's local IP address or hostname."; return }
        connect(NearbyMac(id: host, name: host, endpoint: .hostPort(host: .init(host), port: .init(rawValue: Wire.port)!)), code: code)
    }

    func connect(_ host: NearbyMac, code: String) {
        guard code.count == 8, code.allSatisfy(\.isNumber) else { error = "Enter the eight-digit code on your Mac."; return }
        wantsConnection = true; retryCount = 0
        open(host, code: code, expectedPeer: nil)
    }

    private func open(_ host: NearbyMac, code: String, expectedPeer: Data?) {
        closeChannel()
        guard let identity else { error = "Pairing identity is unavailable. Unlock your iPhone and relaunch Duo Trackpad."; return }
        error = nil; connecting = true; status = expectedPeer == nil ? "Pairing…" : "Reconnecting…"; hostName = host.name
        let id = UUID(); generation = id
        let channel = PeerChannel(connection: NWConnection(to: host.endpoint, using: PeerChannel.parameters), code: code,
            isHost: false, name: UIDevice.current.name, identity: identity, expectedPeer: expectedPeer)
        channel.onTrust = { [weak self] key, name in
            Task { @MainActor in
                guard let self, self.generation == id else { return }
                let peer = PairedPeer(publicKey: key, name: name, serviceID: host.id, address: host.address)
                do { try self.store.save(peer); self.savedMac = peer }
                catch { self.error = "Connected, but Keychain could not save pairing. Unlock your iPhone and pair again." }
            }
        }
        channel.onReady = { [weak self] name in
            Task { @MainActor in
                guard let self, self.generation == id else { return }
                self.connected = true; self.connecting = false; self.status = name; self.hostName = name; self.retryCount = 0
                self.showSettings = false; UIApplication.shared.isIdleTimerDisabled = true
                if self.haptics { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
            }
        }
        channel.onLatency = { [weak self] value in
            Task { @MainActor in guard self?.generation == id else { return }; self?.latency = value }
        }
        channel.onInput = { [weak self] input in
            guard input.kind == .hostStatus else { return }
            Task { @MainActor in guard self?.generation == id else { return }; self?.hostPermission = input.x == 1 }
        }
        channel.onClose = { [weak self] reason in
            Task { @MainActor in
                guard let self, self.generation == id else { return }
                self.connected = false; self.connecting = false; self.status = "Disconnected"
                self.latency = nil; self.hostPermission = nil; self.channel = nil; self.pointer.reset()
                UIApplication.shared.isIdleTimerDisabled = false
                self.error = reason
                if reason.contains("Pairing") { self.wantsConnection = false; self.showSettings = true }
                else { self.scheduleReconnect() }
            }
        }
        self.channel = channel; channel.start()
    }

    private func scheduleReconnect() {
        guard active, wantsConnection, savedMac != nil else { return }
        retryCount += 1
        let delay = min(8, pow(2, Double(min(retryCount - 1, 3))))
        status = "Reconnecting…"
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.retry = nil; self?.reconnect()
        }
    }

    private func closeChannel() {
        retry?.cancel(); retry = nil
        generation = UUID(); channel?.cancel(); channel = nil
        connected = false; connecting = false; latency = nil; hostPermission = nil; pointer.reset()
        UIApplication.shared.isIdleTimerDisabled = false
    }
    func disconnect() { wantsConnection = false; closeChannel(); status = "Disconnected" }
    func resumeSavedConnection() { wantsConnection = true; retryCount = 0; reconnect() }
    func forgetMac() {
        disconnect()
        do { try store.forgetAll(); savedMac = nil; error = nil; status = "Find your Mac" }
        catch { self.error = "Keychain could not remove saved pairing. Try again after unlocking." }
    }

    func send(_ input: Wire.Input) {
        guard connected else { return }
        var input = input
        if input.kind == .move {
            let result = pointer.apply(x: input.x, y: input.y, timestamp: input.timestamp,
                                       sensitivity: sensitivity, accelerated: pointerAcceleration)
            input.x = result.x; input.y = result.y
        }
        if input.kind == .scroll || input.kind == .scrollEnd {
            let factor = (naturalScroll ? -1.0 : 1.0) * scrollSpeed
            input.x *= factor; input.y *= factor
        }
        channel?.send(input)
    }
}
