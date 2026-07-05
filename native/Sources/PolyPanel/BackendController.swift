import Foundation
import Combine

/// Finds/starts the FastAPI backend and polls a tiny summary for the menu bar.
@MainActor
final class BackendController: ObservableObject {
    @Published var isUp = false
    @Published var totalBalance: Double? = nil
    @Published var liveStrats = 0
    @Published var paperStrats = 0

    let port: Int
    var dashboardURL: URL { URL(string: "http://127.0.0.1:\(port)/")! }

    private var timer: Timer?

    init() {
        // read PANEL_PORT from config/panel.env next to the repo, else 8799
        var p = 8799
        if let root = Self.repoRoot(),
           let txt = try? String(contentsOf: root.appendingPathComponent("config/panel.env")) {
            for line in txt.split(separator: "\n") where line.hasPrefix("PANEL_PORT=") {
                p = Int(line.dropFirst("PANEL_PORT=".count)) ?? p
            }
        }
        port = p
        startPolling()
    }

    var menuSummary: String {
        guard isUp else { return "▲ …" }
        let bal = totalBalance.map { String(format: "$%.2f", $0) } ?? "—"
        return liveStrats > 0 ? "▲ \(bal) · \(liveStrats) live" : "▲ \(bal)"
    }

    /// The repo root (…/polymarket-control-panel), whether we run from
    /// native/.build or from the packaged .app sitting in native/.
    static func repoRoot() -> URL? {
        var dir = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<5 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("backend/server.py").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    func ensureRunning() {
        Task {
            if await ping() { isUp = true; return }
            guard let root = Self.repoRoot() else { return }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = [root.appendingPathComponent("backend/run.sh").path]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if await ping() { isUp = true; break }
            }
        }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        Task { await refresh() }
    }

    private func ping() async -> Bool {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/health")!)
        req.timeoutInterval = 2
        return (try? await URLSession.shared.data(for: req)) != nil
    }

    func refresh() async {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/accounts") else { return }
        var req = URLRequest(url: url); req.timeoutInterval = 6
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = obj["accounts"] as? [[String: Any]] else {
            isUp = false; return
        }
        isUp = true
        totalBalance = accounts.compactMap { $0["balance_usd"] as? Double }.reduce(0, +)
        var live = 0, paper = 0
        for a in accounts {
            for s in (a["running_strats"] as? [[String: Any]] ?? []) {
                if (s["live"] as? Bool) == true { live += 1 } else { paper += 1 }
            }
        }
        liveStrats = live; paperStrats = paper
    }
}
