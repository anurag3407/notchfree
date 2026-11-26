#if canImport(Testing)
import Foundation
import Testing
@testable import NotchFreeCore

@Suite("NotchFreeCore Tests")
struct NotchFreeCoreTests {
    private var fixedCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        return fixedCalendar.date(from: comps)!
    }

    @Test("Natural language task parser extracts date, time, priority, project, recurrence")
    func naturalLanguageTaskParser() {
        let ref = makeDate(2026, 11, 26, 10, 0)

        let parsed1 = NaturalLanguageTaskParser.parse("Call mom tomorrow at 5pm !high #family", referenceDate: ref, calendar: fixedCalendar)
        #expect(parsed1.title == "Call mom")
        #expect(parsed1.priority == .high)
        #expect(parsed1.project == "family")
        #expect(parsed1.scheduledDay == makeDate(2026, 11, 27, 0, 0))
        #expect(parsed1.reminderDate == makeDate(2026, 11, 27, 17, 0))

        let parsed2 = NaturalLanguageTaskParser.parse("Standup every weekday at 9:30am", referenceDate: ref, calendar: fixedCalendar)
        #expect(parsed2.title == "Standup")
        #expect(parsed2.recurrence == .weekdays)
        #expect(parsed2.reminderDate == makeDate(2026, 11, 26, 9, 30))

        let parsed3 = NaturalLanguageTaskParser.parse("Review PR in 2h", referenceDate: ref, calendar: fixedCalendar)
        #expect(parsed3.title == "Review PR")
        #expect(parsed3.reminderDate == makeDate(2026, 11, 26, 12, 0))
    }

    @Test("DayPlannerEngine schedules untimed tasks around calendar events")
    func dayPlannerEngineSchedulesAroundEvents() {
        let start = makeDate(2026, 11, 26, 9, 0)
        let end = makeDate(2026, 11, 26, 12, 0)

        let event = CalendarTimeBlock(
            title: "Team Sync",
            start: makeDate(2026, 11, 26, 9, 30),
            end: makeDate(2026, 11, 26, 10, 30)
        )

        let t1 = NotchTask(title: "High Task", durationMinutes: 30, priority: .high, orderIndex: 1)
        let t2 = NotchTask(title: "Medium Task", durationMinutes: 60, priority: .medium, orderIndex: 0)

        let slots = DayPlannerEngine.generatePlan(
            tasks: [t2, t1],
            events: [event],
            startTime: start,
            endTime: end
        )

        #expect(slots.count == 2)
        #expect(slots[0].task.title == "High Task")
        #expect(slots[0].plannedStart == makeDate(2026, 11, 26, 9, 0))
        #expect(slots[0].plannedEnd == makeDate(2026, 11, 26, 9, 30))
        #expect(slots[1].task.title == "Medium Task")
        #expect(slots[1].plannedStart == makeDate(2026, 11, 26, 10, 30))
        #expect(slots[1].plannedEnd == makeDate(2026, 11, 26, 11, 30))
    }

    @Test("PlannerStore repeating tasks and wrap-up")
    @MainActor
    func plannerStoreRepeatingAndWrapUp() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = PlannerStore(storageURL: tempDir.appendingPathComponent("tasks.json"), calendar: fixedCalendar)

        let today = makeDate(2026, 11, 26, 10, 0)
        let recurring = store.addTask(title: "Daily Journal", scheduledDay: today, recurrence: .daily)
        let unfinished = store.addTask(title: "Write Docs", scheduledDay: today)

        store.toggleComplete(id: recurring.id, now: today)
        #expect(store.tasks.count == 3)
        let tomorrow = makeDate(2026, 11, 27, 0, 0)
        #expect(store.tasks.contains { $0.title == "Daily Journal" && !$0.isCompleted && $0.scheduledDay == tomorrow })

        let wrapResult = store.wrapUpDay(from: today, moveRemainingTo: .inbox)
        #expect(wrapResult.completedCount == 1)
        #expect(wrapResult.movedCount == 1)
        #expect(store.inboxTasks().contains { $0.id == unfinished.id })
    }

    @Test("DailyNotepadStore converts line to task and ProductivityInsightsStore tracks streak")
    @MainActor
    func notepadConvertLineToTaskAndInsights() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = PlannerStore(storageURL: tempDir.appendingPathComponent("tasks.json"), calendar: fixedCalendar)
        let notepad = DailyNotepadStore(storageURL: tempDir.appendingPathComponent("notes.json"), calendar: fixedCalendar)
        let insights = ProductivityInsightsStore(storageURL: tempDir.appendingPathComponent("sessions.json"), calendar: fixedCalendar)

        let today = makeDate(2026, 11, 26, 14, 0)
        let created = notepad.convertLineToTask(line: "- Ship release !high", into: store, date: today)
        #expect(created?.title == "Ship release")
        #expect(created?.priority == .high)

        insights.recordSession(FocusSessionRecord(startedAt: today, endedAt: today.addingTimeInterval(1500), durationSeconds: 1500, completed: true))
        #expect(insights.todayFocusMinutes(referenceDate: today) == 25)
        #expect(insights.currentStreak(tasks: store.tasks, referenceDate: today) == 1)
        #expect(insights.bestFocusHours().first?.hour == 14)

        let summary = insights.weeklySummary(tasks: store.tasks, referenceDate: today)
        #expect(summary.dailyPoints.count == 7)
        #expect(summary.focusMinutesLast7Days == 25)
        #expect(summary.activeDaysLast7Days == 1)
    }

    @Test("BookingCalendarClient decodes Calendly and Cal.com payloads")
    func bookingPayloadsDecoding() {
        let calendlyJSON = """
        {"collection":[{"uri":"https://api.calendly.com/scheduled_events/1","name":"Intro Call","start_time":"2026-11-26T15:00:00Z","end_time":"2026-11-26T15:30:00Z","location":{"join_url":"https://zoom.us/j/123"}}]}
        """.data(using: .utf8)!
        let calendlyEvents = BookingCalendarClient.parseCalendlyPayload(calendlyJSON)
        #expect(calendlyEvents.count == 1)
        #expect(calendlyEvents[0].title == "Intro Call")
        #expect(calendlyEvents[0].conferenceURL?.absoluteString == "https://zoom.us/j/123")

        let calComJSON = """
        {"bookings":[{"id":42,"title":"Design Review","startTime":"2026-11-26T16:00:00Z","endTime":"2026-11-26T16:45:00Z","status":"ACCEPTED","location":"https://meet.google.com/abc"}]}
        """.data(using: .utf8)!
        let calComEvents = BookingCalendarClient.parseCalComPayload(calComJSON)
        #expect(calComEvents.count == 1)
        #expect(calComEvents[0].source == "Cal.com")
    }

    @Test("MCP server JSON-RPC and Backup round-trip")
    @MainActor
    func mcpServerJSONRPCAndBackupRoundTrip() async throws {
        let initReq = #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#.data(using: .utf8)!
        let initResp = await NotchFreeMCPServer.shared.handleJSONRPC(initReq)
        let initObj = try JSONSerialization.jsonObject(with: initResp) as? [String: Any]
        #expect(initObj?["result"] != nil)

        let listReq = #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.data(using: .utf8)!
        let listResp = await NotchFreeMCPServer.shared.handleJSONRPC(listReq)
        let listObj = try JSONSerialization.jsonObject(with: listResp) as? [String: Any]
        let tools = (listObj?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        #expect(tools?.count == 6)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let store = PlannerStore(storageURL: tempDir.appendingPathComponent("tasks.json"), calendar: fixedCalendar)
        let notepad = DailyNotepadStore(storageURL: tempDir.appendingPathComponent("notes.json"), calendar: fixedCalendar)
        store.addTask(title: "Backup Test")
        notepad.updateContent("Note line", for: makeDate(2026, 11, 26))

        let exported = try PlannerBackup.exportJSON(tasks: store, notepad: notepad, sessions: [])
        store.replaceAllTasks([])
        let restored = try PlannerBackup.importJSON(exported, into: store, notepad: notepad) { _ in }
        #expect(restored.tasks.count == 1)
        #expect(store.tasks.first?.title == "Backup Test")
    }

    @Test("PhoneDropServer two-way Android & iPhone drop + LocalSendReceiveCoordinator")
    @MainActor
    func phoneDropAndLocalSendReceiver() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dropServer = PhoneDropServer(dropDirectory: tempDir)
        let token = dropServer.sessionToken
        var routedItems: [DroppedItemPayload] = []
        dropServer.onItemReceived = { routedItems.append($0) }
        dropServer.macClipboardProvider = { "Copied from Mac" }

        let shelfSample = tempDir.appendingPathComponent("hello.txt")
        try Data("from mac shelf".utf8).write(to: shelfSample)
        dropServer.shelfFilesProvider = {
            [ShelfShareableFile(id: "item-1", name: "hello.txt", url: shelfSample, byteCount: 14)]
        }

        // Unauthorized request rejected
        let unauth = await dropServer.processHTTPRequest(Data("GET / HTTP/1.1\r\n\r\n".utf8))
        #expect(String(decoding: unauth, as: UTF8.self).contains("401 Unauthorized"))

        // Text drop
        let textReq = Data("POST /drop-text?token=\(token) HTTP/1.1\r\nContent-Length: 18\r\n\r\nhttps://notchfree.app".utf8)
        let textResp = await dropServer.processHTTPRequest(textReq)
        #expect(String(decoding: textResp, as: UTF8.self).contains("200 OK"))
        #expect(routedItems.last?.kind == .text)

        // File drop
        let fileReq = Data("POST /drop-file?token=\(token) HTTP/1.1\r\nX-Filename: pixel_photo.jpg\r\nContent-Length: 4\r\n\r\nJPEG".utf8)
        let fileResp = await dropServer.processHTTPRequest(fileReq)
        #expect(String(decoding: fileResp, as: UTF8.self).contains("200 OK"))
        #expect(routedItems.last?.kind == .file)

        // Pull Mac clipboard & Shelf file
        let clipResp = await dropServer.processHTTPRequest(Data("GET /mac-clipboard?token=\(token) HTTP/1.1\r\n\r\n".utf8))
        #expect(String(decoding: clipResp, as: UTF8.self).contains("Copied from Mac"))
        let dlResp = await dropServer.processHTTPRequest(Data("GET /shelf-file/item-1?token=\(token) HTTP/1.1\r\n\r\n".utf8))
        #expect(String(decoding: dlResp, as: UTF8.self).contains("from mac shelf"))

        // LocalSendReceiveCoordinator trust + prepare-upload + upload
        let receiver = LocalSendReceiveCoordinator(
            trustStorageURL: tempDir.appendingPathComponent("trust.json"),
            dropDirectory: tempDir
        )
        receiver.trustDevice(fingerprint: "android-pixel-9", alias: "Pixel 9")
        let prepareBody = """
        {"info":{"alias":"Pixel 9","fingerprint":"android-pixel-9","deviceModel":"Pixel 9"},"files":{"f1":{"id":"f1","fileName":"android.png","size":3,"fileType":"image/png"}}}
        """.data(using: .utf8)!
        let prepRes = await receiver.handlePrepareUpload(bodyData: prepareBody)
        #expect(prepRes.status == 200)
        let sid = prepRes.json["sessionId"] as? String ?? ""
        let uploadToken = (prepRes.json["files"] as? [String: String])?["f1"] ?? ""
        let upRes = receiver.handleUpload(sessionID: sid, fileID: "f1", token: uploadToken, bodyData: Data("PNG".utf8))
        #expect(upRes.status == 200)
        #expect(receiver.receiveState == .completed(summary: "1 item(s) from Pixel 9"))
    }
}
#endif
