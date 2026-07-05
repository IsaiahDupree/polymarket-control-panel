import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(store.backendUp ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(store.backendUp ? "Backend running" : "Backend offline")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }

            if let bal = store.totalBalance {
                Text(fmtUSD(bal))
                    .font(.system(size: 22, weight: .bold))
                if let c = store.portfolioChange, c.has_data {
                    ChangeBadge(delta: c.delta, pct: c.pct)
                }
                HStack(spacing: 12) {
                    Label("\(store.liveCount) live", systemImage: "bolt.fill")
                        .foregroundStyle(store.liveCount > 0 ? .red : .secondary)
                    Label("\(store.paperCount) paper", systemImage: "doc.text")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11, weight: .semibold))

                Sparkline(points: store.portfolio, height: 40)
            }

            Divider()
            Button("Open panel") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Open web dashboard") {
                NSWorkspace.shared.open(store.api.base)
            }
            Button("Start backend") { store.ensureBackendRunning() }
                .disabled(store.backendUp)
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 250)
        .onAppear { store.bootstrap() }
    }
}
