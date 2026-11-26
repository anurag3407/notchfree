import Foundation
import Combine

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

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        if let decoded = try? JSONDecoder().decode([FocusSessionRecord].self, from: data) {
            self.sessions = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
