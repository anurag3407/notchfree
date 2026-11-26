import Foundation

public struct PlannedTaskSlot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var task: NotchTask
    public var plannedStart: Date?
    public var plannedEnd: Date?

    public init(task: NotchTask, plannedStart: Date?, plannedEnd: Date?) {
        self.id = task.id
        self.task = task
        self.plannedStart = plannedStart
        self.plannedEnd = plannedEnd
    }
}

public enum DayPlannerEngine {
    /// Generates a schedule for today's untimed tasks around existing calendar events.
    /// - Parameters:
    ///   - tasks: Today's tasks (completed tasks and tasks with user-set reminders are preserved as-is).
    ///   - events: Calendar events for today.
    ///   - startTime: Earliest time to start scheduling.
    ///   - endTime: End of workday cutoff.
    ///   - orderOnly: When `true`, returns tasks ordered by priority without assigning reminder times.
    public static func generatePlan(
        tasks: [NotchTask],
        events: [CalendarTimeBlock],
        startTime: Date,
        endTime: Date,
        orderOnly: Bool = false
    ) -> [PlannedTaskSlot] {
        let untimedOpen = tasks
            .filter { !$0.isCompleted && $0.reminderDate == nil }
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.orderIndex < $1.orderIndex
            }

        if orderOnly || startTime >= endTime {
            return untimedOpen.map { PlannedTaskSlot(task: $0, plannedStart: nil, plannedEnd: nil) }
        }

        // Build busy intervals from non-all-day events
        let busyIntervals: [(start: Date, end: Date)] = events
            .filter { !$0.isAllDay && $0.end > startTime && $0.start < endTime }
            .map { (max($0.start, startTime), min($0.end, endTime)) }
            .sorted { $0.start < $1.start }

        // Merge overlapping busy intervals
        var mergedBusy: [(start: Date, end: Date)] = []
        for interval in busyIntervals {
            if let last = mergedBusy.last, interval.start <= last.end {
                mergedBusy[mergedBusy.count - 1].end = max(last.end, interval.end)
            } else {
                mergedBusy.append(interval)
            }
        }

        // Compute free windows
        var freeWindows: [(start: Date, end: Date)] = []
        var cursor = startTime
        for busy in mergedBusy {
            if busy.start > cursor {
                freeWindows.append((cursor, busy.start))
            }
            cursor = max(cursor, busy.end)
        }
        if cursor < endTime {
            freeWindows.append((cursor, endTime))
        }

        // Fit tasks sequentially into free windows
        var result: [PlannedTaskSlot] = []
        var windowIdx = 0
        var windowCursor = freeWindows.first?.start ?? startTime

        for task in untimedOpen {
            let duration = TimeInterval(task.durationMinutes * 60)
            var assigned = false

            while windowIdx < freeWindows.count {
                let window = freeWindows[windowIdx]
                let candidateStart = max(windowCursor, window.start)
                let candidateEnd = candidateStart.addingTimeInterval(duration)
                if candidateEnd <= window.end {
                    result.append(PlannedTaskSlot(task: task, plannedStart: candidateStart, plannedEnd: candidateEnd))
                    windowCursor = candidateEnd
                    assigned = true
                    break
                } else {
                    windowIdx += 1
                    if windowIdx < freeWindows.count {
                        windowCursor = freeWindows[windowIdx].start
                    }
                }
            }

            if !assigned {
                result.append(PlannedTaskSlot(task: task, plannedStart: nil, plannedEnd: nil))
            }
        }

        return result
    }

    /// Applies a generated plan to `PlannerStore` and returns a snapshot of the previous tasks for Undo.
    @MainActor
    @discardableResult
    public static func applyPlan(_ slots: [PlannedTaskSlot], to store: PlannerStore) -> [NotchTask] {
        let snapshot = store.tasks
        for (index, slot) in slots.enumerated() {
            var updated = slot.task
            updated.orderIndex = index
            if let start = slot.plannedStart {
                updated.reminderDate = start
            }
            store.updateTask(updated)
        }
        return snapshot
    }
}
