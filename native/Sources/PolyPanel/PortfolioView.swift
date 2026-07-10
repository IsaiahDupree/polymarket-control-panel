import SwiftUI

// Visual hierarchy (glanceable in <2s):
//   L1  portfolio value + period P&L (biggest, trend-colored)
//   L2  KPI strip (open P&L, $ in markets, live exposure) — clickable
//   L3  time-critical: open positions sorted by soonest resolution, countdowns
//   L4  strategy activity + per-account cards
//   L5  metadata (addresses, sources) — smallest, muted

struct PortfolioView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                PositionsPanel()
                HStack(alignment: .top, spacing: 16) {
                    ActivityCard().frame(maxWidth: .infinity)
                    activeNowCard.frame(width: 290)
                }
                accountGrid
            }
            .padding(18)
        }
    }

    // ---------------- L1 + L2: hero ----------------
    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PORTFOLIO VALUE")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Theme.muted).kerning(0.6)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(fmtUSD(store.totalBalance))
                            .font(.system(size: 36, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(Theme.text)
                        if let c = store.portfolioChange, c.has_data {
                            ChangeBadge(delta: c.delta, pct: c.pct)
                        }
                    }
                }
                Spacer()
                RangeChips(hours: $store.hours)
            }

            // L2: KPI strip — every chip is a shortcut
            HStack(spacing: 10) {
                kpi("OPEN P&L", fmtSigned(store.openPnlTotal),
                    color: store.openPnlTotal >= 0 ? Theme.green : Theme.red)
                kpi("IN MARKETS", fmtUSD(store.inMarketsTotal))
                kpi("OPEN ORDERS", "\(store.openOrdersCount)")
                kpi("LIVE STRATS", "\(store.liveCount)",
                    color: store.liveCount > 0 ? Theme.red : Theme.text) {
                    store.requestedTab = .strategies
                }
                kpi("PAPER STRATS", "\(store.paperCount)") {
                    store.requestedTab = .bots
                }
                Spacer()
            }

            BalanceChart(points: store.portfolio)
        }
        .card()
    }

    private func kpi(_ label: String, _ value: String,
                     color: Color = Theme.text,
                     action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.muted).kerning(0.5)
                Text(value)
                    .font(.system(size: 15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Theme.panel2.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    // ---------------- active now ----------------
    private var activeNowCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active now")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
            let items = store.accounts.flatMap { a in a.strats.map { (a, $0) } }
                .sorted { ($0.1.live ?? false) && !($1.1.live ?? false) }
            if items.isEmpty {
                Text("Nothing running.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items.prefix(40), id: \.1.id) { acct, s in
                            HStack(spacing: 8) {
                                Chip(text: (s.live ?? false) ? "LIVE" : "PAPER",
                                     color: (s.live ?? false) ? Theme.red : Theme.blue)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(s.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                    HStack(spacing: 4) {
                                        Text(acct.name).foregroundStyle(Theme.muted)
                                        Text("·").foregroundStyle(Theme.muted)
                                        TickingUptime(baseSecs: s.up_secs, fallback: s.etime)
                                            .foregroundStyle(Theme.muted)
                                    }
                                    .font(.system(size: 10.5))
                                }
                                Spacer()
                            }
                            .padding(.vertical, 5)
                            Divider().overlay(Theme.border.opacity(0.5))
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .card()
    }

    // ---------------- account cards ----------------
    private var accountGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)],
                  spacing: 16) {
            ForEach(store.accounts) { a in
                AccountCard(account: a)
            }
        }
    }
}

func fmtSigned(_ v: Double) -> String {
    (v >= 0 ? "+" : "−") + fmtUSD(abs(v))
}

// =============== L3: positions with countdowns ===============
struct PositionsPanel: View {
    @EnvironmentObject var store: AppStore
    @State private var expanded = false

    var body: some View {
        let rows = store.positionsByUrgency
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Open positions")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
                Chip(text: "\(rows.count)", color: Theme.blue)
                Text("sorted by resolution time")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                Spacer()
                if rows.count > 6 {
                    Button(expanded ? "Show less" : "Show all \(rows.count)") {
                        expanded.toggle()
                    }
                    .buttonStyle(PanelButton(small: true))
                }
            }
            if rows.isEmpty {
                Text("No open positions.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array((expanded ? rows : Array(rows.prefix(6))).enumerated()),
                            id: \.offset) { _, item in
                        PositionRow(account: item.account, position: item.position)
                        Divider().overlay(Theme.border.opacity(0.5))
                    }
                }
            }
        }
        .card()
    }
}

