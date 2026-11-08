import Foundation
import Network

/// AVPlayer reads saved HLS through a loopback-only endpoint. No video leaves the device.
final class LocalRecordingServer: @unchecked Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "mySportly.recording-playback")
    private let lock = NSLock()
    private var listener: NWListener?
    init(directory: URL) { self.directory = directory.standardizedFileURL }
    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        lock.withLock { self.listener = listener }
        return try await withCheckedThrowingContinuation { continuation in
            let latch = ReadyLatch()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port, latch.claim() else { return }
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/index.m3u8")!)
                case .failed(let error): if latch.claim() { continuation.resume(throwing: error) }
                case .cancelled: if latch.claim() { continuation.resume(throwing: CancellationError()) }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                connection.start(queue: self.queue); self.receive(connection, accumulated: Data())
            }
            listener.start(queue: queue)
        }
    }
    func stop() { lock.withLock { listener?.cancel(); listener = nil } }
    deinit { stop() }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var all = accumulated; if let data { all.append(data) }
            guard all.count <= 16384 else { connection.cancel(); return }
            if all.range(of: Data("\r\n\r\n".utf8)) != nil { self.respond(connection, request: String(decoding: all, as: UTF8.self)) }
            else if complete { connection.cancel() } else { self.receive(connection, accumulated: all) }
        }
    }
    private func respond(_ connection: NWConnection, request: String) {
        let lines = request.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2, ["GET", "HEAD"].contains(String(parts[0])),
              let decoded = String(parts[1]).components(separatedBy: "?")[0].removingPercentEncoding,
              !decoded.contains(".."), !decoded.contains("\\") else { send(connection, status: "400 Bad Request", body: Data()); return }
        let file = directory.appending(path: decoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL
        guard file.path.hasPrefix(directory.path + "/"), let data = try? Data(contentsOf: file, options: .mappedIfSafe), data.count <= 40 * 1024 * 1024 else { send(connection, status: "404 Not Found", body: Data()); return }
        let mime = file.pathExtension == "m3u8" ? "application/vnd.apple.mpegurl" : (file.pathExtension == "ts" ? "video/mp2t" : "video/mp4")
        let head = parts[0] == "HEAD"
        if let range = lines.first(where: { $0.lowercased().hasPrefix("range: bytes=") }) {
            let bounds = range.components(separatedBy: "=").last!.split(separator: "-", omittingEmptySubsequences: false)
            let lower = Int(bounds.first ?? "") ?? 0
            let upper = min(Int(bounds.count > 1 ? bounds[1] : "") ?? (data.count - 1), data.count - 1)
            guard lower >= 0, upper >= lower, upper < data.count else { send(connection, status: "416 Range Not Satisfiable", body: Data()); return }
            send(connection, status: "206 Partial Content", body: data.subdata(in: lower..<(upper + 1)), type: mime, extra: "Content-Range: bytes \(lower)-\(upper)/\(data.count)\r\n", head: head)
        } else { send(connection, status: "200 OK", body: data, type: mime, head: head) }
    }
    private func send(_ connection: NWConnection, status: String, body: Data, type: String = "text/plain", extra: String = "", head: Bool = false) {
        var response = Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\n\(extra)Connection: close\r\n\r\n".utf8)
        if !head { response.append(body) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
private final class ReadyLatch: @unchecked Sendable {
    private let lock = NSLock(); private var completed = false
    func claim() -> Bool { lock.withLock { if completed { return false }; completed = true; return true } }
}
