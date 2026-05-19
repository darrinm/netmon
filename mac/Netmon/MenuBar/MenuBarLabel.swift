import SwiftUI

struct MenuBarLabel: View {
    let health: HealthState
    let latency: Double?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: health.systemImage)
            if let latency, latency.isFinite, latency > 0 {
                Text("\(Int(latency.rounded())) ms")
                    .monospacedDigit()
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .foregroundStyle(health.tint)
    }
}