struct PositionRow: View {
    @EnvironmentObject var store: AppStore
    let account: String
    let position: Position

    private var accountName: String {
        store.accounts.first { $0.id == account }?.name ?? account
    }
    private var outcomeColor: Color {
        switch (position.outcome ?? "").lowercased() {
        case "up", "yes": return Theme.green
        case "down", "no": return Theme.red
        default: return Theme.blue
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if position.redeemable == true {
                    Chip(text: "REDEEM", color: Theme.yellow)
                } else {
                    CountdownChip(end: position.end)
                }
            }
            .frame(width: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(position.title ?? position.slug ?? "?")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(accountName)
                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let o = position.outcome {
                Chip(text: o.uppercased(), color: outcomeColor)
            }

            // size @ avg → cur
            if let size = position.size {
                HStack(spacing: 3) {
                    Text(String(format: "%.0f", size))
                        .foregroundStyle(Theme.text)
                    if let avg = position.avgPrice {
                        Text("@ \(String(format: "%.2f", avg))")
                            .foregroundStyle(Theme.muted)
                    }
                    if let cur = position.curPrice {
                        Text("→ \(String(format: "%.2f", cur))")
                            .foregroundStyle(outcomeColor)
                    }
                }
                .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                .frame(width: 130, alignment: .trailing)
            }

            Text(fmtUSD(position.currentValue))
                .font(.system(size: 12.5, weight: .bold)).monospacedDigit()
                .foregroundStyle(Theme.text)
                .frame(width: 72, alignment: .trailing)

            if let pnl = position.cashPnl {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(fmtSigned(pnl))
                        .font(.system(size: 12, weight: .bold)).monospacedDigit()
                    if let pct = position.percentPnl {
                        Text("\(String(format: "%+.1f", pct))%")
                            .font(.system(size: 9.5)).monospacedDigit()
                    }
                }
                .foregroundStyle(pnl >= 0 ? Theme.green : Theme.red)
                .frame(width: 76, alignment: .trailing)
            }
        }
        .padding(.vertical, 6)
    }
}

