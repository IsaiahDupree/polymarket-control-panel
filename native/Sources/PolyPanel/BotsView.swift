import SwiftUI

/// Every running bot — live AND paper — selectable, with its full launch
/// config, an instance-count history graph, and its latest log, all in one
/// master-detail view.
struct BotsView: View {
    @EnvironmentObject var store: AppStore

    enum Mode: String, CaseIterable { case all = "All", live = "Live", paper = "Paper" }
    enum ViewMode: String, CaseIterable { case running = "Running", registry = "Registry" }

    @State private var viewMode: ViewMode = .running
    @State private var account = ""       // "" = all
    @State private var mode: Mode = .all
    @State private var search = ""
    @State private var selectedID: String?

    private var filtered: [Bot] {
        store.bots.filter { b in
            if mode == .live && !b.isLive { return false }
            if mode == .paper && b.isLive { return false }
            if !account.isEmpty && b.account != account { return false }
            if !search.isEmpty {
                let hay = "\(b.module ?? "") \(b.account ?? "") \(b.command ?? "")"
                    .lowercased()
                if !hay.contains(search.lowercased()) { return false }
            }
            return true
        }
    }

    private var selected: Bot? {
        filtered.first { $0.id == selectedID } ?? filtered.first
    }

    private var groups: [(module: String, bots: [Bot])] {
        Dictionary(grouping: filtered) { $0.module ?? "?" }
            .map { ($0.key, $0.value) }
            .sorted {
                let l0 = $0.bots.contains { $0.isLive }
                let l1 = $1.bots.contains { $0.isLive }
                return l0 != l1 ? l0 : $0.module < $1.module
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                Spacer()
            }
            .padding(.horizontal, 18).padding(.top, 14)

            switch viewMode {
            case .registry:
                RegistryPane()
            case .running:
                HStack(alignment: .top, spacing: 16) {
                    listPane.frame(width: 360)
                    if let bot = selected {
                        BotDetailPane(bot: bot).id(bot.id)
                            .frame(maxWidth: .infinity)
                    } else {
                        VStack {
                            Spacer()
                            Text("No bots match the filter.")
                                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(18)
            }
        }
    }

    // ---------------- list ----------------
    private var listPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Bots")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
                Chip(text: "\(store.bots.filter(\.isLive).count) LIVE", color: Theme.red)
                Chip(text: "\(store.bots.filter { !$0.isLive }.count) PAPER", color: Theme.blue)
                Spacer()
            }

            HStack(spacing: 8) {
                Picker("", selection: $account) {
                    Text("All accounts").tag("")
                    ForEach(store.accounts) { a in Text(a.name).tag(a.id) }
                }
                .labelsHidden()

                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
            }

            TextField("Search module / account / flag…", text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.module) { group in
                        Section {
                            ForEach(group.bots) { b in
                                botRow(b)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text(group.module)
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(Theme.muted).kerning(0.4)
                                Text("\(group.bots.count)")
                                    .font(.system(size: 10, weight: .bold)).monospacedDigit()
                                    .foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Theme.panel2)
                                    .clipShape(Capsule())
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .background(Theme.bg)
                        }
                    }
                }
            }
        }
        .card()
    }

    private func botRow(_ b: Bot) -> some View {
        let isSel = b.id == selected?.id
        return Button {
            selectedID = b.id
        } label: {
            HStack(spacing: 8) {
                Chip(text: b.isLive ? "LIVE" : "PAPER",
                     color: b.isLive ? Theme.red : Theme.blue)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Text(accountName(b.account))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        if let coin = b.params?["coin"]?.stringValue, !coin.isEmpty {
                            Text(coin).font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.yellow)
                        }
                    }
                    HStack(spacing: 4) {
                        Text("pid \(b.pid.map(String.init) ?? "?") ·")
                        TickingUptime(baseSecs: b.up_secs, fallback: b.etime)
                    }
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.muted.opacity(isSel ? 1 : 0.4))
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(isSel ? Theme.panel2 : .clear)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(isSel ? Theme.blue : .clear, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func accountName(_ id: String?) -> String {
        store.accounts.first { $0.id == id }?.name ?? id ?? "unmapped"
    }
}

// ================= detail pane =================
struct BotDetailPane: View {
    @EnvironmentObject var store: AppStore
    let bot: Bot

