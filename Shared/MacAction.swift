import Foundation

enum MacAction: Int, CaseIterable, Identifiable {
    case missionControl = 1, appExpose, previousSpace, nextSpace, showDesktop, apps, spotlight
    case back, forward, zoomIn, zoomOut, resetZoom, lookUp, appSwitcher, notificationCenter
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .previousSpace: "Previous desktop"
        case .nextSpace: "Next desktop"
        case .showDesktop: "Show desktop"
        case .apps: "Apps"
        case .spotlight: "Spotlight"
        case .back: "Back"
        case .forward: "Forward"
        case .zoomIn: "Zoom in"
        case .zoomOut: "Zoom out"
        case .resetZoom: "Reset zoom"
        case .lookUp: "Look up"
        case .appSwitcher: "Next app"
        case .notificationCenter: "Notification Center"
        }
    }
    var symbol: String {
        switch self {
        case .missionControl, .appExpose: "rectangle.3.group"
        case .previousSpace, .back: "arrow.left"
        case .nextSpace, .forward: "arrow.right"
        case .showDesktop: "desktopcomputer"
        case .apps: "square.grid.3x3"
        case .spotlight: "magnifyingglass"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .resetZoom: "arrow.counterclockwise"
        case .lookUp: "character.book.closed"
        case .appSwitcher: "app.badge"
        case .notificationCenter: "bell"
        }
    }
    var input: Wire.Input { .init(.action, x: Double(rawValue)) }
}
