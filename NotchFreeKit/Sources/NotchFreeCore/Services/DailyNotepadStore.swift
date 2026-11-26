import Foundation
import Combine

@MainActor
public final class DailyNotepadStore: ObservableObject {
    public static let shared = DailyNotepadStore()

    @Published public private(set) var notesByDay: [String: DailyNote] = [:]

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
            self.storageURL = dir.appendingPathComponent("daily_notes.json")
        }
        load()
    }

    public func note(for date: Date = Date()) -> DailyNote {
        let key = DailyNote.dayKey(for: date, calendar: calendar)
        return notesByDay[key] ?? DailyNote(id: key)
    }

    public func updateContent(_ content: String, for date: Date = Date()) {
        let key = DailyNote.dayKey(for: date, calendar: calendar)
        var existing = notesByDay[key] ?? DailyNote(id: key)
        existing.content = content
        existing.updatedAt = Date()
        notesByDay[key] = existing
        save()
    }

    public func appendLine(_ line: String, for date: Date = Date()) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let current = note(for: date).content
        let updated = current.isEmpty ? trimmed : current + "\n" + trimmed
        updateContent(updated, for: date)
    }

    public func updateReflection(_ reflection: String, for date: Date = Date()) {
        let key = DailyNote.dayKey(for: date, calendar: calendar)
        var existing = notesByDay[key] ?? DailyNote(id: key)
        existing.reflection = reflection
        existing.updatedAt = Date()
        notesByDay[key] = existing
        save()
    }

    /// Converts a line from the daily notepad into a task in `PlannerStore` (for ⌘Return).
    @discardableResult
    public func convertLineToTask(
        line: String,
        into store: PlannerStore,
        date: Date = Date()
    ) -> NotchTask? {
        let cleaned = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[-*•\[\]xX\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return store.addParsedTask(from: cleaned, referenceDate: date, defaultToToday: true)
    }

    public var allNotes: [DailyNote] {
        notesByDay.values.sorted { $0.id > $1.id }
    }

    public func replaceAllNotes(_ notes: [DailyNote]) {
        notesByDay = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        if let decoded = try? JSONDecoder().decode([String: DailyNote].self, from: data) {
            self.notesByDay = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notesByDay) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
