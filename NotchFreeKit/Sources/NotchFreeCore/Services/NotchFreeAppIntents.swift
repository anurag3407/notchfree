import Foundation
import AppIntents

@available(macOS 14.0, *)
public struct AddNotchFreeTaskIntent: AppIntent {
    public static var title: LocalizedStringResource = "Add Task to NotchFree"
    public static var description = IntentDescription("Adds a new task to NotchFree using natural language.")

    @Parameter(title: "Task")
    public var title: String

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let task = await MainActor.run {
            PlannerStore.shared.addParsedTask(from: title, defaultToToday: true)
        }
        return .result(value: "Added: \(task.title)")
    }
}

@available(macOS 14.0, *)
public struct CompleteNotchFreeTaskIntent: AppIntent {
    public static var title: LocalizedStringResource = "Complete Task in NotchFree"
    public static var description = IntentDescription("Marks the first matching open task in NotchFree as completed.")

    @Parameter(title: "Task Name")
    public var query: String

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result: String = await MainActor.run {
            let store = PlannerStore.shared
            if let match = store.openTasksForSpotlight().first(where: { $0.title.localizedCaseInsensitiveContains(query) }) {
                store.toggleComplete(id: match.id)
                return "Completed: \(match.title)"
            }
            return "No matching open task found for '\(query)'."
        }
        return .result(value: result)
    }
}

@available(macOS 14.0, *)
public struct WhatsOnTodayIntent: AppIntent {
    public static var title: LocalizedStringResource = "What's on Today in NotchFree"
    public static var description = IntentDescription("Lists today's open tasks in NotchFree.")

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let summary: String = await MainActor.run {
            let open = PlannerStore.shared.todayTasks(includeCompleted: false)
            if open.isEmpty { return "You have no open tasks for today." }
            return open.map { "• \($0.title)" }.joined(separator: "\n")
        }
        return .result(value: summary)
    }
}

@available(macOS 14.0, *)
public struct NotchFreeShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddNotchFreeTaskIntent(),
            phrases: ["Add a task in \(.applicationName)"],
            shortTitle: "Add Task",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: WhatsOnTodayIntent(),
            phrases: ["What's on today in \(.applicationName)"],
            shortTitle: "What's on Today",
            systemImageName: "calendar"
        )
    }
}
