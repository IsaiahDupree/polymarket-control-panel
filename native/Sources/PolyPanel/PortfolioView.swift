import SwiftUI

struct PortfolioView: View {
    @EnvironmentObject var store: AppStore

    private let ranges: [(String, Double)] = [
        ("1H", 1), ("6H", 6), ("1D", 24), ("1W", 168), ("1M", 720), ("ALL", 87600)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hero
                HStack(alignment: .top, spacing: 16) {
                    activityCard.frame(maxWidth: .infinity)
                    activeNowCard.frame(width: 300)
                }
                accountGrid
            }
            .padding(18)
        }
    }

    // ---------------- hero ----------------
    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PORTFOLIO VALUE")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .kerning(0.6)
                    Text(fmtUSD(store.totalBalance))
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(Theme.text)
                }
                if let c = store.portfolioChange, c.has_data {
                    ChangeBadge(delta: c.delta, pct: c.pct)
                        .padding(.bottom, 5)
                }
                Spacer()
                rangePicker
            }
            BalanceChart(points: store.portfolio)
        }
        .card()
    }

    private var rangePicker: some View {
        HStack(spacing: 3) {
            ForEach(ranges, id: \.0) { label, h in
                Button {
                    store.hours = h
                } label: {
                    Text(label)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(store.hours == h ? Theme.blue : Theme.muted)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(store.hours == h ? Theme.panel2 : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ---------------- strat activity ----------------
    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Running strategies")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.text)
                Chip(text: "LIVE", color: Theme.red)
                Chip(text: "PAPER", color: Theme.blue)
            }
            StratActivityChart(points: store.stratActivity)
        }
        .card()
    }

    private var activeNowCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active now")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.text)
            let items = store.accounts.flatMap { a in
                a.strats.map { (a, $0) }
            }
            if items.isEmpty {
                Text("Nothing running.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items.prefix(30), id: \.1.id) { acct, s in
                            HStack(spacing: 8) {
                                Chip(text: (s.live ?? false) ? "LIVE" : "PAPER",
                                     color: (s.live ?? false) ? Theme.red : Theme.blue)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(s.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.text)
                                    Text("\(acct.name) · up \(s.etime ?? "?")")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Theme.muted)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 5)
                            Divider().overlay(Theme.border.opacity(0.5))
                        }
                    }
                }
                .frame(maxHeight: 170)
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

struct AccountCard: View {
    @EnvironmentObject var store: AppStore
    let account: Account
    @State private var confirmKill = false

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
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 0) {
                    Text(account.name)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Theme.text)
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
                    .font(.system(size: 23, weight: .heavy))
                    .foregroundStyle(Theme.text)
            } else {
                Text(account.error ?? account.balance_error ?? "no data")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
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
                if account.strats.isEmpty {
                    Chip(text: "idle", color: Theme.muted)
                }
            }

            Sparkline(points: store.sparks[account.id] ?? [])

            Button {
                confirmKill = true
            } label: {
                Text("Kill switch")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "Kill switch: \(account.name)",
                isPresented: $confirmKill, titleVisibility: .visible
            ) {
                Button("Cancel ALL orders + stop ALL strategies", role: .destructive) {
                    Task { await store.killSwitch(account: account.id) }
                }
            } message: {
                Text("This cancels real open orders and stops every strategy on this account.")
            }
        }
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(label).font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
        }
    }
}
