import Foundation

public enum LocalSendReceiveDecision: Sendable {
    case acceptOnce
    case alwaysTrust
    case decline
}

public enum LocalSendReceiveState: Equatable, Sendable {
    case idle
    case awaitingApproval
    case receiving(progress: Double, fileName: String)
    case completed(summary: String)
    case rejected
    case failed(String)
}

public struct PendingLocalSendOffer: Identifiable, Equatable, Sendable {
    public let id: String
    public let senderFingerprint: String
    public let senderAlias: String
    public let senderModel: String?
    public let fileCount: Int
    public let totalBytes: Int64
    public let previewNames: [String]

    public init(
        id: String,
        senderFingerprint: String,
        senderAlias: String,
        senderModel: String?,
        fileCount: Int,
        totalBytes: Int64,
        previewNames: [String]
    ) {
        self.id = id
        self.senderFingerprint = senderFingerprint
        self.senderAlias = senderAlias
        self.senderModel = senderModel
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.previewNames = previewNames
    }
}

/// Implements the LocalSend v2 receive protocol (`prepare-upload`, `upload`, `cancel`)
/// with persistent trusted-device management and notch approval prompts.
@MainActor
public final class LocalSendReceiveCoordinator: ObservableObject {
    public static let shared = LocalSendReceiveCoordinator()

    @Published public private(set) var receiveState: LocalSendReceiveState = .idle
    @Published public private(set) var pendingOffer: PendingLocalSendOffer?
    @Published public private(set) var trustedDevices: [String: String] = [:] // fingerprint -> alias

    private struct ActiveReceiveSession {
        let id: String
        let senderAlias: String
        var files: [String: ExpectedFile]
        var receivedBytes: Int64 = 0
        var totalBytes: Int64
        var completedFileIDs: Set<String> = []
    }

    private struct ExpectedFile {
        let id: String
        let fileName: String
        let fileType: String
        let size: Int64
        let token: String
        let previewText: String?
    }

    private var activeSessions: [String: ActiveReceiveSession] = [:]
    private var pendingContinuation: CheckedContinuation<LocalSendReceiveDecision, Never>?
    private let trustStorageURL: URL
    private let dropDirectory: URL
    private var dismissTask: Task<Void, Never>?

    public var onDropReceived: ((DroppedItemPayload) -> Void)?

    public init(trustStorageURL: URL? = nil, dropDirectory: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NotchFree", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.trustStorageURL = trustStorageURL ?? dir.appendingPathComponent("trusted_localsend_devices.json")

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.dropDirectory = dropDirectory ?? caches.appendingPathComponent("NotchFreeDrops", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.dropDirectory, withIntermediateDirectories: true)

        loadTrustedDevices()
    }

    // MARK: - Trust Management

    public func isDeviceTrusted(fingerprint: String) -> Bool {
        trustedDevices[fingerprint] != nil
    }

    public func trustDevice(fingerprint: String, alias: String) {
        trustedDevices[fingerprint] = alias
        saveTrustedDevices()
    }

    public func untrustDevice(fingerprint: String) {
        trustedDevices.removeValue(forKey: fingerprint)
        saveTrustedDevices()
    }

    public func respondToPendingOffer(_ decision: LocalSendReceiveDecision) {
        if decision == .alwaysTrust, let offer = pendingOffer {
            trustDevice(fingerprint: offer.senderFingerprint, alias: offer.senderAlias)
        }
        pendingOffer = nil
        pendingContinuation?.resume(returning: decision)
        pendingContinuation = nil
    }

    // MARK: - LocalSend v2 Protocol Handlers

