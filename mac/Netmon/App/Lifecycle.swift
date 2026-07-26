import AppKit
import Foundation

/// Ensures the `log stream` child is terminated on the way out.
///
/// Nothing used to run `AppModel.stop()` at all, so every exit — including an
/// ordinary Quit — leaked the child. It survives its parent because
/// `log stream` only notices the closed pipe when a write fails, and the link
/// event predicate matches so rarely it may never write.
///
/// Three paths, because no single one covers everything:
///  - `applicationShouldTerminate` — Quit, logout, restart.
///  - signal sources — `kill`, and terminations that bypass AppKit.
///  - `LinkEventMonitor.reapOrphans()` at startup — the only cover for SIGKILL
///    and crashes, which by definition can't run cleanup.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installSignalHandlers()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Shutting the child down is async, so defer the quit rather than
        // racing it — AppKit would otherwise tear us down mid-await.
        Task {
            await LinkEventMonitor.shared.stop()
            await MainActor.run { sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    private func installSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            // The default disposition kills the process before a dispatch
            // source ever runs, so it has to be disabled first.
            signal(signalNumber, SIG_IGN)

            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                Task {
                    await LinkEventMonitor.shared.stop()
                    exit(0)
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }
}
