import SwiftUI

struct StrategiesView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedKey: String?

    private var selected: Strat? {
        store.catalog.first { $0.key == selectedKey } ?? store.catalog.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            catalogList.frame(width: 320)
            VStack(spacing: 16) {
                if let s = selected {
                    StratConfigCard(strat: s).id(s.key)  // .id -> re-init form state
                }
                RunningCard()
            }
        }
        .padding(18)
    }

    private var catalogList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                Text("Catalog")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.text)
                if !store.stratsEnabled {
                    Text("Launching disabled on this backend (read-only). Set EDGEOS_REPO / EDGEOS_PYBIN.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.yellow)
                }
                ForEach(store.catalog) { s in
                    let sel = s.key == (selected?.key ?? "")
                    Button {
                        selectedKey = s.key
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.label)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.text)
                            Text(s.desc)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.muted)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(sel ? Theme.panel2 : Theme.panel)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(sel ? Theme.blue : Theme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// ---------------- config form ----------------
struct StratConfigCard: View {
    @EnvironmentObject var store: AppStore
    let strat: Strat

    @State private var account = ""
    @State private var live = false
    @State private var textValues: [String: String] = [:]
    @State private var boolValues: [String: Bool] = [:]
    @State private var preview: String?
    @State private var confirmLive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configure — \(strat.label)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)

            HStack(spacing: 12) {
                field("ACCOUNT") {
                    Picker("", selection: $account) {
                        ForEach(store.accounts) { a in
                            Text(a.name).tag(a.id)
                        }
                    }
                    .labelsHidden()
                }
                field("MODE") {
                    Picker("", selection: $live) {
                        Text("Paper").tag(false)
                        Text("LIVE (real money)").tag(true)
                    }
                    .labelsHidden()
                }
            }

            paramsGrid

            HStack(spacing: 9) {
                Button("Preview command") {
                    Task { preview = await store.previewStart(
                        account: account, strat: strat.key,
                        params: gatherParams(), live: live) }
                }
                .buttonStyle(PanelButton())

                Button(live ? "Start LIVE" : "Start paper") {
                    if live { confirmLive = true }
                    else { Task { await store.startStrat(
                        account: account, strat: strat.key,
                        params: gatherParams(), live: false) } }
                }
                .buttonStyle(PanelButton(prominent: true, destructive: live))
                .disabled(!store.stratsEnabled)
                .confirmationDialog("Start LIVE strategy",
                                    isPresented: $confirmLive,
                                    titleVisibility: .visible) {
                    Button("Trade REAL MONEY on \(account)", role: .destructive) {
                        Task { await store.startStrat(
                            account: account, strat: strat.key,
                            params: gatherParams(), live: true) }
                    }
                } message: {
                    Text("\(strat.label) will place real orders on \"\(account)\".")
                }
            }

            if let preview {
                Text(preview)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x9FD4A8))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.codeBg)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .card()
        .onAppear {
            if account.isEmpty { account = store.accounts.first?.id ?? "" }
            for p in strat.params {
                if p.type == "bool" { boolValues[p.name] = p.def.boolValue }
                else { textValues[p.name] = p.def.stringValue }
            }
        }
    }

    private var paramsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 185), spacing: 11)],
                  alignment: .leading, spacing: 11) {
            ForEach(strat.params, id: \.name) { p in
                field(p.name.uppercased(), help: p.help) {
                    switch p.type {
                    case "bool":
                        Toggle("", isOn: Binding(
                            get: { boolValues[p.name] ?? false },
                            set: { boolValues[p.name] = $0 }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    case "choice":
                        Picker("", selection: Binding(
                            get: { textValues[p.name] ?? p.def.stringValue },
                            set: { textValues[p.name] = $0 })) {
                            ForEach(p.choices, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    default:
                        TextField("", text: Binding(
                            get: { textValues[p.name] ?? "" },
                            set: { textValues[p.name] = $0 }))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    private func field<C: View>(_ label: String, help: String = "",
                                @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .kerning(0.4)
                if !help.isEmpty {
                    Text("— \(help)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted.opacity(0.7))
                        .lineLimit(1)
                }
            }
            content()
        }
    }

    private func gatherParams() -> [String: Any] {
        var out: [String: Any] = [:]
        for p in strat.params {
            if p.type == "bool" { out[p.name] = boolValues[p.name] ?? false }
            else { out[p.name] = textValues[p.name] ?? p.def.stringValue }
        }
        return out
    }
}

// ---------------- running table ----------------
struct RunningCard: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Running")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.text)
            let rows = store.running.flatMap { acct, list in
                list.map { (acct, $0) }
            }
            if rows.isEmpty {
                Text("Nothing running.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.muted)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.1.id) { acct, s in
                            RunningRow(account: acct, strat: s)
                            Divider().overlay(Theme.border.opacity(0.5))
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .card()
    }
}

struct RunningRow: View {
    @EnvironmentObject var store: AppStore
    let account: String
    let strat: RunningStrat
    @State private var confirmKill = false

    var body: some View {
        HStack(spacing: 10) {
            Chip(text: (strat.live ?? false) ? "LIVE" : "PAPER",
                 color: (strat.live ?? false) ? Theme.red : Theme.blue)
            VStack(alignment: .leading, spacing: 0) {
                Text(strat.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text("\(account) · pid \(strat.pid.map(String.init) ?? "?") · up \(strat.etime ?? "?")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if strat.strat_key != nil {
                Button("Stop") {
                    Task { await store.stopStrat(account: account,
                                                 stratKey: strat.strat_key!, kill: false) }
                }
                .buttonStyle(PanelButton(small: true))
                Button("Kill") { confirmKill = true }
                    .buttonStyle(PanelButton(destructive: true, small: true))
                    .confirmationDialog("Kill \(strat.displayName) on \(account)?",
                                        isPresented: $confirmKill,
                                        titleVisibility: .visible) {
                        Button("SIGTERM the process", role: .destructive) {
                            Task { await store.stopStrat(account: account,
                                                         stratKey: strat.strat_key!, kill: true) }
                        }
                    }
            }
        }
        .padding(.vertical, 7)
    }
}

// ---------------- shared button style ----------------
struct PanelButton: ButtonStyle {
    var prominent = false
    var destructive = false
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        let bg: Color = destructive && prominent ? Theme.red
            : prominent ? Theme.blue
            : destructive ? Theme.red.opacity(0.12)
            : Theme.panel2
        let fg: Color = prominent ? .white
            : destructive ? Theme.red
            : Theme.text
        configuration.label
            .font(.system(size: small ? 11.5 : 12.5, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, small ? 10 : 15)
            .padding(.vertical, small ? 5 : 8)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(prominent ? .clear : Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
