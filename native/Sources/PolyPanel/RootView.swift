import SwiftUI

enum Tab: String, CaseIterable, Equatable {
    case portfolio = "Portfolio"
    case bots = "Bots"
    case strategies = "Strategies"
    case markets = "Markets"
    case logs = "Logs"
    case audit = "Audit"
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab: Tab = .portfolio

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                topBar
                Divider().overlay(Theme.border)
                Group {
                    switch tab {
                    case .portfolio: PortfolioView()
                    case .bots: BotsView()
                    case .strategies: StrategiesView()
                    case .markets: MarketsView()
                    case .logs: LogsView()
                    case .audit: AuditView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            toastStack.padding(18)
        }
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onAppear { store.bootstrap() }
        .onChange(of: store.requestedTab) {
            if let t = store.requestedTab { tab = t; store.requestedTab = nil }
        }
    }

    private var topBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [Theme.blue, Color(hex: 0x7B61FF)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                    .overlay(Text("▲").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white))
                Text("Control Panel")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
            }

            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        Text(t.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tab == t ? Theme.text : Theme.muted)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(tab == t ? Theme.panel2 : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            statusPill(dotColor: (store.health?.proxy_on ?? false) ? Theme.green : Theme.red,
                       text: (store.health?.proxy_on ?? false)
                           ? "proxy \(store.health?.proxy_exit ?? "")" : "no proxy")
            statusPill(dotColor: store.backendUp ? Theme.green : Theme.red,
                       text: store.backendUp ? "backend" : "offline")
            Text(fmtUSD(store.totalBalance))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(Theme.panel)
    }

    private func statusPill(dotColor: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.panel2)
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .clipShape(Capsule())
    }

    private var toastStack: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(store.toasts) { t in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(t.kind == .error ? Theme.red :
                              t.kind == .ok ? Theme.green : Theme.blue)
                        .frame(width: 3)
                    Text(t.text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.text)
                        .lineLimit(3)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.panel2)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .frame(maxWidth: 380, alignment: .leading)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: store.toasts)
    }
}
