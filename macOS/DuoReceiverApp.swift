import SwiftUI

@main
struct DuoReceiverApp: App {
    @StateObject private var model = ReceiverModel()
    var body: some Scene {
        Window("Duo Receiver", id: "receiver") {
            ReceiverView(model: model).frame(minWidth: 430, idealWidth: 480, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 560)
        MenuBarExtra("Duo Receiver", systemImage: "rectangle.and.hand.point.up.left") {
            ReceiverMenu(model: model)
        }
    }
}

struct ReceiverMenu: View {
    @ObservedObject var model: ReceiverModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.connectedName.map { "Connected to \($0)" } ?? "Duo Trackpad")
        Button("Open Duo Receiver") { openWindow(id: "receiver"); NSApp.activate(ignoringOtherApps: true) }
        if model.connectedName != nil { Button("Disconnect") { model.disconnect() } }
        Button(model.paused ? "Resume receiving" : "Pause receiving") { model.togglePause() }
        if model.pairedCount > 0 {
            Button("Forget paired devices (\(model.pairedCount))", role: .destructive) { model.forgetDevices() }
        }
        Divider()
        Button("Quit Duo Receiver") { model.disconnect(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct ReceiverView: View {
    @ObservedObject var model: ReceiverModel
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "rectangle.and.hand.point.up.left")
                .font(.system(size: 42, weight: .ultraLight)).foregroundStyle(.secondary)
                .padding(.top, 12)
            VStack(spacing: 8) {
                Text("Your Mac. More within reach.").font(.system(size: 25, weight: .light))
                Text("DUO TRACKPAD RECEIVER").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
            }
            if let name = model.connectedName {
                VStack(spacing: 12) {
                    Label(name, systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                    Text("Your iPhone is now your trackpad.").foregroundStyle(.secondary)
                    if let latency = model.latency { Text("\(latency.formatted(.number.precision(.fractionLength(1)))) ms round trip").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    Button("Disconnect") { model.disconnect() }
                }.frame(maxWidth: .infinity).padding(24).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 12) {
                    Text(model.paused ? "RECEIVING PAUSED" : "PAIRING CODE").font(.caption2).tracking(2).foregroundStyle(.secondary)
                    PairingCodeLabel(value: model.paused ? "•••• ••••" : String(model.code.prefix(4)) + " " + String(model.code.suffix(4)))
                        .frame(height: 48)
                    Text(model.paused ? "Resume to connect your iPhone." : "Select this Mac in Duo Trackpad, then enter this code.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if model.paused { Button("Resume receiving") { model.togglePause() } }
                }.frame(maxWidth: .infinity).padding(24).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            }
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.trusted ? "checkmark.circle.fill" : "hand.raised.circle").foregroundStyle(model.trusted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.trusted ? "Ready to control your Mac" : "Allow mouse control").font(.callout.weight(.medium))
                        Text(model.trusted ? "Accessibility access is enabled." : "Enable Duo Receiver in System Settings → Privacy & Security → Accessibility.").font(.caption).foregroundStyle(.secondary)
                        if !model.trusted { Button("Open Accessibility Settings") { model.requestAccessibility() } }
                    }
                }
                HStack(spacing: 12) {
                    Image(systemName: "wifi").foregroundStyle(.secondary)
                    Text(model.listening ? "Discoverable on your local network" : "Starting local discovery…").font(.caption).foregroundStyle(.secondary)
                    if !model.listening { Button("Retry") { model.start() } }
                }
                Text("Direct connection: \(NetworkAddresses.localIPv4.first ?? ProcessInfo.processInfo.hostName) · port \(String(Wire.port))")
                    .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center) }
            Text("Encrypted. Direct. No account required.").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(32)
        .background(LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// Keep rotating codes out of SwiftUI's selectable-text glyph transitions.
struct PairingCodeLabel: NSViewRepresentable {
    let value: String
    func makeNSView(context: Context) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .monospacedSystemFont(ofSize: 36, weight: .light)
        label.alignment = .center
        label.isSelectable = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setAccessibilityLabel("Pairing code")
        return label
    }
    func updateNSView(_ label: NSTextField, context: Context) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0; context.allowsImplicitAnimation = false
            label.stringValue = value
            label.needsDisplay = true
        }
    }
}
