import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NotchFreeCore

public enum PlannerSubTab: String, CaseIterable, Identifiable {
    case workspace = "Workspace"
    case week = "Week"
    case clips = "Clips"
    case insights = "Insights"
    case focus = "Focus+"
    case connect = "Connect"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .workspace: return "square.grid.2x2"
        case .week: return "calendar"
        case .clips: return "paperclip"
        case .insights: return "chart.bar.fill"
        case .focus: return "waveform"
        case .connect: return "qrcode"
        }
    }
}

private enum ClipFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case text = "Text"
    case images = "Images"
    case links = "Links"
    var id: String { rawValue }
}

private enum InsightsChartMetric: String, CaseIterable, Identifiable {
    case tasks = "Tasks"
    case focus = "Focus"
    var id: String { rawValue }
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

    @State private var selectedSubTab: PlannerSubTab = .workspace
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
    @State private var clipFilter: ClipFilter = .all
    @State private var chartMetric: InsightsChartMetric = .tasks
    @State private var showQRPopover: Bool = false

    private let calendarEventsProvider: () -> [CalendarTimeBlock]

    public init(calendarEventsProvider: @escaping () -> [CalendarTimeBlock] = { [] }) {
        self.calendarEventsProvider = calendarEventsProvider
    }

    public var body: some View {
        VStack(spacing: 8) {
            topNotchBar

            if let nudge = nudgeMonitor.activeNudgeAppName {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(PaperInk.primary)
                    Text("You opened \(nudge) during focus.")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button("Back to Focus") {
                        nudgeMonitor.dismissNudge()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PaperInk.primary, in: Capsule())
                    .foregroundStyle(Color.white)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .paperCard(.cream, cornerRadius: 10, grainSeed: 42)
            }

            if let offer = localSendReceive.pendingOffer {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 11))
                    Text("\(offer.senderAlias) wants to drop \(offer.fileCount) item(s)")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button("Decline") { localSendReceive.respondToPendingOffer(.decline) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.black.opacity(0.12), in: Capsule())
                    Button("Accept") { localSendReceive.respondToPendingOffer(.acceptOnce) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(PaperInk.primary, in: Capsule())
                        .foregroundStyle(.white)
                    Button("Trust") { localSendReceive.respondToPendingOffer(.alwaysTrust) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(red: 0.14, green: 0.45, blue: 0.25), in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .paperCard(.lavender, cornerRadius: 10, grainSeed: 77)
            }

            if let statusBanner {
                HStack {
                    Text(statusBanner)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                    Spacer()
                    Button {
                        self.statusBanner = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }

            Group {
                switch selectedSubTab {
                case .workspace:
                    workspaceBentoView
                case .week:
                    weekAndInboxPaperView
                case .clips:
                    clipsAndDropStripView
                case .insights:
                    momentumInsightsView
                case .focus:
                    focusPaperView
                case .connect:
                    connectPaperView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .padding(.top, 4)
        .onAppear {
            notepadText = notepad.note().content
            wrapUpReflection = notepad.note().reflection
        }
    }

    // MARK: - Top Notch Header Bar (matching screenshots)

    private var topNotchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Button {
                    selectedSubTab = .connect
                } label: {
                    Image(systemName: dropServer.isRunning ? "qrcode.viewfinder" : "iphone.and.arrow.forward")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(dropServer.isRunning ? PaperSurface.sage.color : Color.white.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Drop from Android & iPhone")

                Menu {
                    ForEach(FocusAmbientSound.allCases, id: \.self) { sound in
                        Button {
                            soundEngine.play(sound)
                        } label: {
                            if soundEngine.currentSound == sound {
                                Label(sound.label, systemImage: "checkmark")
                            } else {
                                Text(sound.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: soundEngine.currentSound == .none ? "moon" : "moon.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(soundEngine.currentSound == .none ? Color.white.opacity(0.75) : PaperSurface.cream.color)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22, height: 22)
                .help("Ambient Focus Sounds")
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                ForEach(PlannerSubTab.allCases) { tab in
                    let isSelected = selectedSubTab == tab
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedSubTab = tab
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10, weight: .medium))
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.58))
                        .background(
                            isSelected ? Color.white.opacity(0.14) : Color.clear,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.05), in: Capsule())
        }
    }

    // MARK: - 1. Workspace Bento (Sage Today + Cream Notepad + Lavender Focus)

    private var workspaceBentoView: some View {
        HStack(spacing: 10) {
            // Left: Sage Paper Today Card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Today")
                        .font(.system(size: 15, weight: .bold))
                    let allToday = store.todayTasks(includeCompleted: true)
                    let doneCount = allToday.filter(\.isCompleted).count
                    Text("\(doneCount)/\(allToday.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(PaperInk.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.08), in: Capsule())

                    Spacer()

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
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PaperInk.primary)
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.08), in: Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 22)

                    Button("Plan") {
                        generateDayPlan()
                        showWrapUpSheet = false
                        showPlanDaySheet.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(showPlanDaySheet ? PaperInk.primary : Color.black.opacity(0.10), in: Capsule())
                    .foregroundStyle(showPlanDaySheet ? .white : PaperInk.primary)

                    Button("Wrap") {
                        showPlanDaySheet = false
                        showWrapUpSheet.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(showWrapUpSheet ? PaperInk.primary : Color.black.opacity(0.10), in: Capsule())
                    .foregroundStyle(showWrapUpSheet ? .white : PaperInk.primary)
                }

                // Quick add input bar on Sage paper
                HStack(spacing: 6) {
                    TextField("Add task (e.g. Call mom tomorrow at 5pm)", text: $newTaskInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(PaperInk.primary)
                        .onSubmit { submitNewTask() }

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
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(voiceRecognizer.isListening ? .red : PaperInk.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                if showPlanDaySheet {
                    planDayPaperPanel
                } else if showWrapUpSheet {
                    wrapUpPaperPanel
                } else {
                    let todayList = store.todayTasks(includeCompleted: true)
                    if todayList.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Spacer()
                            Text("Clear slate for today")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Type naturally like \"Dentist friday at 10am !high\"")
                                .font(.system(size: 11))
                                .foregroundStyle(PaperInk.secondary)
                            Spacer()
                        }
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVStack(spacing: 4) {
                                ForEach(todayList) { task in
                                    paperTaskRow(task, dayContext: Date())
                                }
                            }
                        }
                    }

                    let total = max(1, todayList.count)
                    let done = todayList.filter(\.isCompleted).count
                    VStack(alignment: .leading, spacing: 4) {
                        PaperProgressBar(progress: Double(done) / Double(total))
                        Text("\(done) of \(todayList.count) completed")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(PaperInk.secondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .paperCard(.sage, cornerRadius: 14, grainSeed: 101)

            // Right Column: Cream Notepad Card + Lavender Focus Card
            VStack(spacing: 10) {
                // Warm Cream Sticky-Note Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Daily Notepad")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                        Button("⌘↩ → Task") {
                            let lastLine = notepadText
                                .components(separatedBy: .newlines)
                                .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
                            if let created = notepad.convertLineToTask(line: lastLine, into: store) {
                                statusBanner = "Added '\(created.title)' to Today"
                            }
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.09), in: Capsule())
                    }

                    TextEditor(text: $notepadText)
                        .font(.system(size: 12))
                        .foregroundStyle(PaperInk.primary)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .onChange(of: notepadText) { _, newValue in
                            notepad.updateContent(newValue)
                        }
                }
                .padding(11)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .paperCard(.cream, cornerRadius: 14, grainSeed: 202)

                // Soft Lavender Quick Focus Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Focus Sounds")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                        Text("\(insights.todayFocusMinutes())m today")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PaperInk.secondary)
                    }

                    HStack(spacing: 4) {
                        ForEach(FocusAmbientSound.allCases, id: \.self) { sound in
                            let active = soundEngine.currentSound == sound
                            Button(sound == .brownNoise ? "Brown" : (sound == .pinkNoise ? "Pink" : sound.label)) {
                                soundEngine.play(sound)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: active ? .semibold : .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(active ? PaperInk.primary : Color.black.opacity(0.09), in: Capsule())
                            .foregroundStyle(active ? .white : PaperInk.primary)
                        }
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity)
                .paperCard(.lavender, cornerRadius: 14, grainSeed: 303)
            }
            .frame(width: 265)
        }
    }

    private func submitNewTask() {
        let trimmed = newTaskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addParsedTask(from: trimmed, defaultToToday: true)
        newTaskInput = ""
    }

    @ViewBuilder
    private func paperTaskRow(_ task: NotchTask, dayContext: Date?) -> some View {
        HStack(spacing: 7) {
            Button {
                store.toggleComplete(id: task.id)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(task.isCompleted ? PaperInk.primary : PaperInk.secondary)
            }
            .buttonStyle(.plain)

            if editingTaskID == task.id {
                TextField("Task title", text: $editingTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .onSubmit {
                        store.renameTask(id: task.id, newTitle: editingTaskTitle)
                        editingTaskID = nil
                    }
            } else {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? PaperInk.muted : PaperInk.primary)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        editingTaskID = task.id
                        editingTaskTitle = task.title
                    }
            }

            Spacer(minLength: 4)

            if let project = task.project {
                Text("#\(project)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PaperInk.secondary)
            }

            if task.priority != .none {
                Text(task.priority.label)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.11), in: Capsule())
            }

            if let reminder = task.reminderDate {
                Text(reminder, style: .time)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(PaperInk.secondary)
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
                    .font(.system(size: 10))
                    .foregroundStyle(PaperInk.secondary)
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 18)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Plan Your Day & Wrap Up Paper Panels

    private var planDayPaperPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Plan Your Day")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Toggle("Order only", isOn: $planOrderOnly)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: planOrderOnly) { _, _ in generateDayPlan() }
                Button("Done") { showPlanDaySheet = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.black.opacity(0.10), in: Capsule())
            }

            if plannedSlots.isEmpty {
                Text("No untimed open tasks to schedule.")
                    .font(.system(size: 11))
                    .foregroundStyle(PaperInk.secondary)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(plannedSlots) { slot in
                            HStack {
                                Text(slot.task.title)
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                if let start = slot.plannedStart {
                                    Text(start, style: .time)
                                        .font(.system(size: 10, weight: .bold))
                                } else {
                                    Text("Unscheduled")
                                        .font(.system(size: 10))
                                        .foregroundStyle(PaperInk.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            HStack {
                if let planStatusMessage {
                    Text(planStatusMessage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Spacer()
                if let undoSnapshot {
                    Button("Undo") {
                        store.replaceAllTasks(undoSnapshot)
                        self.undoSnapshot = nil
                        self.planStatusMessage = "Plan reverted"
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.12), in: Capsule())
                }
                Button("Apply") {
                    undoSnapshot = DayPlannerEngine.applyPlan(plannedSlots, to: store)
                    let scheduledCount = plannedSlots.filter { $0.plannedStart != nil }.count
                    planStatusMessage = "\(scheduledCount) reminders set"
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(PaperInk.primary, in: Capsule())
                .foregroundStyle(.white)
            }
        }
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

    private var wrapUpPaperPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Wrap Up Today")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("Done") { showWrapUpSheet = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.black.opacity(0.10), in: Capsule())
            }

            let doneCount = store.todayTasks(includeCompleted: true).filter(\.isCompleted).count
            let openCount = store.todayTasks(includeCompleted: false).count
            Text("Completed: \(doneCount) · Remaining: \(openCount)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PaperInk.secondary)

            TextField("One-line reflection about today...", text: $wrapUpReflection)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(7)
                .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                .onChange(of: wrapUpReflection) { _, val in
                    notepad.updateReflection(val)
                }

            HStack(spacing: 6) {
                Button("Move Remaining → Tomorrow") {
                    let res = store.wrapUpDay(moveRemainingTo: .tomorrow)
                    wrapUpSummary = "Moved \(res.movedCount) task(s) to tomorrow."
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(PaperInk.primary, in: Capsule())
                .foregroundStyle(.white)

                Button("Move → Inbox") {
                    let res = store.wrapUpDay(moveRemainingTo: .inbox)
                    wrapUpSummary = "Moved \(res.movedCount) task(s) to Inbox."
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Color.black.opacity(0.12), in: Capsule())
            }

            if let wrapUpSummary {
                Text(wrapUpSummary)
                    .font(.system(size: 10, weight: .semibold))
            }
            Spacer()
        }
    }

    // MARK: - 2. Week & Inbox (Paper Columns)

    private var weekAndInboxPaperView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                paperDayColumn(title: "Inbox", surface: .ivory, day: nil, tasks: store.inboxTasks(), seed: 401)

                ForEach(0..<7, id: \.self) { offset in
                    let day = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
                    let label = offset == 0 ? "Today" : day.formatted(.dateTime.weekday(.abbreviated).day())
                    let surface: PaperSurface = offset == 0 ? .sage : (offset % 2 == 1 ? .cream : .lavender)
                    paperDayColumn(
                        title: label,
                        surface: surface,
                        day: day,
                        tasks: store.tasks(for: day, includeCompleted: false),
                        seed: UInt64(500 + offset)
                    )
                }
            }
        }
    }

    private func paperDayColumn(title: String, surface: PaperSurface, day: Date?, tasks: [NotchTask], seed: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PaperInk.secondary)
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tasks) { task in
                        HStack(spacing: 5) {
                            Button { store.toggleComplete(id: task.id) } label: {
                                Image(systemName: "circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(PaperInk.secondary)
                            }
                            .buttonStyle(.plain)
                            Text(task.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(2)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 6))
                        .contextMenu {
                            Button("Move to Today") { store.moveTask(id: task.id, toDay: Date()) }
                            Button("Move to Inbox") { store.moveTask(id: task.id, toDay: nil) }
                            Button("Delete", role: .destructive) { store.deleteTask(id: task.id) }
                        }
                    }
                }
            }
        }
        .padding(9)
        .frame(width: 146)
        .frame(maxHeight: .infinity, alignment: .top)
        .paperCard(surface, cornerRadius: 12, grainSeed: seed)
    }

