import Foundation
import Combine

@MainActor
public final class PlannerStore: ObservableObject {
    public static let shared = PlannerStore()

    @Published public private(set) var tasks: [NotchTask] = []
    @Published public var insertNewTasksAtTop: Bool = false
    @Published public var sortOption: TaskSortOption = .manual

    private let storageURL: URL
    private let calendar: Calendar

    public init(storageURL: URL? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("NotchFree", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.storageURL = dir.appendingPathComponent("tasks.json")
        }
        load()
    }

    // MARK: - Queries

    public func tasks(for day: Date, includeCompleted: Bool = true) -> [NotchTask] {
        let filtered = tasks.filter { task in
            guard let scheduled = task.scheduledDay else { return false }
            let sameDay = calendar.isDate(scheduled, inSameDayAs: day)
            return sameDay && (includeCompleted || !task.isCompleted)
        }
        return sorted(filtered)
    }

    public func todayTasks(referenceDate: Date = Date(), includeCompleted: Bool = true) -> [NotchTask] {
        tasks(for: referenceDate, includeCompleted: includeCompleted)
    }

    public func inboxTasks(includeCompleted: Bool = false) -> [NotchTask] {
        let filtered = tasks.filter { $0.scheduledDay == nil && (includeCompleted || !$0.isCompleted) }
        return sorted(filtered)
    }

    public func openTasksForSpotlight() -> [NotchTask] {
        tasks.filter { !$0.isCompleted }
    }

    // MARK: - Mutations

    @discardableResult
    public func addTask(
        title: String,
        scheduledDay: Date? = nil,
        reminderDate: Date? = nil,
        deadline: Date? = nil,
        durationMinutes: Int = 30,
        priority: TaskPriority = .none,
        project: String? = nil,
        recurrence: TaskRecurrence? = nil,
        attachments: [TaskAttachment] = []
    ) -> NotchTask {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDay = scheduledDay.map { calendar.startOfDay(for: $0) }
        let newOrder: Int
        if insertNewTasksAtTop {
            for idx in tasks.indices {
                tasks[idx].orderIndex += 1
            }
            newOrder = 0
        } else {
            newOrder = (tasks.map(\.orderIndex).max() ?? -1) + 1
        }

        let task = NotchTask(
            title: trimmed.isEmpty ? "Untitled Task" : trimmed,
            scheduledDay: normalizedDay,
            reminderDate: reminderDate,
            deadline: deadline,
            durationMinutes: durationMinutes,
            priority: priority,
            project: project,
            recurrence: recurrence,
            attachments: attachments,
            orderIndex: newOrder
        )
        tasks.append(task)
        save()
        return task
    }

    @discardableResult
    public func addParsedTask(from input: String, referenceDate: Date = Date(), defaultToToday: Bool = true) -> NotchTask {
        let parsed = NaturalLanguageTaskParser.parse(input, referenceDate: referenceDate, calendar: calendar)
        let day = parsed.scheduledDay ?? (defaultToToday ? calendar.startOfDay(for: referenceDate) : nil)
        return addTask(
            title: parsed.title,
            scheduledDay: day,
            reminderDate: parsed.reminderDate,
            priority: parsed.priority,
            project: parsed.project,
            recurrence: parsed.recurrence
        )
    }

