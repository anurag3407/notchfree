import Foundation

public struct ParsedTaskInput: Equatable, Sendable {
    public var title: String
    public var scheduledDay: Date?
    public var reminderDate: Date?
    public var priority: TaskPriority
    public var project: String?
    public var recurrence: TaskRecurrence?
}

public enum NaturalLanguageTaskParser {
    private static let weekdayMap: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7
    ]

    public static func parse(
        _ rawInput: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ParsedTaskInput {
        var working = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        var scheduledDay: Date?
        var reminderTime: (hour: Int, minute: Int)?
        var priority: TaskPriority = .none
        var project: String?
        var recurrence: TaskRecurrence?

        // 1. Priority tags: !high, !medium, !low, !p1, !p2, !p3
        let priorityPatterns: [(String, TaskPriority)] = [
            (#"(?i)(?:^|\s)!(high|p1)\b"#, .high),
            (#"(?i)(?:^|\s)!(medium|med|p2)\b"#, .medium),
            (#"(?i)(?:^|\s)!(low|p3)\b"#, .low)
        ]
        for (pattern, level) in priorityPatterns {
            if let range = working.range(of: pattern, options: .regularExpression) {
                priority = level
                working.removeSubrange(range)
            }
        }

        // 2. Project tag: #project
        if let range = working.range(of: #"(?:^|\s)#([A-Za-z0-9_-]+)"#, options: .regularExpression) {
            let matched = String(working[range]).trimmingCharacters(in: .whitespaces)
            project = String(matched.dropFirst())
            working.removeSubrange(range)
        }

        // 3. Recurrence: "every day", "daily", "every weekday", "weekdays", "every week", "weekly", "every month", "monthly"
        let recurrencePatterns: [(String, TaskRecurrence)] = [
            (#"(?i)\b(every\s+weekday|weekdays)\b"#, .weekdays),
            (#"(?i)\b(every\s+day|daily)\b"#, .daily),
            (#"(?i)\b(every\s+week|weekly)\b"#, .weekly),
            (#"(?i)\b(every\s+month|monthly)\b"#, .monthly)
        ]
        for (pattern, rule) in recurrencePatterns {
            if let range = working.range(of: pattern, options: .regularExpression) {
                recurrence = rule
                working.removeSubrange(range)
                break
            }
        }

        // 4. Relative duration: "in 2h" or "in 30m"
        if let range = working.range(of: #"(?i)\bin\s+(\d+)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)\b"#, options: .regularExpression) {
            let token = String(working[range]).lowercased()
            let digits = token.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let amount = Int(digits) {
                let isHours = token.contains("h")
                let offsetMinutes = isHours ? amount * 60 : amount
                if let target = calendar.date(byAdding: .minute, value: offsetMinutes, to: referenceDate) {
                    scheduledDay = calendar.startOfDay(for: target)
                    let comps = calendar.dateComponents([.hour, .minute], from: target)
                    reminderTime = (comps.hour ?? 9, comps.minute ?? 0)
                }
            }
            working.removeSubrange(range)
        }

        // 5. Day keywords: "today", "tomorrow", "tmr", or weekday names
        if let range = working.range(of: #"(?i)\b(today)\b"#, options: .regularExpression) {
            scheduledDay = calendar.startOfDay(for: referenceDate)
            working.removeSubrange(range)
        } else if let range = working.range(of: #"(?i)\b(tomorrow|tmr)\b"#, options: .regularExpression) {
            scheduledDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate))
            working.removeSubrange(range)
        } else {
            let weekdayPattern = #"(?i)\b(?:on\s+|next\s+)?(sunday|sun|monday|mon|tuesday|tue|tues|wednesday|wed|thursday|thu|thur|thurs|friday|fri|saturday|sat)\b"#
            if let range = working.range(of: weekdayPattern, options: .regularExpression) {
                let matched = String(working[range]).lowercased()
                let isNext = matched.contains("next ")
                let dayToken = matched.components(separatedBy: CharacterSet.alphanumerics.inverted).last ?? ""
                if let targetWeekday = weekdayMap[dayToken] {
                    scheduledDay = nextWeekday(targetWeekday, from: referenceDate, forceNextWeek: isNext, calendar: calendar)
                }
                working.removeSubrange(range)
            }
        }

        // 6. Explicit time: "at 5pm", "at 5:30 pm", "at 14:00", "5pm", "10:30am"
        let timePattern = #"(?i)(?:\bat\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b|\bat\s+(\d{1,2}):(\d{2})\b"#
        if let range = working.range(of: timePattern, options: .regularExpression) {
            let rawTime = String(working[range]).lowercased()
            if let parsedTime = parseTimeToken(rawTime) {
                reminderTime = parsedTime
                if scheduledDay == nil {
                    scheduledDay = calendar.startOfDay(for: referenceDate)
                }
            }
            working.removeSubrange(range)
        }

        // Assemble reminderDate if time was specified
        var reminderDate: Date?
        if let time = reminderTime {
            let base = scheduledDay ?? calendar.startOfDay(for: referenceDate)
            reminderDate = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base)
        }

        // Clean up extra whitespace / dangling prepositions
        let cleanedTitle = working
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))

        return ParsedTaskInput(
            title: cleanedTitle.isEmpty ? rawInput.trimmingCharacters(in: .whitespacesAndNewlines) : cleanedTitle,
            scheduledDay: scheduledDay,
            reminderDate: reminderDate,
            priority: priority,
            project: project,
            recurrence: recurrence
        )
    }

    private static func nextWeekday(
        _ targetWeekday: Int,
        from referenceDate: Date,
        forceNextWeek: Bool,
        calendar: Calendar
    ) -> Date {
        let start = calendar.startOfDay(for: referenceDate)
        let currentWeekday = calendar.component(.weekday, from: start)
        var delta = targetWeekday - currentWeekday
        if delta < 0 || (delta == 0 && forceNextWeek) {
            delta += 7
        } else if delta == 0 {
            delta = 7
        }
        return calendar.date(byAdding: .day, value: delta, to: start) ?? start
    }

    private static func parseTimeToken(_ raw: String) -> (hour: Int, minute: Int)? {
        let cleaned = raw.replacingOccurrences(of: "at", with: "").trimmingCharacters(in: .whitespaces)
        let isPM = cleaned.hasSuffix("pm")
        let isAM = cleaned.hasSuffix("am")
        let numeric = cleaned
            .replacingOccurrences(of: "am", with: "")
            .replacingOccurrences(of: "pm", with: "")
            .trimmingCharacters(in: .whitespaces)

        let parts = numeric.split(separator: ":")
        guard let rawHour = Int(parts[0]) else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        guard minute >= 0 && minute < 60 else { return nil }

        var hour = rawHour
        if isPM && hour < 12 {
            hour += 12
        } else if isAM && hour == 12 {
            hour = 0
        }
        guard hour >= 0 && hour < 24 else { return nil }
        return (hour, minute)
    }
}
