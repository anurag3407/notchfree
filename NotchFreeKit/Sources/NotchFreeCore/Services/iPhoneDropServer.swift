import Foundation
import Network
import CoreImage
import AppKit

public struct DroppedItemPayload: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case text
        case file
    }

    public let id: UUID
    public let kind: Kind
    public let title: String
    public let text: String?
    public let fileURL: URL?
    public let receivedAt: Date

    public init(id: UUID = UUID(), kind: Kind, title: String, text: String? = nil, fileURL: URL? = nil, receivedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.fileURL = fileURL
        self.receivedAt = receivedAt
    }
}

/// Lightweight local Wi-Fi HTTP drop server so an iPhone on the same network
/// can send text, photos, or files straight into NotchFree without installing an app.
@MainActor
public final class iPhoneDropServer: ObservableObject {
    public static let shared = iPhoneDropServer()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var port: UInt16 = 38495
    @Published public private(set) var receivedItems: [DroppedItemPayload] = []

    public var onItemReceived: ((DroppedItemPayload) -> Void)?

    private var listener: NWListener?
    private let dropDirectory: URL

    public init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.dropDirectory = caches.appendingPathComponent("NotchFreeDrops", isDirectory: true)
        try? FileManager.default.createDirectory(at: dropDirectory, withIntermediateDirectories: true)
    }

    public var dropURLString: String {
        let host = Self.localIPAddress() ?? "localhost"
        return "http://\(host):\(port)/"
    }

    public func qrCodeImage() -> NSImage? {
        let data = Data(dropURLString.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    public func start(port: UInt16 = 38495) {
        stop()
        self.port = port
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        do {
            let listener = try NWListener(using: .tcp, on: nwPort)
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

    private nonisolated func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 10_485_760) { [weak self] data, _, _, _ in
            guard let self, let data else {
                connection.cancel()
                return
            }
            let raw = String(decoding: data, as: UTF8.self)
            if raw.hasPrefix("GET ") {
                let html = Self.uploadHTML
                let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data((header + html).utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            if raw.hasPrefix("POST /drop-text") {
                let body = raw.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
                let payload = DroppedItemPayload(kind: .text, title: "iPhone Text", text: body)
                Task { @MainActor in
                    self.receivedItems.insert(payload, at: 0)
                    self.onItemReceived?(payload)
                }
                let resp = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
                connection.send(content: Data(resp.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            if raw.hasPrefix("POST /drop-file") {
                let headerPart = raw.components(separatedBy: "\r\n\r\n").first ?? ""
                let fileName = headerPart
                    .components(separatedBy: "\r\n")
                    .first(where: { $0.lowercased().hasPrefix("x-filename:") })?
                    .components(separatedBy: ":").dropFirst().joined(separator: ":")
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "drop-\(Int(Date().timeIntervalSince1970)).bin"

                if let sepRange = data.range(of: Data("\r\n\r\n".utf8)) {
                    let fileData = data[sepRange.upperBound...]
                    let safeName = (fileName as NSString).lastPathComponent
                    let dest = self.dropDirectory.appendingPathComponent(safeName)
                    try? Data(fileData).write(to: dest)
                    let payload = DroppedItemPayload(kind: .file, title: safeName, fileURL: dest)
                    Task { @MainActor in
                        self.receivedItems.insert(payload, at: 0)
                        self.onItemReceived?(payload)
                    }
                }
                let resp = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
                connection.send(content: Data(resp.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            let notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(notFound.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private nonisolated static let uploadHTML = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Drop to NotchFree</title>
    <style>body{font-family:-apple-system,sans-serif;background:#111;color:#fff;padding:24px;max-width:480px;margin:auto}
    textarea,input,button{width:100%;margin-top:12px;padding:12px;border-radius:10px;border:1px solid #333;background:#1c1c1e;color:#fff;font-size:16px}
    button{background:#0a84ff;border:none;font-weight:600;cursor:pointer}</style></head>
    <body><h2>Drop to NotchFree</h2>
    <textarea id="txt" rows="4" placeholder="Paste text or link..."></textarea>
    <button onclick="sendText()">Send Text</button>
    <input type="file" id="f" onchange="sendFile()"/>
    <p id="status"></p>
    <script>
    async function sendText(){const v=document.getElementById('txt').value;if(!v)return;
    await fetch('/drop-text',{method:'POST',body:v});document.getElementById('txt').value='';
    document.getElementById('status').innerText='Sent text to NotchFree!';}
    async function sendFile(){const f=document.getElementById('f').files[0];if(!f)return;
    await fetch('/drop-file',{method:'POST',headers:{'X-Filename':f.name},body:f});
    document.getElementById('status').innerText='Sent '+f.name+' to NotchFree!';}
    </script></body></html>
    """

    private static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }
}