    public func updateTask(_ updated: NotchTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == updated.id }) else { return }
        tasks[idx] = updated
        save()
    }

    public func renameTask(id: UUID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].title = trimmed
        save()
    }

    public func deleteTask(id: UUID) {
        tasks.removeAll { $0.id == id }
        save()
    }

    public func toggleComplete(id: UUID, now: Date = Date()) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let wasCompleted = tasks[idx].isCompleted
        tasks[idx].isCompleted = !wasCompleted
        tasks[idx].completedAt = wasCompleted ? nil : now

        // Spawn next occurrence for repeating tasks (Todoist-style on completion)
        if !wasCompleted, let recurrence = tasks[idx].recurrence {
            let baseDay = tasks[idx].scheduledDay ?? calendar.startOfDay(for: now)
            let nextDay = calendar.startOfDay(for: recurrence.nextOccurrence(from: baseDay, calendar: calendar))
            let nextReminder: Date? = tasks[idx].reminderDate.map { oldReminder in
                let timeComps = calendar.dateComponents([.hour, .minute, .second], from: oldReminder)
                return calendar.date(bySettingHour: timeComps.hour ?? 9, minute: timeComps.minute ?? 0, second: timeComps.second ?? 0, of: nextDay) ?? nextDay
            }
            addTask(
                title: tasks[idx].title,
                scheduledDay: nextDay,
                reminderDate: nextReminder,
                durationMinutes: tasks[idx].durationMinutes,
                priority: tasks[idx].priority,
                project: tasks[idx].project,
                recurrence: recurrence,
                attachments: tasks[idx].attachments
            )
            return
        }
        save()
    }

    public func moveTask(id: UUID, toDay day: Date?) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].scheduledDay = day.map { calendar.startOfDay(for: $0) }
        save()
    }

    public func attach(_ attachment: TaskAttachment, toTaskID id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        if !tasks[idx].attachments.contains(attachment) {
            tasks[idx].attachments.append(attachment)
            save()
        }
    }

    public func removeAttachment(id attachmentID: UUID, fromTaskID taskID: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[idx].attachments.removeAll { $0.id == attachmentID }
        save()
    }

    // MARK: - Reordering & Sorting

    public enum MovePosition {
        case top
        case up
        case down
        case bottom
    }

    public func moveTaskOrder(id: UUID, position: MovePosition, withinDay day: Date?) {
        var subset = (day == nil ? inboxTasks(includeCompleted: true) : tasks(for: day!, includeCompleted: true))
        guard let currentIdx = subset.firstIndex(where: { $0.id == id }) else { return }
        let item = subset.remove(at: currentIdx)
        switch position {
        case .top:
            subset.insert(item, at: 0)
        case .up:
            subset.insert(item, at: max(0, currentIdx - 1))
        case .down:
            subset.insert(item, at: min(subset.count, currentIdx + 1))
        case .bottom:
            subset.append(item)
        }
        for (offset, task) in subset.enumerated() {
            if let globalIdx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[globalIdx].orderIndex = offset
            }
        }
        sortOption = .manual
        save()
    }

    // MARK: - Wrap Up

    public enum WrapUpDestination {
        case tomorrow
        case inbox
        case keep
    }

    public func wrapUpDay(from day: Date = Date(), moveRemainingTo destination: WrapUpDestination) -> (completedCount: Int, movedCount: Int) {
        let dayTasks = tasks(for: day, includeCompleted: true)
        let completedCount = dayTasks.filter(\.isCompleted).count
        let remaining = dayTasks.filter { !$0.isCompleted }
        var movedCount = 0

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))!
        for task in remaining {
            guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { continue }
            switch destination {
            case .tomorrow:
                tasks[idx].scheduledDay = tomorrow
                tasks[idx].reminderDate = nil
                movedCount += 1
            case .inbox:
                tasks[idx].scheduledDay = nil
                tasks[idx].reminderDate = nil
                movedCount += 1
            case .keep:
                break
            }
        }
        save()
        return (completedCount, movedCount)
    }

    // MARK: - Snapshot & Restore (Plan Undo / Backup)

    public func replaceAllTasks(_ newTasks: [NotchTask]) {
        self.tasks = newTasks
        save()
    }

    private func sorted(_ list: [NotchTask]) -> [NotchTask] {
        list.sorted { a, b in
            if a.isCompleted != b.isCompleted {
                return !a.isCompleted
            }
            switch sortOption {
            case .manual:
                return a.orderIndex < b.orderIndex
            case .priority:
                if a.priority != b.priority { return a.priority > b.priority }
                return a.orderIndex < b.orderIndex
            case .reminderTime:
                switch (a.reminderDate, b.reminderDate) {
                case let (la?, rb?): return la < rb
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.orderIndex < b.orderIndex
                }
            case .deadline:
                switch (a.deadline, b.deadline) {
                case let (la?, rb?): return la < rb
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.orderIndex < b.orderIndex
                }
            case .project:
                let pa = a.project ?? "zzz"
                let pb = b.project ?? "zzz"
                if pa != pb { return pa.localizedCaseInsensitiveCompare(pb) == .orderedAscending }
                return a.orderIndex < b.orderIndex
            case .name:
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        if let decoded = try? JSONDecoder().decode([NotchTask].self, from: data) {
            self.tasks = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
