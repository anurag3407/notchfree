import Foundation

public enum TaskPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

public enum TaskRecurrence: String, Codable, CaseIterable, Sendable {
    case daily
    case weekdays
    case weekly
    case monthly

    public var label: String {
        switch self {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    public func nextOccurrence(from date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            while calendar.isDateInWeekend(next) {
                next = calendar.date(byAdding: .day, value: 1, to: next) ?? next
            }
            return next
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }
}

public enum TaskSortOption: String, Codable, CaseIterable, Sendable {
    case manual
    case priority
    case reminderTime
    case deadline
    case project
    case name

    public var label: String {
        switch self {
        case .manual: return "Manual"
        case .priority: return "Priority"
        case .reminderTime: return "Reminder Time"
        case .deadline: return "Deadline"
        case .project: return "Project"
        case .name: return "Name"
        }
    }
}

public struct TaskAttachment: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case file
        case link
        case clip
    }

    public let id: UUID
    public var kind: Kind
    public var title: String
    public var value: String

    public init(id: UUID = UUID(), kind: Kind, title: String, value: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.value = value
    }
}

public struct NotchTask: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var notes: String
    public var isCompleted: Bool
    public var createdAt: Date
    public var completedAt: Date?
    /// `nil` means the task is in the Inbox (unscheduled).
    public var scheduledDay: Date?
    public var reminderDate: Date?
    public var deadline: Date?
    public var durationMinutes: Int
    public var priority: TaskPriority
    public var project: String?
    public var recurrence: TaskRecurrence?
    public var attachments: [TaskAttachment]
    public var orderIndex: Int
    public var externalReminderID: String?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        scheduledDay: Date? = nil,
        reminderDate: Date? = nil,
        deadline: Date? = nil,
        durationMinutes: Int = 30,
        priority: TaskPriority = .none,
        project: String? = nil,
        recurrence: TaskRecurrence? = nil,
        attachments: [TaskAttachment] = [],
        orderIndex: Int = 0,
        externalReminderID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.scheduledDay = scheduledDay
        self.reminderDate = reminderDate
        self.deadline = deadline
        self.durationMinutes = max(15, min(120, durationMinutes))
        self.priority = priority
        self.project = project
        self.recurrence = recurrence
        self.attachments = attachments
        self.orderIndex = orderIndex
        self.externalReminderID = externalReminderID
    }
}

public struct DailyNote: Codable, Hashable, Identifiable, Sendable {
    /// Day key formatted as `yyyy-MM-dd`.
    public let id: String
    public var content: String
    public var reflection: String
    public var updatedAt: Date

    public init(id: String, content: String = "", reflection: String = "", updatedAt: Date = Date()) {
        self.id = id
        self.content = content
        self.reflection = reflection
        self.updatedAt = updatedAt
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)
    }
}

public struct CalendarTimeBlock: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var conferenceURL: URL?
    public var source: String

    public init(
        id: String = UUID().uuidString,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        conferenceURL: URL? = nil,
        source: String = "Calendar"
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.conferenceURL = conferenceURL
        self.source = source
    }
}

public struct FocusSessionRecord: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var durationSeconds: TimeInterval
    public var completed: Bool
    public var linkedTaskID: UUID?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        durationSeconds: TimeInterval,
        completed: Bool,
        linkedTaskID: UUID? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.completed = completed
        self.linkedTaskID = linkedTaskID
    }
}

public enum FocusAmbientSound: String, Codable, CaseIterable, Sendable {
    case none
    case brownNoise
    case pinkNoise
    case rain
    case ocean

    public var label: String {
        switch self {
        case .none: return "Off"
        case .brownNoise: return "Brown Noise"
        case .pinkNoise: return "Pink Noise"
        case .rain: return "Rain"
        case .ocean: return "Ocean"
        }
    }
}

public struct NotchFreeBackup: Codable, Sendable {
    public var version: Int
    public var exportedAt: Date
    public var tasks: [NotchTask]
    public var dailyNotes: [DailyNote]
    public var focusSessions: [FocusSessionRecord]

    public init(
        version: Int = 1,
        exportedAt: Date = Date(),
        tasks: [NotchTask],
        dailyNotes: [DailyNote],
        focusSessions: [FocusSessionRecord]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.tasks = tasks
        self.dailyNotes = dailyNotes
        self.focusSessions = focusSessions
    }
}
