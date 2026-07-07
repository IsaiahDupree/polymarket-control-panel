import SwiftUI

// ---------------- Logs ----------------
struct LogsView: View {
    @EnvironmentObject var store: AppStore
    @State private var account = ""
    @State private var files: [LogFile] = []
    @State private var selectedFile = ""
    @State private var tail = "Select an account…"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Picker("", selection: $account) {
                    ForEach(store.accounts) { a in Text(a.name).tag(a.id) }
                }
                .labelsHidden()
                .frame(width: 180)

                Picker("", selection: $selectedFile) {
                    ForEach(files) { f in
                        Text("\(f.name) (\(f.size / 1024)k)").tag(f.name)
                    }
                }
                .labelsHidden()

                Button("Refresh") { Task { await loadTail() } }
                    .buttonStyle(PanelButton())
            }

            ScrollView {
                Text(tail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.text.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Theme.codeBg)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(18)
        .onAppear {
            if account.isEmpty { account = store.accounts.first?.id ?? "" }
        }
        .onChange(of: account) { Task { await loadFiles() } }
        .onChange(of: selectedFile) { Task { await loadTail() } }
        .task { await loadFiles() }
    }

    private func loadFiles() async {
        guard !account.isEmpty else { return }
        if let r: LogListPayload = try? await store.api.get(
            "/api/logs", query: ["account": account]) {
            files = r.logs ?? []
            if let first = files.first?.name { selectedFile = first }
            else { selectedFile = ""; tail = "(no log files)" }
        }
    }

    private func loadTail() async {
        guard !account.isEmpty, !selectedFile.isEmpty else { return }
        if let r: LogListPayload = try? await store.api.get(
            "/api/logs", query: ["account": account, "name": selectedFile,
                                 "lines": "300"]) {
            tail = (r.tail?.isEmpty == false) ? r.tail! : "(empty)"
        }
    }
}

// ---------------- Audit ----------------
struct AuditView: View {
    @EnvironmentObject var store: AppStore
    @State private var entries: [AuditEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Audit trail")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("every state-changing action")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button("Refresh") { Task { await load() } }
                    .buttonStyle(PanelButton(small: true))
            }
            if entries.isEmpty {
                Text("No audit entries yet.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(entries) { e in
                            HStack(alignment: .top, spacing: 12) {
                                ClickableTimestamp(ts: e.ts)
                                    .frame(width: 140, alignment: .leading)
                                Text(e.action ?? "")
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundStyle(Theme.text)
                                    .frame(width: 110, alignment: .leading)
                                Text(e.account ?? "")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.blue)
                                    .frame(width: 70, alignment: .leading)
                                Text(e.detailText)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(2)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            Divider().overlay(Theme.border.opacity(0.5))
                        }
                    }
                }
            }
        }
        .card()
        .padding(18)
        .task { await load() }
    }

    private func load() async {
        if let r: AuditPayload = try? await store.api.get(
            "/api/audit", query: ["n": "200"]) {
            entries = r.audit
        }
    }
}
