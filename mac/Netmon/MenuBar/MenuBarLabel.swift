import AppKit
import SwiftUI

/// Status item label, drawn into a fixed-width template image.
///
/// `MenuBarExtra` ignores `.frame` on its label, so a SwiftUI `Text` resizes
/// the status item whenever the digit count changes and every item to its left
/// moves. The image reserves room for the widest symbol and for three digits.
struct MenuBarLabel: View {
    let health: HealthState
    /// Rounded reading. Stored rounded so that a sub-millisecond change does not redraw the image.
    let milliseconds: Int?

    init(health: HealthState, latency: Double?) {
        self.health = health
        // `Int(exactly:)` returns nil for NaN, infinity and out-of-range values.
        self.milliseconds = latency.flatMap { $0 > 0 ? Int(exactly: $0.rounded()) : nil }
    }

    var body: some View {
        Image(nsImage: Self.render(health: health, text: "\(milliseconds.map(String.init) ?? "—") ms"))
    }

    private static let height: CGFloat = 18
    private static let spacing: CGFloat = 4
    private static let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.black,
    ]
    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)

    /// Width of the widest symbol any `HealthState` can show.
    private static let symbolSlotWidth: CGFloat = HealthState.allCases
        .compactMap { symbol(named: $0.systemImage)?.size.width }
        .max()
        .map { $0.rounded(.up) } ?? 18

    /// Width of a three-digit reading. Digits are monospaced, so any three digits measure the same.
    private static let textSlotWidth: CGFloat = textSize("888 ms").width.rounded(.up)

    private static func symbol(named name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
    }

    private static func textSize(_ text: String) -> NSSize {
        (text as NSString).size(withAttributes: textAttributes)
    }

    private static func render(health: HealthState, text: String) -> NSImage {
        let textSize = textSize(text)
        // A reading of 1000 ms or more is wider than the reserved slot. Grow rather than clip.
        let textSlot = max(textSlotWidth, textSize.width.rounded(.up))
        let size = NSSize(width: symbolSlotWidth + spacing + textSlot, height: height)
        let icon = symbol(named: health.systemImage)
        let iconSlot = symbolSlotWidth
        // An immutable NSAttributedString is safe to read from any thread, but is not marked Sendable.
        nonisolated(unsafe) let string = NSAttributedString(string: text, attributes: textAttributes)

        // AppKit may call the drawing handler off the main thread. `@Sendable` keeps the
        // closure nonisolated, so it captures local copies and not the MainActor statics.
        let image = NSImage(size: size, flipped: false) { @Sendable bounds in
            if let icon {
                icon.draw(in: NSRect(
                    x: ((iconSlot - icon.size.width) / 2).rounded(),
                    y: ((bounds.height - icon.size.height) / 2).rounded(),
                    width: icon.size.width,
                    height: icon.size.height
                ))
            }
            // Right-aligned, so " ms" stays in place and only the digits change.
            string.draw(at: NSPoint(x: bounds.maxX - textSize.width,
                                    y: ((bounds.height - textSize.height) / 2).rounded()))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Netmon, \(health), \(text)"
        return image
    }
}
