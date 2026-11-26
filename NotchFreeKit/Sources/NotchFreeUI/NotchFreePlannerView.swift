import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NotchFreeCore

public enum PlannerSubTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case notepad = "Notepad"
    case focus = "Focus+"
    case insights = "Insights"
    case connect = "Connect"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .today: return "checkmark.circle"
        case .week: return "calendar.day.timeline.left"
        case .notepad: return "note.text"
        case .focus: return "waveform"
        case .insights: return "flame"
        case .connect: return "link.circle"
        }
    }
}

public struct NotchFreePlannerView: View {
    @ObservedObject private var store = PlannerStore.shared
    @ObservedObject private var notepad = DailyNotepadStore.shared
    @ObservedObject private var insights = ProductivityInsightsStore.shared
    @ObservedObject private var soundEngine = AmbientSoundEngine.shared
    @ObservedObject private var nudgeMonitor = DistractionNudgeMonitor.shared
    @ObservedObject private var remindersSync = RemindersSyncService.shared
    @ObservedObject private var mcpServer = NotchFreeMCPServer.shared
    @ObservedObject private var dropServer = PhoneDropServer.shared
    @ObservedObject private var localSendReceive = LocalSendReceiveCoordinator.shared
    @ObservedObject private var ttlService = TimeToLeaveService.shared
    @StateObject private var voiceRecognizer = VoiceTaskRecognizer()

    @State private var selectedSubTab: PlannerSubTab = .today
    @State private var newTaskInput: String = ""
    @State private var editingTaskID: UUID?
    @State private var editingTaskTitle: String = ""
    @State private var showPlanDaySheet: Bool = false
    @State private var showWrapUpSheet: Bool = false
    @State private var undoSnapshot: [NotchTask]?
    @State private var planStatusMessage: String?

    @State private var plannedSlots: [PlannedTaskSlot] = []
    @State private var planOrderOnly: Bool = false
    @State private var wrapUpReflection: String = ""
    @State private var wrapUpSummary: String?

    @State private var notepadText: String = ""
    @State private var statusBanner: String?

    private let calendarEventsProvider: () -> [CalendarTimeBlock]

    public init(calendarEventsProvider: @escaping () -> [CalendarTimeBlock] = { [] }) {
        self.calendarEventsProvider = calendarEventsProvider
    }

