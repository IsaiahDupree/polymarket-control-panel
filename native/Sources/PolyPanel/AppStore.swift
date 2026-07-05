import Foundation
import SwiftUI

struct Toast: Identifiable, Equatable {
    enum Kind { case info, ok, error }
    let id = UUID()
    let text: String
    let kind: Kind
}

/// Single observable source of truth: polls the backend, exposes typed state,
/// performs guarded writes, and can auto-start the backend process.
@MainActor
final class AppStore: ObservableObject {
    let api = APIClient.shared

    @Published var backendUp = false
    @Published var health: Health?
    @Published var accounts: [Account] = []
    @Published var catalog: [Strat] = []
    @Published var stratsEnabled = true
    @Published var running: [String: [RunningStrat]] = [:]

    @Published var portfolio: [HistoryPoint] = []
    @Published var portfolioChange: Change?
    @Published var stratActivity: [StratPoint] = []
    @Published var sparks: [String: [HistoryPoint]] = [:]
    @Published var sparkChanges: [String: Change] = [:]

    @Published var hours: Double = 24 {
        didSet { Task { await loadHistory() } }
    }
    @Published var toasts: [Toast] = []

    private var timers: [Timer] = []
    private var backendProcess: Process?

    // ---------------- derived ----------------
    var totalBalance: Double? {
        let vals = accounts.compactMap(\.balance_usd)
        return vals.isEmpty ? nil : vals.reduce(0, +)
    }
    var liveCount: Int { accounts.reduce(0) { $0 + $1.liveStrats.count } }
    var paperCount: Int { accounts.reduce(0) { $0 + $1.paperStrats.count } }
    var menuSummary: String {
        guard backendUp, let bal = totalBalance else { return "▲ …" }
        let b = String(format: "$%.2f", bal)
        return liveCount > 0 ? "▲ \(b) · \(liveCount) live" : "▲ \(b)"
    }

    // ---------------- lifecycle ----------------
    func bootstrap() {
        guard timers.isEmpty else { return }
        ensureBackendRunning()
        schedule(8) { await self.loadFast() }
        schedule(30) { await self.loadHealth() }
        schedule(60) { await self.loadHistory() }
        Task {
            await loadHealth()
            await loadFast()
            await loadCatalog()
            await loadHistory()
        }
    }

    private func schedule(_ secs: TimeInterval, _ op: @escaping () async -> Void) {
        let t = Timer.scheduledTimer(withTimeInterval: secs, repeats: true) { _ in
            Task { await op() }
        }
        timers.append(t)
    }

    func ensureBackendRunning() {
        Task {
            if (try? await api.get("/api/health", timeout: 2) as Health) != nil {
                backendUp = true; return
            }
            guard let root = api.repoRoot, backendProcess == nil else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = [root.appendingPathComponent("backend/run.sh").path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            backendProcess = p
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if (try? await api.get("/api/health", timeout: 2) as Health) != nil {
                    backendUp = true
                    await loadFast(); await loadCatalog(); await loadHistory()
                    break
                }
            }
        }
    }

    // ---------------- loads ----------------
    func loadHealth() async {
        do {
            health = try await api.get("/api/health")
            stratsEnabled = health?.strats_enabled ?? true
            backendUp = true
        } catch { backendUp = false }
    }

    func loadFast() async {
        do {
            let payload: AccountsPayload = try await api.get("/api/accounts")
            accounts = payload.accounts
            let run: RunningPayload = try await api.get("/api/strats/running")
            running = run.running
            backendUp = true
        } catch { backendUp = false }
    }

    func loadCatalog() async {
        if let c: CatalogPayload = try? await api.get("/api/strats/catalog") {
            catalog = c.strats
            stratsEnabled = c.enabled ?? true
        }
    }

    func loadHistory() async {
        let h = String(hours)
        if let bal: BalanceHistory = try? await api.get("/api/history/balances",
                                                        query: ["hours": h]) {
            portfolio = bal.series
            portfolioChange = bal.change
        }
        if let st: StratHistory = try? await api.get("/api/history/strats",
                                                     query: ["hours": h]) {
            stratActivity = st.series
        }
        for a in accounts {
            if let s: BalanceHistory = try? await api.get("/api/history/balances",
                                                          query: ["account": a.id, "hours": h]) {
                sparks[a.id] = s.series
                sparkChanges[a.id] = s.change
            }
        }
    }

    // ---------------- writes (guarded server-side too) ----------------
    func previewStart(account: String, strat: String, params: [String: Any],
                      live: Bool) async -> String? {
        do {
            let r = try await api.post("/api/strats/start", body: [
                "account": account, "strat": strat, "params": params,
                "live": live, "dryRun": true])
            return r["command"] as? String
        } catch { toast(error.localizedDescription, .error); return nil }
    }

    func startStrat(account: String, strat: String, params: [String: Any],
                    live: Bool) async {
        do {
            let r = try await api.post("/api/strats/start", body: [
                "account": account, "strat": strat, "params": params,
                "live": live, "dryRun": false, "confirm": live])
            let pid = (r["pid"] as? Int).map(String.init) ?? "?"
            toast("Started \(strat) (\(live ? "LIVE" : "paper")) pid \(pid)", .ok)
            await loadFast()
        } catch { toast(error.localizedDescription, .error) }
    }

    func stopStrat(account: String, stratKey: String, kill: Bool) async {
        do {
            _ = try await api.post("/api/strats/stop", body: [
                "account": account, "strat": stratKey,
                "mode": kill ? "kill" : "stop", "confirm": true])
            toast("\(kill ? "Kill" : "Stop") sent to \(stratKey) on \(account)", .ok)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await loadFast()
        } catch { toast(error.localizedDescription, .error) }
    }

    func killSwitch(account: String) async {
        do {
            _ = try await api.post("/api/accounts/\(account)/kill_switch",
                                   body: ["confirm": true])
            toast("Kill switch fired for \(account)", .ok)
            await loadFast()
        } catch { toast(error.localizedDescription, .error) }
    }

    // ---------------- toasts ----------------
    func toast(_ text: String, _ kind: Toast.Kind = .info) {
        let t = Toast(text: text, kind: kind)
        toasts.append(t)
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            toasts.removeAll { $0 == t }
        }
    }
}
