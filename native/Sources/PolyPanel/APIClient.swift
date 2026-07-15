import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Thin async client for the local panel backend.
final class APIClient: Sendable {
    static let shared = APIClient()

    let base: URL
    let repoRoot: URL?

    init() {
        let root = Self.findRepoRoot()
        repoRoot = root
        var port = 8799
        if let root,
           let txt = try? String(contentsOf: root.appendingPathComponent("config/panel.env"),
                                 encoding: .utf8) {
            for line in txt.split(separator: "\n") where line.hasPrefix("PANEL_PORT=") {
                port = Int(line.dropFirst("PANEL_PORT=".count)) ?? port
            }
        }
        base = URL(string: "http://127.0.0.1:\(port)")!
    }

    /// Walk up from the executable to find the repo (works from .app in native/
    /// and from `swift run` inside native/.build/...).
    static func findRepoRoot() -> URL? {
        var dir = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<7 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("backend/server.py").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:],
                           timeout: TimeInterval = 30) async throws -> T {
        var comps = URLComponents(url: base.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = timeout
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// POST with an untyped body; returns the untyped response dict.
    /// Untyped because start/order responses vary by dry-run vs live.
    func post(_ path: String, body: [String: Any],
              timeout: TimeInterval = 120) async throws -> [String: Any] {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = timeout
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func delete(_ path: String, query: [String: String] = [:],
                timeout: TimeInterval = 60) async throws -> [String: Any] {
        var comps = URLComponents(url: base.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        req.timeoutInterval = timeout
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard !(200...299).contains(http.statusCode) else { return }
        var msg = "HTTP \(http.statusCode)"
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = obj["detail"] as? String {
            msg = detail
        }
        throw APIError(message: msg)
    }
}