    public var body: some View {
        VStack(spacing: 8) {
            subTabBar

            if let nudge = nudgeMonitor.activeNudgeAppName {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("You opened \(nudge) during focus.")
                        .font(.caption)
                    Spacer()
                    Button("Back to Focus") {
                        nudgeMonitor.dismissNudge()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }

            if let statusBanner {
                HStack {
                    Text(statusBanner)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") { self.statusBanner = nil }
                        .font(.caption2)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
            }

            Group {
                switch selectedSubTab {
                case .today:
                    todayView
                case .week:
                    weekAndInboxView
                case .notepad:
                    notepadView
                case .focus:
                    focusUpgradesView
                case .insights:
                    insightsView
                case .connect:
                    connectView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onAppear {
            notepadText = notepad.note().content
            wrapUpReflection = notepad.note().reflection
        }
    }

    // MARK: - Sub-Tab Bar

    private var subTabBar: some View {
        HStack(spacing: 6) {
            ForEach(PlannerSubTab.allCases) { tab in
                Button {
                    selectedSubTab = tab
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        selectedSubTab == tab
                            ? Color.white.opacity(0.18)
                            : Color.white.opacity(0.05),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedSubTab == tab ? .white : .secondary)
            }
            Spacer()
        }
    }

    // MARK: - Today

    private var todayView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("Add task (e.g. Call mom tomorrow at 5pm !high)", text: $newTaskInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit {
                        submitNewTask()
                    }

                Button {
                    Task {
                        if voiceRecognizer.isListening {
                            voiceRecognizer.stopListening()
                            if !voiceRecognizer.transcript.isEmpty {
                                newTaskInput = voiceRecognizer.transcript
                                submitNewTask()
                            }
                        } else {
                            await voiceRecognizer.startListening()
                        }
                    }
                } label: {
                    Image(systemName: voiceRecognizer.isListening ? "mic.fill" : "mic")
                        .foregroundStyle(voiceRecognizer.isListening ? .red : .white)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Dictate task")

                Menu {
                    ForEach(TaskSortOption.allCases, id: \.self) { option in
                        Button {
                            store.sortOption = option
                        } label: {
                            if store.sortOption == option {
                                Label(option.label, systemImage: "checkmark")
                            } else {
                                Text(option.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 26)

                Button("Plan") {
                    generateDayPlan()
                    showPlanDaySheet.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Wrap") {
                    showWrapUpSheet.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if showPlanDaySheet {
                planDayPanel
            } else if showWrapUpSheet {
                wrapUpPanel
            } else {
                let todayList = store.todayTasks(includeCompleted: true)
                if todayList.isEmpty {
                    VStack(spacing: 4) {
                        Spacer()
                        Text("No tasks for today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Type naturally like \"Dentist friday at 10am\"")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(todayList) { task in
                                taskRow(task, dayContext: Date())
                            }
                        }
                    }
                }
            }
        }
    }

    private func submitNewTask() {
        let trimmed = newTaskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addParsedTask(from: trimmed, defaultToToday: true)
        newTaskInput = ""
    }

    @ViewBuilder
    private func taskRow(_ task: NotchTask, dayContext: Date?) -> some View {
        HStack(spacing: 8) {
            Button {
                store.toggleComplete(id: task.id)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            if editingTaskID == task.id {
                TextField("Task title", text: $editingTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit {
                        store.renameTask(id: task.id, newTitle: editingTaskTitle)
                        editingTaskID = nil
                    }
            } else {
                Text(task.title)
                    .font(.system(size: 12))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        editingTaskID = task.id
                        editingTaskTitle = task.title
                    }
            }

            Spacer(minLength: 4)

            if let project = task.project {
                Text("#\(project)")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }

            if task.priority != .none {
                Text(task.priority.label)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(priorityColor(task.priority).opacity(0.2), in: Capsule())
                    .foregroundStyle(priorityColor(task.priority))
            }

            if let reminder = task.reminderDate {
                Text(reminder, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if task.recurrence != nil {
                Image(systemName: "repeat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Menu {
                Button("Rename") {
                    editingTaskID = task.id
                    editingTaskTitle = task.title
                }
                Button("Move to Top") { store.moveTaskOrder(id: task.id, position: .top, withinDay: dayContext) }
                Button("Move Up") { store.moveTaskOrder(id: task.id, position: .up, withinDay: dayContext) }
                Button("Move Down") { store.moveTaskOrder(id: task.id, position: .down, withinDay: dayContext) }
                Button("Move to Bottom") { store.moveTaskOrder(id: task.id, position: .bottom, withinDay: dayContext) }
                Divider()
                Button("Move to Inbox") { store.moveTask(id: task.id, toDay: nil) }
                Button("Move to Tomorrow") {
                    let tmr = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                    store.moveTask(id: task.id, toDay: tmr)
                }
                Divider()
                Button("Delete", role: .destructive) { store.deleteTask(id: task.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        case .none: return .gray
        }
    }

    // MARK: - Plan Day & Wrap Up

    private var planDayPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Plan Your Day")
                    .font(.headline)
                Spacer()
                Toggle("Order only", isOn: $planOrderOnly)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: planOrderOnly) { _, _ in generateDayPlan() }
                Button("Close") { showPlanDaySheet = false }
                    .controlSize(.mini)
            }

            if plannedSlots.isEmpty {
                Text("No untimed open tasks to schedule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(plannedSlots) { slot in
                            HStack {
                                Text(slot.task.title)
                                    .font(.caption)
                                Spacer()
                                if let start = slot.plannedStart {
                                    Text(start, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                } else {
                                    Text("Unscheduled")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(6)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            HStack {
                if let planStatusMessage {
                    Text(planStatusMessage)
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                Spacer()
                if let undoSnapshot {
                    Button("Undo") {
                        store.replaceAllTasks(undoSnapshot)
                        self.undoSnapshot = nil
                        self.planStatusMessage = "Plan reverted"
                    }
                    .controlSize(.small)
                }
                Button("Apply") {
                    undoSnapshot = DayPlannerEngine.applyPlan(plannedSlots, to: store)
                    let scheduledCount = plannedSlots.filter { $0.plannedStart != nil }.count
                    planStatusMessage = "\(scheduledCount) reminders set"
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func generateDayPlan() {
        let now = Date()
        let cal = Calendar.current
        let endOfDay = cal.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(3600 * 4)
        plannedSlots = DayPlannerEngine.generatePlan(
            tasks: store.todayTasks(includeCompleted: false),
            events: calendarEventsProvider(),
            startTime: now,
            endTime: endOfDay,
            orderOnly: planOrderOnly
        )
    }

    private var wrapUpPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Wrap Up Today")
                    .font(.headline)
                Spacer()
                Button("Close") { showWrapUpSheet = false }
                    .controlSize(.mini)
            }

            let doneCount = store.todayTasks(includeCompleted: true).filter(\.isCompleted).count
            let openCount = store.todayTasks(includeCompleted: false).count
            Text("Completed: \(doneCount) · Remaining: \(openCount)")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("One-line reflection about today...", text: $wrapUpReflection)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onChange(of: wrapUpReflection) { _, val in
                    notepad.updateReflection(val)
                }

            HStack(spacing: 8) {
                Button("Move Remaining → Tomorrow") {
                    let res = store.wrapUpDay(moveRemainingTo: .tomorrow)
                    wrapUpSummary = "Moved \(res.movedCount) task(s) to tomorrow."
                }
                .controlSize(.small)
                Button("Move Remaining → Inbox") {
                    let res = store.wrapUpDay(moveRemainingTo: .inbox)
                    wrapUpSummary = "Moved \(res.movedCount) task(s) to Inbox."
                }
                .controlSize(.small)
            }

            if let wrapUpSummary {
                Text(wrapUpSummary)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Week & Inbox

    private var weekAndInboxView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                // Inbox column
                dayColumn(title: "Inbox", day: nil, tasks: store.inboxTasks())

                // Next 7 days
                ForEach(0..<7, id: \.self) { offset in
                    let day = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
                    let label = offset == 0 ? "Today" : day.formatted(.dateTime.weekday(.abbreviated).day())
                    dayColumn(title: label, day: day, tasks: store.tasks(for: day, includeCompleted: false))
                }
            }
        }
    }

    private func dayColumn(title: String, day: Date?, tasks: [NotchTask]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.white)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tasks) { task in
                        HStack(spacing: 4) {
                            Button { store.toggleComplete(id: task.id) } label: {
                                Image(systemName: "circle")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            Text(task.title)
                                .font(.caption2)
                                .lineLimit(2)
                        }
                        .padding(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        .contextMenu {
                            Button("Move to Today") { store.moveTask(id: task.id, toDay: Date()) }
                            Button("Move to Inbox") { store.moveTask(id: task.id, toDay: nil) }
                            Button("Delete", role: .destructive) { store.deleteTask(id: task.id) }
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(width: 145)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Daily Notepad

    private var notepadView: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Daily Notepad · \(DailyNote.dayKey(for: Date()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Turn Last Line into Task (⌘↩)") {
                    let lastLine = notepadText
                        .components(separatedBy: .newlines)
                        .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
                    if let created = notepad.convertLineToTask(line: lastLine, into: store) {
                        statusBanner = "Created task: \(created.title)"
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .controlSize(.mini)
            }

            TextEditor(text: $notepadText)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: notepadText) { _, newValue in
                    notepad.updateContent(newValue)
                }
        }
    }

    // MARK: - Focus+

    private var focusUpgradesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ambient Focus Sounds")
                    .font(.caption.bold())
                HStack(spacing: 6) {
                    ForEach(FocusAmbientSound.allCases, id: \.self) { sound in
                        Button(sound.label) {
                            soundEngine.play(sound)
                        }
                        .buttonStyle(.bordered)
                        .tint(soundEngine.currentSound == sound ? .blue : .gray)
                        .controlSize(.mini)
                    }
                }
                HStack {
                    Text("Volume")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(value: $soundEngine.volume, in: 0...1)
                }

                Divider().opacity(0.2)

                Text("Distraction Nudges & Shortcuts")
                    .font(.caption.bold())
                Text("Nudges you when opening: \(nudgeMonitor.distractingAppNames.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(nudgeMonitor.isFocusActive ? "Stop Focus Monitoring" : "Start Focus Monitoring") {
                        if nudgeMonitor.isFocusActive {
                            nudgeMonitor.endFocusMonitoring()
                        } else {
                            nudgeMonitor.beginFocusMonitoring {
                                soundEngine.stop()
                            }
                        }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - Insights

    private var insightsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                insightCard(title: "Focus Today", value: "\(insights.todayFocusMinutes())m", icon: "timer")
                insightCard(title: "Streak", value: "\(insights.currentStreak(tasks: store.tasks))d", icon: "flame.fill")
                insightCard(title: "Completed", value: "\(insights.completedTasksCount(in: store))", icon: "checkmark.seal.fill")
            }

            let bestHours = insights.bestFocusHours().prefix(3)
            if !bestHours.isEmpty {
                Text("Best Focus Hours")
                    .font(.caption.bold())
                ForEach(Array(bestHours.enumerated()), id: \.offset) { _, entry in
                    Text("\(entry.hour):00 — \(entry.minutes) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Complete focus sessions to discover your best focus hours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func insightCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2).foregroundStyle(.orange)
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.bold())
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Connect (Reminders, MCP, iPhone Drop, Backup)

    private var connectView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Apple Reminders
                HStack {
                    VStack(alignment: .leading) {
                        Text("Apple Reminders Sync").font(.caption.bold())
                        Text("Two-way sync with '\(remindersSync.listName)' list").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sync Now") {
                        Task {
                            if remindersSync.authorizationStatus != .fullAccess {
                                _ = await remindersSync.requestAccess()
                            }
                            await remindersSync.sync(with: store)
                            statusBanner = "Reminders synced"
                        }
                    }
                    .controlSize(.mini)
                }

                Divider().opacity(0.2)

                // Local MCP Server
                HStack {
                    VStack(alignment: .leading) {
                        Text("Local MCP Server (AI Agents)").font(.caption.bold())
                        Text(mcpServer.isRunning ? "Running on 127.0.0.1:\(mcpServer.port)" : "Stopped")
                            .font(.caption2)
                            .foregroundStyle(mcpServer.isRunning ? .green : .secondary)
                    }
                    Spacer()
                    Button(mcpServer.isRunning ? "Stop" : "Start") {
                        mcpServer.isRunning ? mcpServer.stop() : mcpServer.start()
                    }
                    .controlSize(.mini)
                }
                HStack(spacing: 6) {
                    ForEach(NotchFreeMCPServer.AgentClient.allCases, id: \.self) { client in
                        Button("Connect \(client.rawValue)") {
                            if !mcpServer.isRunning { mcpServer.start() }
                            if let url = try? mcpServer.installClientConfig(for: client) {
                                statusBanner = "Configured \(client.rawValue) at \(url.lastPathComponent)"
                            }
                        }
                        .controlSize(.mini)
                    }
                }

                Divider().opacity(0.2)

                // Drop from Android & iPhone (QR Web Drop + LocalSend Receiver)
                HStack {
                    VStack(alignment: .leading) {
                        Text("Drop from Android & iPhone (Wi-Fi)").font(.caption.bold())
                        Text(dropServer.isRunning ? "QR paired · Files → Shelf, Text → Clipboard" : "Scan QR on Android/iPhone, or use Android Share → LocalSend")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if dropServer.isRunning {
                        Button("New Token") {
                            dropServer.regenerateToken()
                        }
                        .controlSize(.mini)
                    }
                    Button(dropServer.isRunning ? "Stop" : "Start") {
                        dropServer.isRunning ? dropServer.stop() : dropServer.start()
                    }
                    .controlSize(.mini)
                }
                if dropServer.isRunning, let qr = dropServer.qrCodeImage() {
                    HStack(alignment: .top, spacing: 10) {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 72, height: 72)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Two-way mobile page:")
                                .font(.caption2.bold())
                            Text(dropServer.dropURLString)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if let toast = dropServer.lastDropToast {
                                Text(toast)
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                if !dropServer.receivedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Phone Drops")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        ForEach(dropServer.receivedItems.prefix(4)) { item in
                            HStack(spacing: 6) {
                                Image(systemName: item.kind == .file ? "doc.fill" : "doc.on.clipboard")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                Text(item.title)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Text("· \(item.source.label)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                if item.kind == .text, let txt = item.text {
                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(txt, forType: .string)
                                        statusBanner = "Copied text to clipboard"
                                    }
                                    .controlSize(.mini)
                                } else if let url = item.fileURL {
                                    Button("Reveal") {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                    .controlSize(.mini)
                                }
                            }
                        }
                    }
                }
                if let offer = localSendReceive.pendingOffer {
                    HStack(spacing: 8) {
                        Text("Incoming from \(offer.senderAlias) (\(offer.fileCount) item(s))")
                            .font(.caption2.bold())
                        Spacer()
                        Button("Decline") { localSendReceive.respondToPendingOffer(.decline) }
                            .controlSize(.mini)
                        Button("Accept") { localSendReceive.respondToPendingOffer(.acceptOnce) }
                            .controlSize(.mini)
                        Button("Trust") { localSendReceive.respondToPendingOffer(.alwaysTrust) }
                            .controlSize(.mini)
                    }
                    .padding(6)
                    .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                }

                Divider().opacity(0.2)

                // Time to leave & Backup
                HStack {
                    Toggle("Time to leave (Apple Maps)", isOn: $ttlService.isEnabled)
                        .font(.caption)
                    Spacer()
                    Button("Export JSON Backup") {
                        exportBackupPanel()
                    }
                    .controlSize(.mini)
                }
            }
        }
    }

    private func exportBackupPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "notchfree-backup.json"
        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? PlannerBackup.exportJSON(tasks: store, notepad: notepad, sessions: insights.sessions) {
                try? data.write(to: url)
                statusBanner = "Exported backup to \(url.lastPathComponent)"
            }
        }
    }
}
