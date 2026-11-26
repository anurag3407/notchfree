import Foundation
import AppKit

@MainActor
public final class DistractionNudgeMonitor: ObservableObject {
    public static let shared = DistractionNudgeMonitor()

    @Published public var distractingAppNames: [String] = ["Discord", "Slack", "Messages", "Safari", "Twitter"]
    @Published public var activeNudgeAppName: String?
    @Published public var focusStartShortcutName: String = ""
    @Published public var focusEndShortcutName: String = ""
    @Published public private(set) var isFocusActive: Bool = false

    private var appObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var onSleepPause: (() -> Void)?

    public init() {}

    public func beginFocusMonitoring(onMacSleep: @escaping () -> Void) {
        isFocusActive = true
        activeNudgeAppName = nil
        onSleepPause = onMacSleep

        runShortcutIfConfigured(focusStartShortcutName)

        if appObserver == nil {
            appObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let name = app?.localizedName ?? ""
                Task { @MainActor in
                    self.handleActivatedApp(name: name)
                }
            }
        }

        if sleepObserver == nil {
            sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.onSleepPause?()
                }
            }
        }
    }

    public func endFocusMonitoring() {
        isFocusActive = false
        activeNudgeAppName = nil
        if let appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appObserver)
            self.appObserver = nil
        }
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        runShortcutIfConfigured(focusEndShortcutName)
    }

    public func dismissNudge() {
        activeNudgeAppName = nil
    }

    private func handleActivatedApp(name: String) {
        guard isFocusActive, !name.isEmpty else { return }
        let matched = distractingAppNames.contains { candidate in
            !candidate.trimmingCharacters(in: .whitespaces).isEmpty
                && name.localizedCaseInsensitiveContains(candidate.trimmingCharacters(in: .whitespaces))
        }
        if matched {
            activeNudgeAppName = name
        }
    }

    private func runShortcutIfConfigured(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", trimmed]
            try? process.run()
        }
    }
}
