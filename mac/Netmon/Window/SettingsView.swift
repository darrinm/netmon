import SwiftUI

struct SettingsView: View {
    @Bindable var prefs: Preferences
    @State private var loginItemError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings").font(.largeTitle.bold())

                GroupBox(label: groupLabel("Monitoring")) {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent("Ping host") {
                            TextField("", text: $prefs.pingHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 220)
                        }
                        LabeledContent("DNS host") {
                            TextField("", text: $prefs.dnsHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 220)
                        }
                        LabeledContent("Interval") {
                            HStack(spacing: 8) {
                                Text("\(prefs.intervalSeconds)s")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 40, alignment: .trailing)
                                Stepper("", value: $prefs.intervalSeconds, in: 1...600, step: stepSize)
                                    .labelsHidden()
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: groupLabel("Notifications")) {
                    Toggle("Send a notification on outage start and recovery",
                           isOn: $prefs.notificationsEnabled)
                        .toggleStyle(.switch)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox(label: groupLabel("Startup")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Launch Netmon at login", isOn: Binding(
                            get: { prefs.launchAtLogin },
                            set: { newValue in
                                do {
                                    try LoginItem.setEnabled(newValue)
                                    prefs.launchAtLogin = newValue
                                    loginItemError = nil
                                } catch {
                                    loginItemError = error.localizedDescription
                                }
                            }
                        ))
                        .toggleStyle(.switch)

                        if let err = loginItemError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Changes to monitoring take effect on the next sample.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func groupLabel(_ title: String) -> some View {
        Text(title).font(.headline)
    }

    /// Finer steps at the low end so 1–10s is easy to reach,
    /// coarser as the interval grows.
    private var stepSize: Int {
        switch prefs.intervalSeconds {
        case ..<10:  return 1
        case ..<60:  return 5
        case ..<300: return 30
        default:     return 60
        }
    }
}