// =============== L4: strategy activity (own clock) ===============
struct ActivityCard: View {
    @EnvironmentObject var store: AppStore
    @State private var hours: Double = 24
    @State private var account = ""          // "" = all accounts
    @State private var showLive = true
    @State private var showPaper = true
    @State private var series: [StratPoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Strategy activity")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)

                // clickable legend = series toggles
                legendChip("LIVE", color: Theme.red, on: $showLive)
                legendChip("PAPER", color: Theme.blue, on: $showPaper)

                Picker("", selection: $account) {
                    Text("All accounts").tag("")
                    ForEach(store.accounts) { a in Text(a.name).tag(a.id) }
                }
                .labelsHidden()
                .frame(width: 150)

                Spacer()
                RangeChips(hours: $hours, compact: true)
            }
            StratActivityChart(points: series, showLive: showLive, showPaper: showPaper)
        }
        .card()
        .task(id: "\(account)|\(hours)") { await load() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            Task { await load() }
        }
    }

    private func legendChip(_ text: String, color: Color, on: Binding<Bool>) -> some View {
        Button {
            on.wrappedValue.toggle()
        } label: {
            Chip(text: text, color: on.wrappedValue ? color : Theme.muted)
                .opacity(on.wrappedValue ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .help("Click to toggle this series")
    }

    private func load() async {
        var q = ["hours": String(hours)]
        if !account.isEmpty { q["account"] = account }
        if let r: StratHistory = try? await store.api.get("/api/history/strats", query: q) {
            series = r.series
        }
    }
}

// =============== account cards + detail sheet ===============
struct AccountCard: View {
    @EnvironmentObject var store: AppStore
    let account: Account
    @State private var confirmKill = false
    @State private var showDetail = false

    private var avatarColor: Color {
        let palette: [Color] = [Theme.blue, Color(hex: 0x7B61FF), Theme.green,
                                Color(hex: 0xF2994A), Theme.red, Color(hex: 0x56CCF2)]
        let sum = account.id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Circle().fill(avatarColor)
                    .frame(width: 32, height: 32)
                    .overlay(Text(account.name.prefix(2).uppercased())
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 0) {
                    Text(account.name)
                        .font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.text)
                    Text(account.shortAddr)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if let c = store.sparkChanges[account.id], c.has_data {
                    ChangeBadge(delta: c.delta, pct: c.pct)
                }
            }

            if let bal = account.balance_usd {
                Text(fmtUSD(bal))
                    .font(.system(size: 23, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(Theme.text)
            } else {
                Text(account.error ?? account.balance_error ?? "no data")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }

            HStack(spacing: 14) {
                stat("\(account.positions_n ?? 0)", "positions")
                stat("\(account.open_orders_n ?? 0)", "orders")
                if let pv = account.positions_value, pv > 0 {
                    stat(fmtUSD(pv), "in mkts")
                }
            }

            HStack(spacing: 5) {
                ForEach(account.liveStrats.prefix(3)) { s in
                    Chip(text: "LIVE \(s.strat_key ?? s.module ?? "?")", color: Theme.red)
                }
                if account.paperStrats.count > 0 {
                    Chip(text: "\(account.paperStrats.count) paper", color: Theme.blue)
                }
                if account.strats.isEmpty { Chip(text: "idle", color: Theme.muted) }
            }

            // clickable sparkline -> full account detail with its own clock
            Button {
                showDetail = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Sparkline(points: store.sparks[account.id] ?? [])
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.muted.opacity(0.7))
                        .padding(3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open full chart & history")

            Button {
                confirmKill = true
            } label: {
                Text("Kill switch")
                    .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(Theme.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Kill switch: \(account.name)",
                                isPresented: $confirmKill, titleVisibility: .visible) {
                Button("Cancel ALL orders + stop ALL strategies", role: .destructive) {
                    Task { await store.killSwitch(account: account.id) }
                }
            } message: {
                Text("This cancels real open orders and stops every strategy on this account.")
            }
        }
        .card()
        .sheet(isPresented: $showDetail) {
            AccountDetailSheet(account: account).environmentObject(store)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(Theme.text)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
        }
    }
}

/// Per-account deep dive: full balance chart, live/paper activity (paper
/// graphs for every account live here), and that account's positions —
/// each with its own clickable time range.
struct AccountDetailSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let account: Account

    @State private var hours: Double = 24
    @State private var balSeries: [HistoryPoint] = []
    @State private var balChange: Change?
    @State private var actSeries: [StratPoint] = []
    @State private var showLive = true
    @State private var showPaper = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.text)
                        Text(account.funder ?? "")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(fmtUSD(account.balance_usd))
                            .font(.system(size: 26, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(Theme.text)
                        if let c = balChange, c.has_data {
                            ChangeBadge(delta: c.delta, pct: c.pct)
                        }
                    }
                    Button("Done") { dismiss() }.buttonStyle(PanelButton())
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Balance").font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        RangeChips(hours: $hours, compact: true)
                    }
                    BalanceChart(points: balSeries, height: 210)
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Strategy activity").font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Button { showLive.toggle() } label: {
                            Chip(text: "LIVE", color: showLive ? Theme.red : Theme.muted)
                                .opacity(showLive ? 1 : 0.55)
                        }.buttonStyle(.plain)
                        Button { showPaper.toggle() } label: {
                            Chip(text: "PAPER", color: showPaper ? Theme.blue : Theme.muted)
                                .opacity(showPaper ? 1 : 0.55)
                        }.buttonStyle(.plain)
                        Spacer()
                    }
                    StratActivityChart(points: actSeries, showLive: showLive,
                                       showPaper: showPaper, height: 130)
                }
                .card()

                let pos = store.positions[account.id] ?? []
                if !pos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Positions (\(pos.count))")
                            .font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.text)
                        VStack(spacing: 0) {
                            ForEach(pos) { p in
                                PositionRow(account: account.id, position: p)
                                Divider().overlay(Theme.border.opacity(0.5))
                            }
                        }
                    }
                    .card()
                }
            }
            .padding(18)
        }
        .frame(width: 720, height: 620)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .task(id: hours) { await load() }
    }

    private func load() async {
        let h = String(hours)
        if let r: BalanceHistory = try? await store.api.get(
            "/api/history/balances", query: ["account": account.id, "hours": h]) {
            balSeries = r.series
            balChange = r.change
        }
        if let r: StratHistory = try? await store.api.get(
            "/api/history/strats", query: ["account": account.id, "hours": h]) {
            actSeries = r.series
        }
    }
}