    // MARK: - 3. Clips & Phone Drop Strip (Matches Screenshots 1 & 2!)

    private var filteredDropItems: [DroppedItemPayload] {
        dropServer.receivedItems.filter { item in
            switch clipFilter {
            case .all:
                return true
            case .text:
                return item.kind == .text && !(item.text?.trimmingCharacters(in: .whitespaces).hasPrefix("http") ?? false)
            case .images:
                return item.kind == .file
            case .links:
                return item.kind == .text && (item.text?.trimmingCharacters(in: .whitespaces).hasPrefix("http") ?? false)
            }
        }
    }

    private var clipsAndDropStripView: some View {
        VStack(spacing: 10) {
            if filteredDropItems.isEmpty {
                HStack(spacing: 12) {
                    // Example Warm Cream Note card + Ivory QR Drop card when empty
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Phone Drop Ready")
                            .font(.system(size: 13, weight: .bold))
                        Text("Scan QR from Android or iPhone, or share via Android LocalSend.")
                            .font(.system(size: 11))
                            .foregroundStyle(PaperInk.secondary)
                        Spacer()
                        HStack(spacing: 6) {
                            Button(dropServer.isRunning ? "Stop QR Drop" : "Start QR Drop") {
                                dropServer.isRunning ? dropServer.stop() : dropServer.start()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(PaperInk.primary, in: Capsule())
                            .foregroundStyle(.white)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .paperCard(.cream, cornerRadius: 14, grainSeed: 601)

                    if dropServer.isRunning, let qr = dropServer.qrCodeImage() {
                        VStack(spacing: 6) {
                            Image(nsImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 96, height: 96)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("Scan on Android / iPhone")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(PaperInk.secondary)
                        }
                        .padding(12)
                        .frame(width: 170)
                        .frame(maxHeight: .infinity)
                        .paperCard(.ivory, cornerRadius: 14, grainSeed: 602)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(filteredDropItems) { item in
                            clipPaperCard(for: item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Bottom filter pills + hint bar (exact Screenshot 1 & 2 layout)
            HStack(spacing: 6) {
                ForEach(ClipFilter.allCases) { filter in
                    let active = clipFilter == filter
                    Button(filter.rawValue) {
                        clipFilter = filter
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: active ? .semibold : .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(active ? PaperSurface.ivory.color : Color.white.opacity(0.08), in: Capsule())
                    .foregroundStyle(active ? PaperInk.primary : Color.white.opacity(0.72))
                }

                Spacer()

                Text("Click to copy · Double-click to open · ⌥V to paste")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.5))

                Button(dropServer.isRunning ? "QR Active" : "Show QR") {
                    if !dropServer.isRunning { dropServer.start() }
                    showQRPopover.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12), in: Capsule())
                .foregroundStyle(.white)
                .popover(isPresented: $showQRPopover) {
                    qrPopoverContent
                }
            }
        }
    }

    @ViewBuilder
    private func clipPaperCard(for item: DroppedItemPayload) -> some View {
        let isLink = item.kind == .text && (item.text?.trimmingCharacters(in: .whitespaces).hasPrefix("http") ?? false)

        VStack(spacing: 6) {
            Group {
                if item.kind == .file, let url = item.fileURL, let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 150, height: 106)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        )
                } else if isLink {
                    VStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(PaperInk.muted)
                        Text(URL(string: item.text ?? "")?.host ?? item.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(width: 150, height: 106)
                    .paperCard(.ivory, cornerRadius: 10, grainSeed: 701)
                } else if item.kind == .text {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text ?? item.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(5)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(width: 150, height: 106, alignment: .topLeading)
                    .paperCard(.cream, cornerRadius: 10, grainSeed: 702)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(PaperInk.secondary)
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                    }
                    .padding(8)
                    .frame(width: 150, height: 106)
                    .paperCard(.ivory, cornerRadius: 10, grainSeed: 703)
                }
            }
            .onTapGesture(count: 2) {
                if let url = item.fileURL {
                    NSWorkspace.shared.open(url)
                } else if isLink, let txt = item.text, let url = URL(string: txt.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    NSWorkspace.shared.open(url)
                }
            }
            .onTapGesture(count: 1) {
                if let txt = item.text {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(txt, forType: .string)
                    statusBanner = "Copied '\(item.title)'"
                } else if let url = item.fileURL {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([url as NSURL])
                    statusBanner = "Copied file '\(item.title)'"
                }
            }

            Text(item.kind == .text ? (isLink ? "Link" : "Note") : item.title)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(1)
                .frame(width: 145)
        }
    }

    private var qrPopoverContent: some View {
        VStack(spacing: 8) {
            Text("Scan with Android or iPhone")
                .font(.headline)
            if let qr = dropServer.qrCodeImage() {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 140, height: 140)
            }
            Text(dropServer.dropURLString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 220)
                .multilineTextAlignment(.center)
        }
        .padding(14)
    }

    // MARK: - 4. Insights ("Momentum is building" — Matches Screenshot 3!)

    private var momentumInsightsView: some View {
        let summary = insights.weeklySummary(tasks: store.tasks)

        return HStack(spacing: 10) {
            // Left Sage Paper Card: Momentum is building
            VStack(alignment: .leading, spacing: 6) {
                Text("Momentum is building")
                    .font(.system(size: 14, weight: .bold))

                Text("\(summary.completedLast7Days) tasks done, vs \(summary.completedPrevious7Days) the week before, with \(summary.formattedFocusTime) focused.")
                    .font(.system(size: 11))
                    .foregroundStyle(PaperInk.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 2)

                Text("Last 7 days")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PaperInk.secondary)

                Text("\(summary.completedLast7Days)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text("Tasks completed")
                    .font(.system(size: 12, weight: .semibold))

                PaperProgressBar(
                    progress: summary.plannedLast7Days > 0
                        ? Double(summary.completedLast7Days) / Double(summary.plannedLast7Days)
                        : 0,
                    height: 5
                )

                Text("of \(summary.plannedLast7Days) planned")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(PaperInk.secondary)

                Spacer(minLength: 2)

                HStack {
                    Label("Focus time", systemImage: "clock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PaperInk.secondary)
                    Spacer()
                    Text(summary.formattedFocusTime)
                        .font(.system(size: 11, weight: .bold))
                }
                HStack {
                    Label("Active days", systemImage: "calendar")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PaperInk.secondary)
                    Spacer()
                    Text("\(summary.activeDaysLast7Days) of 7")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .padding(14)
            .frame(width: 245)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .paperCard(.sage, cornerRadius: 14, grainSeed: 801)

            // Right Lavender Paper Card: Tasks / Focus 7-Day Bar Chart
            VStack(alignment: .leading, spacing: 10) {
                PaperSegmentedControl(
                    options: InsightsChartMetric.allCases,
                    selection: $chartMetric,
                    label: { $0.rawValue }
                )

                Spacer(minLength: 4)

                insightsBarChart(points: summary.dailyPoints)

                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(PaperInk.primary)
                            .frame(width: 10, height: 10)
                        Text(chartMetric == .tasks ? "Completed" : "Focus mins")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(PaperInk.secondary)
                    }
                    if chartMetric == .tasks {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(PaperInk.plannedBar)
                                .frame(width: 10, height: 10)
                            Text("Planned")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(PaperInk.secondary)
                        }
                    }
                    Spacer()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .paperCard(.lavender, cornerRadius: 14, grainSeed: 802)
        }
    }

    private func insightsBarChart(points: [DailyInsightPoint]) -> some View {
        let maxTaskVal = max(1, points.map { max($0.plannedTasks, $0.completedTasks) }.max() ?? 1)
        let maxFocusVal = max(15, points.map(\.focusMinutes).max() ?? 15)
        let chartHeight: CGFloat = 115

        return HStack(alignment: .bottom, spacing: 14) {
            ForEach(points) { point in
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        if chartMetric == .tasks {
                            let plannedRatio = CGFloat(point.plannedTasks) / CGFloat(maxTaskVal)
                            let completedRatio = CGFloat(point.completedTasks) / CGFloat(maxTaskVal)

                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(PaperInk.plannedBar)
                                .frame(width: 24, height: max(6, chartHeight * plannedRatio))

                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(PaperInk.primary)
                                .frame(width: 24, height: point.completedTasks > 0 ? max(8, chartHeight * completedRatio) : 0)
                        } else {
                            let focusRatio = CGFloat(point.focusMinutes) / CGFloat(maxFocusVal)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(PaperInk.plannedBar)
                                .frame(width: 24, height: chartHeight)
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(PaperInk.primary)
                                .frame(width: 24, height: point.focusMinutes > 0 ? max(8, chartHeight * focusRatio) : 0)
                        }
                    }
                    .frame(height: chartHeight, alignment: .bottom)

                    VStack(spacing: 1) {
                        Text(point.weekdayLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PaperInk.secondary)
                        Text(point.dayNumberLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(PaperInk.muted)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 5. Focus+ Paper View

    private var focusPaperView: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ambient Focus Sounds")
                    .font(.system(size: 14, weight: .bold))
                HStack(spacing: 6) {
                    ForEach(FocusAmbientSound.allCases, id: \.self) { sound in
                        let active = soundEngine.currentSound == sound
                        Button(sound.label) {
                            soundEngine.play(sound)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: active ? .semibold : .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(active ? PaperInk.primary : Color.black.opacity(0.10), in: Capsule())
                        .foregroundStyle(active ? .white : PaperInk.primary)
                    }
                }
                HStack {
                    Text("Volume")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PaperInk.secondary)
                    Slider(value: $soundEngine.volume, in: 0...1)
                        .tint(PaperInk.primary)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .paperCard(.lavender, cornerRadius: 14, grainSeed: 901)

            VStack(alignment: .leading, spacing: 10) {
                Text("Distraction Nudges & Shortcuts")
                    .font(.system(size: 14, weight: .bold))
                Text("Watching: \(nudgeMonitor.distractingAppNames.joined(separator: ", "))")
                    .font(.system(size: 11))
                    .foregroundStyle(PaperInk.secondary)
                Spacer()
                Button(nudgeMonitor.isFocusActive ? "Stop Focus Monitoring" : "Start Focus Monitoring") {
                    if nudgeMonitor.isFocusActive {
                        nudgeMonitor.endFocusMonitoring()
                    } else {
                        nudgeMonitor.beginFocusMonitoring { soundEngine.stop() }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(PaperInk.primary, in: Capsule())
                .foregroundStyle(.white)
            }
            .padding(14)
            .frame(width: 245)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .paperCard(.cream, cornerRadius: 14, grainSeed: 902)
        }
    }

    // MARK: - 6. Connect Paper View (Android/iPhone Drop, MCP, Reminders, Backup)

    private var connectPaperView: some View {
        HStack(spacing: 10) {
            // Left Ivory Card: Drop from Android & iPhone
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Drop from Android & iPhone")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Button(dropServer.isRunning ? "Stop" : "Start") {
                        dropServer.isRunning ? dropServer.stop() : dropServer.start()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(PaperInk.primary, in: Capsule())
                    .foregroundStyle(.white)
                }

                Text("Two-way QR web drop (no app) + Android Share Sheet via LocalSend.")
                    .font(.system(size: 11))
                    .foregroundStyle(PaperInk.secondary)

                if dropServer.isRunning, let qr = dropServer.qrCodeImage() {
                    HStack(spacing: 10) {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 78, height: 78)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dropServer.dropURLString)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(PaperInk.secondary)
                                .lineLimit(2)
                            Button("Regenerate QR Token") {
                                dropServer.regenerateToken()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.black.opacity(0.10), in: Capsule())
                        }
                    }
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .paperCard(.ivory, cornerRadius: 14, grainSeed: 1001)

            // Right Sand/Sage Card: Local MCP, Reminders, Backup
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("AI Agents (MCP)")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Button(mcpServer.isRunning ? "Stop" : "Start") {
                        mcpServer.isRunning ? mcpServer.stop() : mcpServer.start()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(mcpServer.isRunning ? Color(red: 0.14, green: 0.45, blue: 0.25) : PaperInk.primary, in: Capsule())
                    .foregroundStyle(.white)
                }

                HStack(spacing: 4) {
                    ForEach(NotchFreeMCPServer.AgentClient.allCases, id: \.self) { client in
                        Button(client.rawValue) {
                            if !mcpServer.isRunning { mcpServer.start() }
                            if let url = try? mcpServer.installClientConfig(for: client) {
                                statusBanner = "Configured \(client.rawValue) (\(url.lastPathComponent))"
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Color.black.opacity(0.09), in: Capsule())
                    }
                }

                Divider().overlay(PaperInk.hairline)

                HStack {
                    Text("Apple Reminders")
                        .font(.system(size: 12, weight: .bold))
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
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.10), in: Capsule())
                }

                HStack {
                    Toggle("Time to leave", isOn: $ttlService.isEnabled)
                        .font(.system(size: 11, weight: .medium))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    Spacer()
                    Button("JSON Backup") { exportBackupPanel() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(0.10), in: Capsule())
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .paperCard(.sand, cornerRadius: 14, grainSeed: 1002)
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
