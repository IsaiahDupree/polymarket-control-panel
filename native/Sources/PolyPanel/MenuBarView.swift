import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var backend: BackendController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(backend.isUp ? .green : .red).frame(width: 8, height: 8)
                Text(backend.isUp ? "Backend running" : "Backend offline")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            if let bal = backend.totalBalance {
                Text(String(format: "$%.2f", bal))
                    .font(.system(size: 22, weight: .bold))
                HStack(spacing: 12) {
                    Label("\(backend.liveStrats) live", systemImage: "bolt.fill")
                        .foregroundStyle(backend.liveStrats > 0 ? .red : .secondary)
                    Label("\(backend.paperStrats) paper", systemImage: "doc.text")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11, weight: .semibold))
            }
            Divider()
            Button("Open dashboard") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            Button("Open in browser") { NSWorkspace.shared.open(backend.dashboardURL) }
            Button("Start backend") { backend.ensureRunning() }.disabled(backend.isUp)
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 230)
    }
}
