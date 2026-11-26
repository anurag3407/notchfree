import Foundation

public enum PlannerBackup {
    @MainActor
    public static func exportJSON(
        tasks: PlannerStore,
        notepad: DailyNotepadStore,
        sessions: [FocusSessionRecord]
    ) throws -> Data {
        let payload = NotchFreeBackup(
            tasks: tasks.tasks,
            dailyNotes: notepad.allNotes,
            focusSessions: sessions
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    @MainActor
    public static func importJSON(
        _ data: Data,
        into tasks: PlannerStore,
        notepad: DailyNotepadStore,
        onSessions: ([FocusSessionRecord]) -> Void
    ) throws -> NotchFreeBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(NotchFreeBackup.self, from: data)
        tasks.replaceAllTasks(backup.tasks)
        notepad.replaceAllNotes(backup.dailyNotes)
        onSessions(backup.focusSessions)
        return backup
    }
}
