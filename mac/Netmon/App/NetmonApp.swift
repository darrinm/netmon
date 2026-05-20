import SwiftUI

@main
struct NetmonApp: App {
    @State private var app: AppModel

    init() {
        let model = AppModel()
        _app = State(initialValue: model)
        Task { @MainActor in await model.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(app)
                .frame(width: 300)
        } label: {
            // The label is always rendered (the status item is always present),
            // so it's a reliable place to listen for "open main window" signals
            // posted from the notification delegate.
            MenuBarLabel(health: app.health, latency: app.latestMetric?.pingAvg)
                .modifier(OpenMainWindowOnNotification())
        }
        .menuBarExtraStyle(.window)

        Window("Netmon", id: "main") {
            MainView()
                .environment(app)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentMinSize)
    }
}

private struct OpenMainWindowOnNotification: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .netmonOpenMainWindow)) { _ in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

enum HealthState: Sendable {
    case unknown, good, degraded, bad

    var systemImage: String {
        switch self {
        case .unknown:  return "wifi.slash"
        case .good:     return "wifi"
        case .degraded: return "wifi.exclamationmark"
        case .bad:      return "wifi.slash"
        }
    }

    var tint: Color {
        switch self {
        case .unknown:  return .secondary
        case .good:     return .green
        case .degraded: return .yellow
        case .bad:      return .red
        }
    }
}
