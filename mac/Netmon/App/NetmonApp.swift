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
            MenuBarLabel(health: app.health, latency: app.latestMetric?.pingAvg)
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
