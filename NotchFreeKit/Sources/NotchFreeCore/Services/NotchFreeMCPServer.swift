import Foundation
import Network

/// Local Model Context Protocol (MCP) JSON-RPC 2.0 server over localhost HTTP
/// so Claude Code, Claude Desktop, and Cursor can manage NotchFree tasks, notes,
/// insights, and focus sessions on this Mac.
@MainActor
public final class NotchFreeMCPServer: ObservableObject {
    public static let shared = NotchFreeMCPServer()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var port: UInt16 = 38492
    @Published public private(set) var lastRequestSummary: String = ""

    private var listener: NWListener?

    public init() {}

    public func start(port: UInt16 = 38492) {
        stop()
        self.port = port
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)

        do {
            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.isRunning = (state == .ready)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener.start(queue: .global(qos: .userInitiated))
            self.listener = listener
        } catch {
            isRunning = false
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    public enum AgentClient: String, CaseIterable {
        case claudeDesktop = "Claude Desktop"
        case claudeCode = "Claude Code"
        case cursor = "Cursor"
    }

    /// Writes or merges the NotchFree MCP server entry into the target AI client's config file.
    public func installClientConfig(for client: AgentClient) throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configURL: URL
        switch client {
        case .claudeDesktop:
            configURL = home
                .appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
                .appendingPathComponent("claude_desktop_config.json")
        case .claudeCode:
            configURL = home.appendingPathComponent(".claude.json")
        case .cursor:
            configURL = home
                .appendingPathComponent(".cursor", isDirectory: true)
                .appendingPathComponent("mcp.json")
        }

        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var root: [String: Any] = [:]
        if let existingData = try? Data(contentsOf: configURL),
           let existingJSON = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            root = existingJSON
        }

        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        servers["notchfree"] = [
            "url": "http://127.0.0.1:\(port)/mcp",
            "transport": "http"
        ]
        root["mcpServers"] = servers

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL, options: .atomic)
        return configURL
    }

    // MARK: - JSON-RPC Dispatch (also testable directly)

    public func handleJSONRPC(_ requestData: Data) async -> Data {
        guard let req = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
              let method = req["method"] as? String else {
            return encodeJSONRPCError(id: nil, code: -32700, message: "Parse error")
        }
        let id = req["id"]
        let params = req["params"] as? [String: Any] ?? [:]
        lastRequestSummary = method

        switch method {
        case "initialize":
            return encodeJSONRPCResult(id: id, result: [
                "protocolVersion": "2024-11-05",
                "serverInfo": ["name": "notchfree-mcp", "version": "1.0.0"],
                "capabilities": ["tools": [:]]
            ])

        case "tools/list":
            return encodeJSONRPCResult(id: id, result: [
                "tools": Self.toolDefinitions
            ])

        case "tools/call":
            let toolName = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            let textResult = executeTool(name: toolName, arguments: args)
            return encodeJSONRPCResult(id: id, result: [
                "content": [["type": "text", "text": textResult]]
            ])

        default:
            return encodeJSONRPCError(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    public func executeTool(name: String, arguments: [String: Any]) -> String {
        let store = PlannerStore.shared
        let notepad = DailyNotepadStore.shared
        let insights = ProductivityInsightsStore.shared

        switch name {
        case "list_tasks":
            let includeCompleted = (arguments["include_completed"] as? Bool) ?? false
            let list = store.todayTasks(includeCompleted: includeCompleted)
            let items = list.map { t in
                "- [\(t.isCompleted ? "x" : " ")] \(t.title) (id: \(t.id.uuidString), priority: \(t.priority.label))"
            }
            return items.isEmpty ? "No tasks for today." : items.joined(separator: "\n")

        case "add_task":
            let input = (arguments["title"] as? String) ?? ""
            guard !input.isEmpty else { return "Missing 'title' argument." }
            let task = store.addParsedTask(from: input, defaultToToday: true)
            return "Added task '\(task.title)' (id: \(task.id.uuidString))."

        case "complete_task":
            guard let idStr = arguments["id"] as? String, let uuid = UUID(uuidString: idStr) else {
                return "Invalid or missing task 'id'."
            }
            store.toggleComplete(id: uuid)
            return "Toggled completion for task \(idStr)."

        case "get_daily_note":
            let note = notepad.note()
            return note.content.isEmpty ? "(Empty daily note)" : note.content

        case "append_daily_note":
            let line = (arguments["text"] as? String) ?? ""
            notepad.appendLine(line)
            return "Appended to today's notepad."

        case "get_insights":
            let streak = insights.currentStreak(tasks: store.tasks)
            let focusMins = insights.todayFocusMinutes()
            let completed = insights.completedTasksCount(in: store)
            return "Today focus: \(focusMins) min | Current streak: \(streak) days | Total completed tasks: \(completed)"

        default:
            return "Unknown tool: \(name)"
        }
    }

    private static let toolDefinitions: [[String: Any]] = [
        ["name": "list_tasks", "description": "List today's tasks in NotchFree", "inputSchema": ["type": "object", "properties": ["include_completed": ["type": "boolean"]]]],
        ["name": "add_task", "description": "Add a task using natural language (e.g. 'call mom tomorrow at 5pm')", "inputSchema": ["type": "object", "properties": ["title": ["type": "string"]], "required": ["title"]]],
        ["name": "complete_task", "description": "Toggle completion of a task by UUID", "inputSchema": ["type": "object", "properties": ["id": ["type": "string"]], "required": ["id"]]],
        ["name": "get_daily_note", "description": "Read today's daily notepad content", "inputSchema": ["type": "object", "properties": [:]]],
        ["name": "append_daily_note", "description": "Append a line to today's daily notepad", "inputSchema": ["type": "object", "properties": ["text": ["type": "string"]], "required": ["text"]]],
        ["name": "get_insights", "description": "Get focus minutes, streak, and completed tasks summary", "inputSchema": ["type": "object", "properties": [:]]]
    ]

    private nonisolated func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, _, _ in
            guard let self, let data else {
                connection.cancel()
                return
            }
            let raw = String(data: data, encoding: .utf8) ?? ""
            let bodyString = raw.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
            let bodyData = Data(bodyString.utf8)

            Task { @MainActor in
                let responseJSON = await self.handleJSONRPC(bodyData)
                let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(responseJSON.count)\r\nConnection: close\r\n\r\n"
                var payload = Data(header.utf8)
                payload.append(responseJSON)
                connection.send(content: payload, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func encodeJSONRPCResult(id: Any?, result: Any) -> Data {
        var obj: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { obj["id"] = id }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    private func encodeJSONRPCError(id: Any?, code: Int, message: String) -> Data {
        var obj: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message]]
        if let id { obj["id"] = id }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }
}
