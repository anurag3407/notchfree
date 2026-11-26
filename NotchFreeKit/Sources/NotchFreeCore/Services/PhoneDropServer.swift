import Foundation
import Network
import CoreImage
import AppKit

public struct DroppedItemPayload: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case text
        case file
    }

    public enum Source: Equatable, Sendable {
        case qrWebDrop
        case localSend(deviceAlias: String)

        public var label: String {
            switch self {
            case .qrWebDrop: return "QR Web Drop"
            case .localSend(let alias): return "LocalSend · \(alias)"
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    public let source: Source
    public let title: String
    public let text: String?
    public let fileURL: URL?
    public let receivedAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        source: Source = .qrWebDrop,
        title: String,
        text: String? = nil,
        fileURL: URL? = nil,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.title = title
        self.text = text
        self.fileURL = fileURL
        self.receivedAt = receivedAt
    }
}

public struct ShelfShareableFile: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let byteCount: Int64

    public init(id: String, name: String, url: URL, byteCount: Int64 = 0) {
        self.id = id
        self.name = name
        self.url = url
        self.byteCount = byteCount
    }
}

/// Two-way local Wi-Fi HTTP drop server so any Android or iPhone browser on the same Wi-Fi
/// can send files/photos/text to NotchFree AND pull Shelf files or the Mac clipboard,
/// with zero app install required.
@MainActor
public final class PhoneDropServer: ObservableObject {
    public static let shared = PhoneDropServer()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var port: UInt16 = 38495
    @Published public private(set) var sessionToken: String = PhoneDropServer.generateToken()
    @Published public private(set) var receivedItems: [DroppedItemPayload] = []
    @Published public private(set) var lastDropToast: String?

    /// Smart-routing callback invoked when an item arrives (files → Shelf, text → Clipboard).
    public var onItemReceived: ((DroppedItemPayload) -> Void)?
    /// Provides files currently on the Mac's NotchFree Shelf for Mac → Phone download.
    public var shelfFilesProvider: (() -> [ShelfShareableFile])?
    /// Provides the current Mac clipboard text for Mac → Phone copy.
    public var macClipboardProvider: (() -> String?)?

    private var listener: NWListener?
    public let dropDirectory: URL