    public func handlePrepareUpload(bodyData: Data) async -> (status: Int, json: [String: Any]) {
        guard let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let info = json["info"] as? [String: Any],
              let filesDict = json["files"] as? [String: [String: Any]],
              !filesDict.isEmpty else {
            return (400, ["error": "invalid-prepare-upload"])
        }

        let fingerprint = (info["fingerprint"] as? String) ?? UUID().uuidString
        let alias = (info["alias"] as? String) ?? "Android Device"
        let model = info["deviceModel"] as? String

        var expectedFiles: [String: ExpectedFile] = [:]
        var tokenMap: [String: String] = [:]
        var totalBytes: Int64 = 0
        var previewNames: [String] = []

        for (fileID, fileObj) in filesDict {
            let fileName = (fileObj["fileName"] as? String) ?? "file-\(fileID)"
            let fileType = (fileObj["fileType"] as? String) ?? "application/octet-stream"
            let size = (fileObj["size"] as? NSNumber)?.int64Value ?? 0
            let preview = fileObj["preview"] as? String
            let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")

            expectedFiles[fileID] = ExpectedFile(
                id: fileID,
                fileName: fileName,
                fileType: fileType,
                size: size,
                token: token,
                previewText: preview
            )
            tokenMap[fileID] = token
            totalBytes += max(0, size)
            previewNames.append(fileName)
        }

        let sessionID = UUID().uuidString

        if !isDeviceTrusted(fingerprint: fingerprint) {
            let offer = PendingLocalSendOffer(
                id: sessionID,
                senderFingerprint: fingerprint,
                senderAlias: alias,
                senderModel: model,
                fileCount: expectedFiles.count,
                totalBytes: totalBytes,
                previewNames: previewNames
            )
            let decision = await requestUserApproval(for: offer)
            guard decision != .decline else {
                receiveState = .rejected
                scheduleAutoDismiss()
                return (403, ["error": "rejected"])
            }
        }

        activeSessions[sessionID] = ActiveReceiveSession(
            id: sessionID,
            senderAlias: alias,
            files: expectedFiles,
            totalBytes: max(1, totalBytes)
        )
        let firstTitle = previewNames.first ?? "Transfer"
        receiveState = .receiving(progress: 0, fileName: firstTitle)

        return (200, [
            "sessionId": sessionID,
            "files": tokenMap
        ])
    }

    public func handleUpload(sessionID: String, fileID: String, token: String, bodyData: Data) -> (status: Int, json: [String: Any]) {
        guard var session = activeSessions[sessionID],
              let expected = session.files[fileID],
              expected.token == token else {
            return (403, ["error": "invalid-session-or-token"])
        }

        let source = DroppedItemPayload.Source.localSend(deviceAlias: session.senderAlias)

        if expected.fileType.lowercased().hasPrefix("text/plain") {
            let text = String(data: bodyData, encoding: .utf8) ?? expected.previewText ?? ""
            let payload = DroppedItemPayload(
                kind: .text,
                source: source,
                title: expected.fileName,
                text: text
            )
            emitDrop(payload)
        } else {
            let safeName = (expected.fileName as NSString).lastPathComponent
            let dest = uniqueFileURL(in: dropDirectory, fileName: safeName)
            do {
                try bodyData.write(to: dest, options: .atomic)
                let payload = DroppedItemPayload(
                    kind: .file,
                    source: source,
                    title: dest.lastPathComponent,
                    fileURL: dest
                )
                emitDrop(payload)
            } catch {
                receiveState = .failed("Could not save \(safeName)")
                scheduleAutoDismiss()
                return (500, ["error": "write-failed"])
            }
        }

        session.completedFileIDs.insert(fileID)
        session.receivedBytes += Int64(bodyData.count)
        let progress = min(1.0, Double(session.receivedBytes) / Double(max(1, session.totalBytes)))

        if session.completedFileIDs.count >= session.files.count {
            let count = session.files.count
            activeSessions.removeValue(forKey: sessionID)
            receiveState = .completed(summary: "\(count) item(s) from \(session.senderAlias)")
            scheduleAutoDismiss()
        } else {
            activeSessions[sessionID] = session
            receiveState = .receiving(progress: progress, fileName: expected.fileName)
        }

        return (200, ["ok": true])
    }

    public func handleCancel(sessionID: String) -> (status: Int, json: [String: Any]) {
        activeSessions.removeValue(forKey: sessionID)
        if pendingOffer?.id == sessionID {
            respondToPendingOffer(.decline)
        }
        receiveState = .idle
        return (200, ["ok": true])
    }

    // MARK: - Helpers

    private func emitDrop(_ payload: DroppedItemPayload) {
        PhoneDropServer.shared.recordExternalDrop(payload)
        onDropReceived?(payload)
    }

    private func requestUserApproval(for offer: PendingLocalSendOffer) async -> LocalSendReceiveDecision {
        // Cancel any lingering prompt before showing a new one
        if pendingContinuation != nil {
            respondToPendingOffer(.decline)
        }
        pendingOffer = offer
        receiveState = .awaitingApproval

        return await withCheckedContinuation { continuation in
            pendingContinuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if self?.pendingOffer?.id == offer.id {
                    self?.respondToPendingOffer(.decline)
                }
            }
        }
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self else { return }
            switch self.receiveState {
            case .completed, .rejected, .failed:
                self.receiveState = .idle
            default:
                break
            }
        }
    }

    private func uniqueFileURL(in directory: URL, fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            candidate = directory.appendingPathComponent(nextName)
            counter += 1
        }
        return candidate
    }

    private func loadTrustedDevices() {
        guard let data = try? Data(contentsOf: trustStorageURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        trustedDevices = decoded
    }

    private func saveTrustedDevices() {
        guard let data = try? JSONEncoder().encode(trustedDevices) else { return }
        try? data.write(to: trustStorageURL, options: .atomic)
    }
}
