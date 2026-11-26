import Foundation
import EventKit

@MainActor
public final class RemindersSyncService: ObservableObject {
    public static let shared = RemindersSyncService()

    @Published public private(set) var authorizationStatus: EKAuthorizationStatus
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncedAt: Date?
    @Published public var listName: String = "NotchFree"
    /// When true, tasks without an explicit reminder time are synced to Reminders without a due date
    /// so they don't appear as "Due Today" every morning on iPhone.
    @Published public var dueDatesOnlyWithTime: Bool = true

    private let eventStore = EKEventStore()

    public init() {
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    public func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            return granted
        } catch {
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            return false
        }
    }

    public func sync(with store: PlannerStore) async {
        guard authorizationStatus == .fullAccess else { return }
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncedAt = Date()
        }

        guard let calendar = findOrCreateRemindersList(named: listName) else { return }
        let predicate = eventStore.predicateForReminders(in: [calendar])
        let existingReminders = await fetchReminders(matching: predicate)
        let remindersByID = Dictionary(uniqueKeysWithValues: existingReminders.map { ($0.calendarItemIdentifier, $0) })

        // 1. Push NotchFree tasks -> Apple Reminders
        for task in store.tasks {
            if let extID = task.externalReminderID, let reminder = remindersByID[extID] {
                if reminder.isCompleted != task.isCompleted {
                    // Two-way: if completed in Reminders, reflect in NotchFree
                    if reminder.isCompleted && !task.isCompleted {
                        store.toggleComplete(id: task.id)
                    } else {
                        reminder.isCompleted = task.isCompleted
                        try? eventStore.save(reminder, commit: false)
                    }
                }
                if reminder.title != task.title {
                    reminder.title = task.title
                    try? eventStore.save(reminder, commit: false)
                }
            } else if !task.isCompleted {
                let reminder = EKReminder(eventStore: eventStore)
                reminder.calendar = calendar
                reminder.title = task.title
                reminder.notes = task.notes.isEmpty ? nil : task.notes
                reminder.priority = mapPriority(task.priority)
                if let reminderDate = task.reminderDate {
                    reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
                    reminder.addAlarm(EKAlarm(absoluteDate: reminderDate))
                } else if !dueDatesOnlyWithTime, let day = task.scheduledDay {
                    reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: day)
                }
                do {
                    try eventStore.save(reminder, commit: false)
                    var updated = task
                    updated.externalReminderID = reminder.calendarItemIdentifier
                    store.updateTask(updated)
                } catch {
                    // Best-effort per item
                }
            }
        }

        // 2. Pull newly created Reminders from iPhone/Watch -> NotchFree
        let knownIDs = Set(store.tasks.compactMap(\.externalReminderID))
        for reminder in existingReminders where !knownIDs.contains(reminder.calendarItemIdentifier) && !reminder.isCompleted {
            let dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            let created = store.addTask(
                title: reminder.title ?? "Reminder",
                scheduledDay: dueDate.map { Calendar.current.startOfDay(for: $0) },
                reminderDate: dueDate
            )
            var linked = created
            linked.externalReminderID = reminder.calendarItemIdentifier
            store.updateTask(linked)
        }

        try? eventStore.commit()
    }

    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { items in
                continuation.resume(returning: items ?? [])
            }
        }
    }

    private func findOrCreateRemindersList(named name: String) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .reminder)
        if let existing = calendars.first(where: { $0.title == name }) {
            return existing
        }
        let newCal = EKCalendar(for: .reminder, eventStore: eventStore)
        newCal.title = name
        newCal.source = eventStore.defaultCalendarForNewReminders()?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local })
        do {
            try eventStore.saveCalendar(newCal, commit: true)
            return newCal
        } catch {
            return eventStore.defaultCalendarForNewReminders()
        }
    }

    private func mapPriority(_ priority: TaskPriority) -> Int {
        switch priority {
        case .none: return 0
        case .low: return 9
        case .medium: return 5
        case .high: return 1
        }
    }
}