    public init(dropDirectory: URL? = nil) {
        if let dropDirectory {
            self.dropDirectory = dropDirectory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.dropDirectory = caches.appendingPathComponent("NotchFreeDrops", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.dropDirectory, withIntermediateDirectories: true)
    }

    public var dropURLString: String {
        let host = Self.localIPAddress() ?? "localhost"
        return "http://\(host):\(port)/?token=\(sessionToken)"
    }

    public func regenerateToken() {
        sessionToken = Self.generateToken()
    }

    public func recordExternalDrop(_ payload: DroppedItemPayload) {
        receivedItems.insert(payload, at: 0)
        if receivedItems.count > 50 {
            receivedItems = Array(receivedItems.prefix(50))
        }
        lastDropToast = "Received \(payload.title) from \(payload.source.label)"
        onItemReceived?(payload)
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
        self.sessionToken = Self.generateToken()
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

    // MARK: - HTTP Request Processing (also testable directly)

    public func processHTTPRequest(_ data: Data) async -> Data {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEndRange = data.range(of: separator) else {
            return httpResponse(status: 400, contentType: "text/plain", body: Data("Bad Request".utf8))
        }
        let headerData = data[..<headerEndRange.lowerBound]
        let bodyData = data[headerEndRange.upperBound...]
        let headerString = String(decoding: headerData, as: UTF8.self)
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return httpResponse(status: 400, contentType: "text/plain", body: Data("Bad Request".utf8))
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return httpResponse(status: 400, contentType: "text/plain", body: Data("Bad Request".utf8))
        }

        let method = String(parts[0]).uppercased()
        let rawTarget = String(parts[1])
        let components = URLComponents(string: "http://localhost\(rawTarget)")
        let path = components?.path ?? rawTarget
        let queryToken = components?.queryItems?.first(where: { $0.name == "token" })?.value
        let headerToken = lines.first(where: { $0.lowercased().hasPrefix("x-drop-token:") })?
            .components(separatedBy: ":").dropFirst().joined(separator: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let providedToken = headerToken ?? queryToken
        guard providedToken == sessionToken else {
            return httpResponse(
                status: 401,
                contentType: "text/html; charset=utf-8",
                body: Data("<h3>Unauthorized</h3><p>Scan the current QR code in NotchFree to connect.</p>".utf8)
            )
        }

        if method == "GET" && path == "/" {
            let html = Self.makeWebUI(token: sessionToken)
            return httpResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(html.utf8))
        }

        if method == "POST" && path == "/drop-text" {
            let text = String(decoding: bodyData, as: UTF8.self)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return httpResponse(status: 400, contentType: "text/plain", body: Data("Empty text".utf8))
            }
            let title = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? "Phone Link" : "Phone Text"
            let payload = DroppedItemPayload(kind: .text, source: .qrWebDrop, title: title, text: text)
            recordExternalDrop(payload)
            return httpResponse(status: 200, contentType: "application/json", body: Data(#"{"ok":true}"#.utf8))
        }

        if method == "POST" && path == "/drop-file" {
            let rawName = lines.first(where: { $0.lowercased().hasPrefix("x-filename:") })?
                .components(separatedBy: ":").dropFirst().joined(separator: ":")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let decodedName = rawName?.removingPercentEncoding ?? rawName
            let fallbackName = "drop-\(Int(Date().timeIntervalSince1970)).bin"
            let safeName = ((decodedName?.isEmpty == false ? decodedName! : fallbackName) as NSString).lastPathComponent
            let dest = uniqueFileURL(in: dropDirectory, fileName: safeName)

            do {
                try Data(bodyData).write(to: dest, options: .atomic)
                let payload = DroppedItemPayload(kind: .file, source: .qrWebDrop, title: dest.lastPathComponent, fileURL: dest)
                recordExternalDrop(payload)
                return httpResponse(status: 200, contentType: "application/json", body: Data(#"{"ok":true}"#.utf8))
            } catch {
                return httpResponse(status: 500, contentType: "text/plain", body: Data("Write failed".utf8))
            }
        }

        if method == "GET" && path == "/mac-clipboard" {
            let text = macClipboardProvider?() ?? NSPasteboard.general.string(forType: .string) ?? ""
            let obj: [String: Any] = ["text": text]
            let json = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data(#"{"text":""}"#.utf8)
            return httpResponse(status: 200, contentType: "application/json; charset=utf-8", body: json)
        }

        if method == "GET" && path == "/shelf-files" {
            let files = shelfFilesProvider?() ?? []
            let list: [[String: Any]] = files.map {
                ["id": $0.id, "name": $0.name, "size": $0.byteCount]
            }
            let json = (try? JSONSerialization.data(withJSONObject: ["files": list])) ?? Data(#"{"files":[]}"#.utf8)
            return httpResponse(status: 200, contentType: "application/json; charset=utf-8", body: json)
        }

        if method == "GET" && path.hasPrefix("/shelf-file/") {
            let id = String(path.dropFirst("/shelf-file/".count))
            let files = shelfFilesProvider?() ?? []
            guard let match = files.first(where: { $0.id == id }),
                  let fileData = try? Data(contentsOf: match.url) else {
                return httpResponse(status: 404, contentType: "text/plain", body: Data("Not Found".utf8))
            }
            let safeName = match.name.replacingOccurrences(of: "\"", with: "_")
            let extraHeaders = ["Content-Disposition: attachment; filename=\"\(safeName)\""]
            return httpResponse(
                status: 200,
                contentType: "application/octet-stream",
                extraHeaders: extraHeaders,
                body: fileData
            )
        }

        return httpResponse(status: 404, contentType: "text/plain", body: Data("Not Found".utf8))
    }

    // MARK: - Buffered TCP Connection Reader (supports multi-MB photo/video uploads)

    private nonisolated func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        readFullHTTPRequest(from: connection, accumulated: Data(), expectedTotalLength: nil)
    }

    private nonisolated func readFullHTTPRequest(
        from connection: NWConnection,
        accumulated: Data,
        expectedTotalLength: Int?
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] chunk, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                _ = error
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let chunk {
                buffer.append(chunk)
            }

            var targetTotal = expectedTotalLength
            if targetTotal == nil, let sepRange = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerText = String(decoding: buffer[..<sepRange.lowerBound], as: UTF8.self)
                let contentLength = Self.parseContentLength(from: headerText)
                targetTotal = sepRange.upperBound + contentLength
            }

            // Cap at 250 MB to guard against runaway requests
            if let targetTotal, targetTotal > 250 * 1024 * 1024 {
                connection.cancel()
                return
            }

            let isReady: Bool
            if let targetTotal {
                isReady = buffer.count >= targetTotal || isComplete
            } else {
                isReady = isComplete
            }

            if isReady {
                Task { @MainActor in
                    let response = await self.processHTTPRequest(buffer)
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
            } else {
                self.readFullHTTPRequest(from: connection, accumulated: buffer, expectedTotalLength: targetTotal)
            }
        }
    }

    private nonisolated static func parseContentLength(from headerText: String) -> Int {
        for line in headerText.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let raw = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                return Int(raw) ?? 0
            }
        }
        return 0
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

    private func httpResponse(
        status: Int,
        contentType: String,
        extraHeaders: [String] = [],
        body: Data
    ) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }
        var lines = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close"
        ]
        lines.append(contentsOf: extraHeaders)
        lines.append("")
        lines.append("")
        var data = Data(lines.joined(separator: "\r\n").utf8)
        data.append(body)
        return data
    }

    private static func generateToken() -> String {
        let chars = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return String((0..<12).map { _ in chars.randomElement()! })
    }

    private nonisolated static func makeWebUI(token: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Drop to NotchFree (Android &amp; iPhone)</title>
        <style>
        *{box-sizing:border-box}
        body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#0d0d0f;color:#f5f5f7;padding:20px;max-width:520px;margin:auto}
        h2{margin:0 0 4px} .sub{color:#98989d;font-size:13px;margin-bottom:18px}
        .card{background:#1c1c1e;border:1px solid #2c2c2e;border-radius:14px;padding:14px;margin-bottom:14px}
        .card h3{margin:0 0 10px;font-size:15px}
        textarea,input[type=file]{width:100%;padding:10px;border-radius:10px;border:1px solid #3a3a3c;background:#121214;color:#fff;font-size:15px}
        button{width:100%;margin-top:10px;padding:11px;border-radius:10px;background:#0a84ff;color:#fff;border:none;font-size:15px;font-weight:600;cursor:pointer}
        button.secondary{background:#2c2c2e}
        .row{display:flex;justify-content:space-between;align-items:center;padding:8px 0;border-top:1px solid #2c2c2e;gap:8px}
        .row a{color:#0a84ff;text-decoration:none;font-weight:600;font-size:14px;white-space:nowrap}
        .prog{height:6px;background:#2c2c2e;border-radius:99px;overflow:hidden;margin-top:10px;display:none}
        .prog > div{height:100%;background:#30d158;width:0%;transition:width .1s}
        #status{font-size:13px;color:#30d158;min-height:18px;margin:8px 0 0}
        pre{white-space:pre-wrap;word-break:break-word;background:#121214;padding:10px;border-radius:8px;font-size:13px;max-height:140px;overflow:auto;margin:0}
        </style></head><body>
        <h2>NotchFree Phone Drop</h2>
        <div class="sub">Android &amp; iPhone · Paired over local Wi-Fi</div>
        <div class="card">
          <h3>Send Files / Photos → Mac Shelf</h3>
          <input type="file" id="f" multiple onchange="sendFiles()"/>
          <div class="prog" id="progBox"><div id="progBar"></div></div>
          <p id="status"></p>
        </div>
        <div class="card">
          <h3>Send Text / Link → Mac Clipboard</h3>
          <textarea id="txt" rows="3" placeholder="Paste text or link..."></textarea>
          <button onclick="sendText()">Send to Mac Clipboard</button>
        </div>
        <div class="card">
          <h3>Pull Mac Clipboard → Phone</h3>
          <pre id="clipBox">Loading...</pre>
          <button class="secondary" onclick="copyMacClip()">Copy Mac Clipboard</button>
        </div>
        <div class="card">
          <h3>Download Mac Shelf Files → Phone</h3>
          <div id="shelfList">Loading...</div>
          <button class="secondary" onclick="loadMacData()">Refresh</button>
        </div>
        <script>
        const TOKEN='\(token)';
        async function sendText(){
          const el=document.getElementById('txt');const v=el.value;if(!v.trim())return;
          const r=await fetch('/drop-text?token='+TOKEN,{method:'POST',body:v});
          if(r.ok){el.value='';document.getElementById('status').innerText='Sent text to Mac Clipboard!';}
        }
        async function sendFiles(){
          const files=Array.from(document.getElementById('f').files);if(!files.length)return;
          const box=document.getElementById('progBox'),bar=document.getElementById('progBar'),st=document.getElementById('status');
          box.style.display='block';
          for(let i=0;i<files.length;i++){
            const f=files[i];
            await new Promise((res,rej)=>{
              const xhr=new XMLHttpRequest();
              xhr.open('POST','/drop-file?token='+TOKEN);
              xhr.setRequestHeader('X-Filename',encodeURIComponent(f.name));
              xhr.upload.onprogress=(e)=>{if(e.lengthComputable){bar.style.width=Math.round((e.loaded/e.total)*100)+'%';}};
              xhr.onload=()=>xhr.status<300?res():rej();
              xhr.onerror=rej;
              st.innerText='Uploading ('+(i+1)+'/'+files.length+'): '+f.name;
              xhr.send(f);
            });
          }
          bar.style.width='100%';st.innerText='Sent '+files.length+' file(s) to Mac Shelf!';
        }
        async function loadMacData(){
          const cr=await fetch('/mac-clipboard?token='+TOKEN);
          if(cr.ok){const d=await cr.json();document.getElementById('clipBox').innerText=d.text||'(Mac clipboard is empty)';}
          const sr=await fetch('/shelf-files?token='+TOKEN);
          if(sr.ok){
            const d=await sr.json();
            const list=document.getElementById('shelfList');
            if(!d.files.length){list.innerHTML='<div class="sub">No files on Mac Shelf</div>';return;}
            list.innerHTML=d.files.map(f=>'<div class="row"><span>'+f.name+'</span><a href="/shelf-file/'+encodeURIComponent(f.id)+'?token='+TOKEN+'">Download</a></div>').join('');
          }
        }
        async function copyMacClip(){
          const txt=document.getElementById('clipBox').innerText;
          if(navigator.clipboard)await navigator.clipboard.writeText(txt);
          document.getElementById('status').innerText='Copied Mac clipboard to phone!';
        }
        loadMacData();
        </script></body></html>
        """
    }

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

public typealias iPhoneDropServer = PhoneDropServer
