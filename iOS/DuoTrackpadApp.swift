import SwiftUI

@main
struct DuoTrackpadApp: App {
    @StateObject private var model = TrackpadModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            TrackpadSurface(model: model)
                // Deliberate immersive input surface: the user requires the entire display to track.
                // Informational overlays use UIKit safe areas and live reserved regions.
                .ignoresSafeArea()
                .sheet(isPresented: $model.showSettings) { ConnectionSheet(model: model) }
                .task { model.activate() }
                .onChange(of: phase) { _, value in
                    if value == .background { model.suspend() }
                    else if value == .active { model.activate() }
                }
        }
    }
}

struct ConnectionSheet: View {
    @ObservedObject var model: TrackpadModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var code = ""
    @State private var manualAddress = ""
    @State private var manual = false
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if model.connected {
                    Section {
                        Label(model.hostName, systemImage: "desktopcomputer").foregroundStyle(.primary)
                        if let latency = model.latency {
                            LabeledContent("Round-trip latency", value: "\(latency.formatted(.number.precision(.fractionLength(1)))) ms")
                        }
                        Label("Encrypted local connection", systemImage: "lock.shield")
                        if model.hostPermission == false {
                            Label("On your Mac, enable Duo Receiver in System Settings → Privacy & Security → Accessibility to allow mouse control.", systemImage: "hand.raised")
                                .font(.subheadline).foregroundStyle(.orange)
                        }
                        Button("Disconnect", role: .destructive) { model.disconnect() }
                    } header: { Text("Connected") }
                } else {
                    if let saved = model.savedMac {
                        Section("Remembered Mac") {
                            Label(saved.name, systemImage: "checkmark.shield")
                            Button(model.connecting ? "Reconnecting…" : "Reconnect") { model.resumeSavedConnection() }
                                .disabled(model.connecting)
                            Button("Forget this Mac", role: .destructive) { model.forgetMac() }
                        }
                    }
                    Section {
                        Label("Open Duo Receiver on your Mac. Keep both devices on the same local network, then enter the pairing code shown on your Mac.", systemImage: "desktopcomputer")
                            .font(.subheadline)
                    } header: { Text("Your Mac, at your fingertips") }
                    Section {
                        if model.hosts.isEmpty {
                            HStack { ProgressView(); Text("Looking for nearby Macs…").foregroundStyle(.secondary) }
                            Button("Search again", systemImage: "arrow.clockwise") { model.browse() }
                        }
                        ForEach(model.hosts) { host in
                            Button { selectedID = host.id; codeFocused = true } label: {
                                HStack {
                                    Label(host.name, systemImage: "desktopcomputer")
                                    Spacer()
                                    if selectedID == host.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
                                }
                            }.tint(.primary)
                        }
                        if let error = model.discoveryError { Text(error).font(.footnote).foregroundStyle(.red) }
                    } header: { Text("Nearby Macs") }
                    Section {
                        DisclosureGroup("Connect by IP address", isExpanded: $manual) {
                            TextField("Mac IP address or hostname", text: $manualAddress)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                    } footer: { if manual { Text("Use the address shown in Duo Receiver. Both devices must be on the same local network.") } }
                    Section {
                        TextField("8-digit pairing code", text: $code)
                            .keyboardType(.numberPad).textContentType(.oneTimeCode).focused($codeFocused)
                            .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(8)) }
                        Button {
                            if manual, !manualAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                codeFocused = false; model.connectAddress(manualAddress, code: code); return
                            }
                            guard let host = model.hosts.first(where: { $0.id == selectedID }) ?? (model.hosts.count == 1 ? model.hosts.first : nil) else { return }
                            codeFocused = false; model.connect(host, code: code)
                        } label: {
                            HStack { Text(model.connecting ? "Connecting…" : "Connect securely"); Spacer(); Image(systemName: "arrow.up.right") }
                        }
                        .disabled(code.count != 8 || model.connecting || (manual ? manualAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : selectedID == nil && model.hosts.count != 1))
                        if model.connecting { Button("Cancel", role: .cancel) { model.disconnect() } }
                        if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
                    } footer: { Text("Enter the code once. Pairing is saved securely in Keychain and reconnects automatically when you return.") }
                }
                Section("Feel") {
                    VStack(alignment: .leading) {
                        Text("Pointer speed")
                        Slider(value: $model.sensitivity, in: 0.5...3) { Text("Pointer speed") } minimumValueLabel: { Image(systemName: "tortoise") } maximumValueLabel: { Image(systemName: "hare") }
                    }
                    Toggle("Natural scrolling", isOn: $model.naturalScroll)
                    Toggle("Pointer acceleration", isOn: $model.pointerAcceleration)
                    VStack(alignment: .leading) {
                        Text("Scroll speed")
                        Slider(value: $model.scrollSpeed, in: 0.25...2.5) { Text("Scroll speed") }
                    }
                    Toggle("Three-finger drag", isOn: $model.threeFingerDrag)
                    Toggle("Click haptics", isOn: $model.haptics)
                }
                Section("The whole surface") {
                    gesture("Move", symbol: "cursorarrow", detail: "Slide one finger")
                    gesture("Click", symbol: "hand.tap", detail: "Tap once")
                    gesture("Right-click", symbol: "hand.tap", detail: "Tap with two fingers")
                    gesture("Scroll", symbol: "arrow.up.arrow.down", detail: "Slide two fingers")
                    gesture("Drag", symbol: "hand.draw", detail: "Hold still, then slide")
                    gesture("Zoom", symbol: "plus.magnifyingglass", detail: "Pinch two fingers; sends app zoom shortcuts")
                    gesture("Reset zoom", symbol: "arrow.counterclockwise", detail: "Double-tap two fingers")
                    gesture("Rotate", symbol: "rotate.right", detail: "Turn two fingers; uses the app's Rotate menu")
                    gesture("Look up", symbol: "character.book.closed", detail: "Tap three fingers")
                    gesture("Mission Control", symbol: "rectangle.3.group", detail: "Swipe up with three or four fingers")
                    gesture("App Exposé", symbol: "rectangle.stack", detail: "Swipe down with three or four fingers")
                    gesture("Switch desktops", symbol: "arrow.left.arrow.right", detail: "Swipe sideways with three or four fingers")
                    gesture("Show desktop / Apps", symbol: "square.grid.3x3", detail: "Spread / pinch four fingers")
                    gesture("Notification Center", symbol: "bell", detail: "Swipe left from the right edge with two fingers")
                    gesture("Controls", symbol: "slider.horizontal.3", detail: "Tap with four fingers")
                    Text("Mac controls use keyboard shortcuts or app menu commands. Customized shortcuts affect results. Pinch and rotation are app-command equivalents; hardware Force Click and native Smart Zoom are unavailable. Three-finger drag replaces three-finger swipes when enabled.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if model.connected {
                    Section("Mac controls") {
                        ForEach(MacAction.allCases) { action in
                            Button(action.title, systemImage: action.symbol) { model.send(action.input) }
                        }
                    }
                }
            }
            .navigationTitle("Duo Trackpad")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", systemImage: "checkmark") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
    }
    private func gesture(_ title: String, symbol: String, detail: String) -> some View {
        LabeledContent { Text(detail).foregroundStyle(.secondary) } label: { Label(title, systemImage: symbol) }
    }
}