    @State private var hours: Double = 24
    @State private var series: [StratPoint] = []
    @State private var logTail = ""
    @State private var logName = ""
    @State private var showRegister = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                configCard
                graphCard
                logCard
            }
        }
        .task(id: hours) { await loadSeries() }
        .task { await loadLog() }
        .sheet(isPresented: $showRegister) {
            RegisterSheet(
                prefillAccount: bot.account,
                prefillStratKey: catalogKey,
                prefillParams: catalogStrat?.paramValues(fromFlags: bot.params ?? [:]))
                .environmentObject(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(bot.module ?? "?")
                    .font(.system(size: 19, weight: .heavy)).foregroundStyle(Theme.text)
                Chip(text: bot.isLive ? "LIVE" : "PAPER",
                     color: bot.isLive ? Theme.red : Theme.blue)
                if let sub = bot.sub { Chip(text: sub, color: Theme.muted) }
                Spacer()
                if catalogStrat != nil && bot.account != nil {
                    Button("Register this config") { showRegister = true }
                        .buttonStyle(PanelButton(small: true))
                        .help("Create a registry entry pinned to this account with these exact params")
                }
                if let key = catalogKey, bot.account != nil {
                    Button("Stop") {
                        Task { await store.stopStrat(account: bot.account!,
                                                     stratKey: key, kill: false) }
                    }
                    .buttonStyle(PanelButton(small: true))
                }
            }
            HStack(spacing: 6) {
                Text(accountName).foregroundStyle(Theme.blue)
                Text("· pid \(bot.pid.map(String.init) ?? "?") ·")
                TickingUptime(baseSecs: bot.up_secs, fallback: bot.etime)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.muted)
        }
        .card()
    }

    private var catalogStrat: Strat? {
        store.catalog.first { $0.module == bot.module }
    }
    private var catalogKey: String? { catalogStrat?.key }
    private var accountName: String {
        store.accounts.first { $0.id == bot.account }?.name ?? bot.account ?? "unmapped"
    }

    // ---------------- config ----------------
    private var configCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Configuration")
                .font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.text)
            let params = bot.orderedParams
            if params.isEmpty {
                Text("No flags parsed from the process.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)],
                          alignment: .leading, spacing: 8) {
                    ForEach(params, id: \.key) { key, value in
                        paramCell(key, value)
                    }
                }
            }
            if let cmd = bot.command, !cmd.isEmpty {
                Text(cmd)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Theme.codeBg)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        .card()
    }

    private func paramCell(_ key: String, _ value: JSONValue) -> some View {
        let isFlagOnly = value.boolValue && value.stringValue == "true"
        let highlight = key == "live"
        return VStack(alignment: .leading, spacing: 1) {
            Text(key.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Theme.muted).kerning(0.4)
                .lineLimit(1)
            Text(isFlagOnly ? "on" : value.stringValue)
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(highlight ? Theme.red : Theme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? Theme.red.opacity(0.10) : Theme.panel2.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(highlight ? Theme.red.opacity(0.5) : Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // ---------------- graph ----------------
    private var graphCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Instances over time")
                    .font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.text)
                Text("\(bot.module ?? "?") on \(accountName)")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                Spacer()
                RangeChips(hours: $hours, compact: true)
            }
            StratActivityChart(points: series, showLive: true, showPaper: true,
                               height: 140)
        }
        .card()
    }

    private func loadSeries() async {
        guard let module = bot.module else { return }
        var q = ["hours": String(hours), "module": module]
        if let a = bot.account { q["account"] = a }
        if let r: StratHistory = try? await store.api.get("/api/history/bots", query: q) {
            series = r.series
        }
    }

    // ---------------- log ----------------
    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Latest log")
                    .font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.text)
                if !logName.isEmpty {
                    Text(logName).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Button("Refresh") { Task { await loadLog() } }
                    .buttonStyle(PanelButton(small: true))
            }
            ScrollView {
                Text(logTail.isEmpty ? "No matching log file found." : logTail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.text.opacity(0.85))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 180)
            .background(Theme.codeBg)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .card()
    }

    private func loadLog() async {
        guard let account = bot.account, let module = bot.module else { return }
        guard let list: LogListPayload = try? await store.api.get(
            "/api/logs", query: ["account": account]) else { return }
        let match = (list.logs ?? []).first { $0.name.contains(module) }
        guard let match else { logTail = ""; return }
        logName = match.name
        if let r: LogListPayload = try? await store.api.get(
            "/api/logs", query: ["account": account, "name": match.name,
                                 "lines": "150"]) {
            logTail = r.tail ?? ""
        }
    }
}
