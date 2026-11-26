import SwiftUI
import NotchFreeCore

public struct NotchFreeSettingsSection: View {
    @ObservedObject private var remindersSync = RemindersSyncService.shared
    @ObservedObject private var mcpServer = NotchFreeMCPServer.shared
    @ObservedObject private var nudgeMonitor = DistractionNudgeMonitor.shared
    @ObservedObject private var ttlService = TimeToLeaveService.shared
    @ObservedObject private var localSendReceive = LocalSendReceiveCoordinator.shared

    @State private var calendlyKey: String = KeychainSecretStore.load(key: BookingCalendarClient.calendlyKeyName) ?? ""
    @State private var calComKey: String = KeychainSecretStore.load(key: BookingCalendarClient.calComKeyName) ?? ""
    @State private var distractingAppsText: String = ""
    @State private var savedBanner: String?

    public init() {}

    public var body: some View {
        Form {
            Section("NotchFree Planner & Reminders") {
                TextField("Apple Reminders List Name", text: $remindersSync.listName)
                Toggle("Due dates only with a time (prevents cluttered iPhone Today)", isOn: $remindersSync.dueDatesOnlyWithTime)
            }

            Section("Focus Automation & Nudges") {
                TextField("Shortcut on Focus Start", text: $nudgeMonitor.focusStartShortcutName)
                TextField("Shortcut on Focus End", text: $nudgeMonitor.focusEndShortcutName)
                TextField("Distracting Apps (comma-separated)", text: $distractingAppsText)
                    .onAppear {
                        distractingAppsText = nudgeMonitor.distractingAppNames.joined(separator: ", ")
                    }
                    .onChange(of: distractingAppsText) { _, val in
                        nudgeMonitor.distractingAppNames = val
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    }
            }

            Section("Calendly, Cal.com & Time to Leave") {
                SecureField("Calendly Personal Access Token (Keychain)", text: $calendlyKey)
                SecureField("Cal.com API Key (Keychain)", text: $calComKey)
                Button("Save Calendar Keys to Keychain") {
                    KeychainSecretStore.save(key: BookingCalendarClient.calendlyKeyName, value: calendlyKey)
                    KeychainSecretStore.save(key: BookingCalendarClient.calComKeyName, value: calComKey)
                    savedBanner = "Saved keys to Keychain"
                }
                Toggle("Time to leave (Apple Maps ETA)", isOn: $ttlService.isEnabled)
            }

            Section("AI Agents (Local MCP Server)") {
                Toggle("Enable Local MCP Server (127.0.0.1:\(mcpServer.port))", isOn: Binding(
                    get: { mcpServer.isRunning },
                    set: { enabled in enabled ? mcpServer.start() : mcpServer.stop() }
                ))
            }

            Section("Trusted Android / LocalSend Devices") {
                if localSendReceive.trustedDevices.isEmpty {
                    Text("No trusted devices yet. Tap 'Trust' on an incoming LocalSend prompt to auto-accept future drops.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(localSendReceive.trustedDevices.sorted(by: { $0.value < $1.value })), id: \.key) { fingerprint, alias in
                        HStack {
                            Text(alias)
                            Spacer()
                            Button("Revoke", role: .destructive) {
                                localSendReceive.untrustDevice(fingerprint: fingerprint)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            if let savedBanner {
                Text(savedBanner)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .formStyle(.grouped)
    }
}
