import Foundation
import Combine

public struct DailyInsightPoint: Identifiable, Equatable, Sendable {
    public let id: String
    public let date: Date
    public let weekdayLabel: String
    public let dayNumberLabel: String
    public let completedTasks: Int
    public let plannedTasks: Int
    public let focusMinutes: Int

    public init(
        id: String,
        date: Date,
        weekdayLabel: String,
        dayNumberLabel: String,
        completedTasks: Int,
        plannedTasks: Int,
        focusMinutes: Int
    ) {
        self.id = id
        self.date = date
        self.weekdayLabel = weekdayLabel
        self.dayNumberLabel = dayNumberLabel
        self.completedTasks = completedTasks
        self.plannedTasks = plannedTasks
        self.focusMinutes = focusMinutes
    }
}

public struct WeeklyMomentumSummary: Equatable, Sendable {
    public let completedLast7Days: Int
    public let completedPrevious7Days: Int
    public let plannedLast7Days: Int
    public let focusMinutesLast7Days: Int
    public let activeDaysLast7Days: Int
    public let dailyPoints: [DailyInsightPoint]

    public var formattedFocusTime: String {
        let hours = focusMinutesLast7Days / 60
        let mins = focusMinutesLast7Days % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

@MainActor
public final class ProductivityInsightsStore: ObservableObject {
    public static let shared = ProductivityInsightsStore()

    @Published public private(set) var sessions: [FocusSessionRecord] = []

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
            self.storageURL = dir.appendingPathComponent("focus_sessions.json")
        }
        load()
    }

    public func recordSession(_ session: FocusSessionRecord) {
        sessions.append(session)
        save()
    }

    public func replaceAllSessions(_ newSessions: [FocusSessionRecord]) {
        sessions = newSessions
        save()
    }

    public func totalFocusMinutes(since date: Date) -> Int {
        let totalSeconds = sessions
            .filter { $0.startedAt >= date }
            .reduce(0.0) { $0 + $1.durationSeconds }
        return Int(totalSeconds / 60)
    }

    public func todayFocusMinutes(referenceDate: Date = Date()) -> Int {
        let start = calendar.startOfDay(for: referenceDate)
        return totalFocusMinutes(since: start)
    }

    public func completedTasksCount(in store: PlannerStore, since date: Date? = nil) -> Int {
        store.tasks.filter { task in
            guard task.isCompleted else { return false }
            if let date, let completedAt = task.completedAt {
                return completedAt >= date
            }
            return true
        }.count
    }

    /// Consecutive days (ending today or yesterday) with at least one completed task or focus session.
    public func currentStreak(tasks: [NotchTask], referenceDate: Date = Date()) -> Int {
        var activeDays = Set<String>()
        for task in tasks where task.isCompleted {
            let d = task.completedAt ?? task.createdAt
            activeDays.insert(DailyNote.dayKey(for: d, calendar: calendar))
        }
        for session in sessions where session.durationSeconds >= 60 {
            activeDays.insert(DailyNote.dayKey(for: session.startedAt, calendar: calendar))
        }

        var streak = 0
        var cursor = calendar.startOfDay(for: referenceDate)
        if !activeDays.contains(DailyNote.dayKey(for: cursor, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        while activeDays.contains(DailyNote.dayKey(for: cursor, calendar: calendar)) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Returns hours (0...23) sorted by total focus minutes descending.
    public func bestFocusHours() -> [(hour: Int, minutes: Int)] {
        var buckets = [Int: TimeInterval]()
        for session in sessions {
            let hour = calendar.component(.hour, from: session.startedAt)
            buckets[hour, default: 0] += session.durationSeconds
        }
        return buckets
            .map { (hour: $0.key, minutes: Int($0.value / 60)) }
            .filter { $0.minutes > 0 }
            .sorted { $0.minutes > $1.minutes }
    }

    /// Computes the 7-day momentum card and daily bar-chart breakdown.
    public func weeklySummary(tasks: [NotchTask], referenceDate: Date = Date()) -> WeeklyMomentumSummary {
        let todayStart = calendar.startOfDay(for: referenceDate)
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.dateFormat = "EEE"

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.dateFormat = "d"

        var points: [DailyInsightPoint] = []
        var completedLast7 = 0
        var plannedLast7 = 0
        var focusMinutesLast7 = 0
        var activeDays = 0

        for offset in (-6...0) {
            let day = calendar.date(byAdding: .day, value: offset, to: todayStart) ?? todayStart
            let key = DailyNote.dayKey(for: day, calendar: calendar)

            let completedOnDay = tasks.filter { task in
                guard task.isCompleted else { return false }
                let d = task.completedAt ?? task.scheduledDay ?? task.createdAt
                return DailyNote.dayKey(for: d, calendar: calendar) == key
            }.count

            let scheduledOrCompletedOnDay = tasks.filter { task in
                if let sched = task.scheduledDay, DailyNote.dayKey(for: sched, calendar: calendar) == key {
                    return true
                }
                if task.isCompleted, let comp = task.completedAt, DailyNote.dayKey(for: comp, calendar: calendar) == key {
                    return true
                }
                return false
            }.count

            let planned = max(completedOnDay, scheduledOrCompletedOnDay)
            let focusSecs = sessions
                .filter { DailyNote.dayKey(for: $0.startedAt, calendar: calendar) == key }
                .reduce(0.0) { $0 + $1.durationSeconds }
            let focusMins = Int(focusSecs / 60)

            if completedOnDay > 0 || focusMins > 0 {
                activeDays += 1
            }
            completedLast7 += completedOnDay
            plannedLast7 += planned
            focusMinutesLast7 += focusMins

            points.append(
                DailyInsightPoint(
                    id: key,
                    date: day,
                    weekdayLabel: weekdayFormatter.string(from: day),
                    dayNumberLabel: dayFormatter.string(from: day),
                    completedTasks: completedOnDay,
                    plannedTasks: planned,
                    focusMinutes: focusMins
                )
            )
        }

        // Previous 7 days (-13...-7) for week-over-week comparison
        let prevStart = calendar.date(byAdding: .day, value: -13, to: todayStart) ?? todayStart
        let prevEnd = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let completedPrev7 = tasks.filter { task in
            guard task.isCompleted else { return false }
            let d = task.completedAt ?? task.createdAt
            return d >= prevStart && d < prevEnd
        }.count

        return WeeklyMomentumSummary(
            completedLast7Days: completedLast7,
            completedPrevious7Days: completedPrev7,
            plannedLast7Days: max(completedLast7, plannedLast7),
            focusMinutesLast7Days: focusMinutesLast7,
            activeDaysLast7Days: activeDays,
            dailyPoints: points
        )
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        if let decoded = try? JSONDecoder().decode([FocusSessionRecord].self, from: data) {
            self.sessions = decoded
        }
    }

    private func save() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
