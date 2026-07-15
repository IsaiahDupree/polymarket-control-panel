import SwiftUI

/// The bot registry: named bot→account bindings with one-click off/paper/LIVE,
/// drift + account-verification badges, and warnings for unregistered or
/// unattributable running bots.
struct RegistryPane: View {
    @EnvironmentObject var store: AppStore
    @State private var showRegister = false

    private var data: RegistryPayload? { store.registryData }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let regs = data?.registrations, !regs.isEmpty {
                    ForEach(regs) { reg in
                        RegistrationRow(reg: reg)
                    }
                } else {
                    VStack(spacing: 6) {
                        Text("No bots registered yet.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        Text("Register a bot to pin it to an account and control it with one click — or open a running bot in the Running view and register its exact config.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.muted.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
                if let orphans = data?.orphans, !orphans.isEmpty {
                    orphanCard(orphans)
                }
                if let unmapped = data?.unmapped, !unmapped.isEmpty {
                    unmappedCard(unmapped)
                }
            }
            .padding(18)
        }
        .sheet(isPresented: $showRegister) {
            RegisterSheet().environmentObject(store)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Registered bots")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
            if let d = data {
                Chip(text: "\(d.registrations.count)", color: Theme.blue)
                if !d.orphans.isEmpty {
                    Chip(text: "\(d.orphans.count) unregistered", color: Theme.yellow)
                }
                if !d.unmapped.isEmpty {
                    Chip(text: "\(d.unmapped.count) UNMAPPED", color: Theme.red)
                }
            }
            Spacer()
            Button("＋ Register bot") { showRegister = true }
                .buttonStyle(PanelButton(prominent: true))
        }
    }

    private func orphanCard(_ orphans: [RegInstance]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(Theme.yellow)
                Text("Running but not registered")
                    .font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.text)
                Text("attributed to an account, but nobody owns them here")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            }
            ForEach(orphans) { p in
                instanceLine(p)
            }
            Text("Tip: open one in the Running view and use “Register this config”.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
        }
        .card()
    }

    private func unmappedCard(_ unmapped: [RegInstance]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.red)
                Text("Unmapped processes")
                    .font(.system(size: 13.5, weight: .bold)).foregroundStyle(Theme.red)
                Text("state dir maps to NO configured account — verify these")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            }
            ForEach(unmapped) { p in
                instanceLine(p)
            }
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Theme.red.opacity(0.5), lineWidth: 1))
    }

    private func instanceLine(_ p: RegInstance) -> some View {
        HStack(spacing: 8) {
            Chip(text: (p.live ?? false) ? "LIVE" : "PAPER",
                 color: (p.live ?? false) ? Theme.red : Theme.blue)
            Text(p.module ?? "?")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
            Text(p.account ?? "—")
                .font(.system(size: 11)).foregroundStyle(Theme.blue)
            Text("pid \(p.pid.map(String.init) ?? "?") ·")
                .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            TickingUptime(baseSecs: p.up_secs, fallback: p.etime)
                .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// ================= one registration =================
struct RegistrationRow: View {
    @EnvironmentObject var store: AppStore
    let reg: Registration
    @State private var confirmLive = false
    @State private var confirmUnregister = false

    private var statusColor: Color {
        switch reg.actualStatus {
        case "live": return Theme.red
        case "paper": return Theme.blue
        default: return Theme.muted
        }
    }
    private var stratLabel: String {
        store.catalog.first { $0.key == reg.strat }?.label ?? reg.strat
    }
    private var accountName: String {
        store.accounts.first { $0.id == reg.account }?.name ?? reg.account
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text(reg.name)
                    .font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.text)
                Chip(text: reg.actualStatus.uppercased(), color: statusColor)
                if reg.drift == true {
                    Label("drift: wanted \(reg.desired)", systemImage: "exclamationmark.arrow.circlepath")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Theme.yellow)
                        .help("Actual state differs from desired — someone changed it outside the registry")
                }
                if reg.account_verified == true {
                    Label("account verified", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Theme.green)
                        .help("Every running instance's state dir maps back to \(accountName)")
                }
                Spacer()
                Button("Unregister") {
                    if reg.actualStatus == "off" {
                        Task { await store.unregisterBot(reg) }
                    } else {
                        confirmUnregister = true
                    }
                }
                .buttonStyle(PanelButton(destructive: true, small: true))
                .confirmationDialog("Unregister \(reg.name)?",
                                    isPresented: $confirmUnregister,
                                    titleVisibility: .visible) {
                    Button("Kill running bot and unregister", role: .destructive) {
                        Task { await store.unregisterBot(reg) }
                    }
                } message: {
                    Text("This bot is currently \(reg.actualStatus). Unregistering will SIGTERM it first.")
                }
            }

            HStack(spacing: 6) {
                Text(stratLabel).foregroundStyle(Theme.text)
                Text("on").foregroundStyle(Theme.muted)
                Text(accountName).foregroundStyle(Theme.blue)
                if let inst = reg.instances, !inst.isEmpty {
                    Text("·").foregroundStyle(Theme.muted)
                    TickingUptime(baseSecs: inst[0].up_secs, fallback: inst[0].etime)
                        .foregroundStyle(Theme.muted)
                    Text("· pid \(inst[0].pid.map(String.init) ?? "?")")
                        .foregroundStyle(Theme.muted)
                }
            }
            .font(.system(size: 12, weight: .semibold))

            if let params = reg.params, !params.isEmpty {
                HStack(spacing: 5) {
                    ForEach(params.sorted { $0.key < $1.key }.prefix(6), id: \.key) { k, v in
                        Chip(text: "\(k)=\(v.stringValue)", color: Theme.muted)
                    }
                    if params.count > 6 {
                        Text("+\(params.count - 6) more")
                            .font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }
            }

            // one-click state control
            HStack(spacing: 6) {
                stateButton("Off", target: "off", color: Theme.muted)
                stateButton("Paper", target: "paper", color: Theme.blue)
                Button {
                    confirmLive = true
                } label: {
                    stateLabel("LIVE", active: reg.actualStatus == "live", color: Theme.red)
                }
                .buttonStyle(.plain)
                .confirmationDialog("Put \(reg.name) LIVE?",
                                    isPresented: $confirmLive,
                                    titleVisibility: .visible) {
                    Button("Trade REAL MONEY on \(accountName)", role: .destructive) {
                        Task { await store.setRegistrationState(reg, desired: "live") }
                    }
                } message: {
                    Text("\(stratLabel) will place real orders. Any running paper instance is killed and replaced.")
                }
                Spacer()
            }
        }
        .card()
    }

    private func stateButton(_ label: String, target: String, color: Color) -> some View {
        Button {
            Task { await store.setRegistrationState(reg, desired: target) }
        } label: {
            stateLabel(label, active: reg.actualStatus == target, color: color)
        }
        .buttonStyle(.plain)
    }

    private func stateLabel(_ label: String, active: Bool, color: Color) -> some View {
        Text(label)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(active ? .white : color)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(active ? color : color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// ================= register sheet =================
struct RegisterSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    // optional prefill (from a running bot's parsed config)
    var prefillAccount: String?
    var prefillStratKey: String?
    var prefillParams: [String: JSONValue]?

    @State private var name = ""
    @State private var account = ""
    @State private var stratKey = ""
    @State private var textValues: [String: String] = [:]
    @State private var boolValues: [String: Bool] = [:]

    private var strat: Strat? { store.catalog.first { $0.key == stratKey } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Register bot")
                .font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.text)
            Text("Binds this strategy + config to one account. Nothing starts until you flip it to Paper or LIVE.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.muted)

            HStack(spacing: 10) {
                field("NAME (optional)") {
                    TextField("\(stratKey.isEmpty ? "strat" : stratKey)@\(account)", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                field("ACCOUNT") {
                    Picker("", selection: $account) {
                        ForEach(store.accounts) { a in Text(a.name).tag(a.id) }
                    }.labelsHidden()
                }
                field("STRATEGY") {
                    Picker("", selection: $stratKey) {
                        ForEach(store.catalog) { s in Text(s.label).tag(s.key) }
                    }.labelsHidden()
                }
            }

            if let s = strat {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    ForEach(s.params, id: \.name) { p in
                        field(p.name.uppercased(), help: p.help) {
                            paramControl(p)
                        }
                    }
                }
                .id(s.key)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PanelButton())
                Button("Register") {
                    Task {
                        if await store.registerBot(name: name, account: account,
                                                   strat: stratKey, params: gather()) {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(PanelButton(prominent: true))
                .disabled(account.isEmpty || stratKey.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onAppear { seed() }
        .onChange(of: stratKey) { seedParams() }
    }

    private func seed() {
        account = prefillAccount ?? store.accounts.first?.id ?? ""
        stratKey = prefillStratKey ?? store.catalog.first?.key ?? ""
        seedParams()
    }

    private func seedParams() {
        guard let s = strat else { return }
        textValues = [:]; boolValues = [:]
        for p in s.params {
            let pre = prefillStratKey == s.key ? prefillParams?[p.name] : nil
            if p.type == "bool" {
                boolValues[p.name] = pre?.boolValue ?? p.def.boolValue
            } else {
                textValues[p.name] = pre?.stringValue ?? p.def.stringValue
            }
        }
    }

    @ViewBuilder
    private func paramControl(_ p: StratParam) -> some View {
        switch p.type {
        case "bool":
            Toggle("", isOn: Binding(get: { boolValues[p.name] ?? false },
                                     set: { boolValues[p.name] = $0 }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
        case "choice":
            Picker("", selection: Binding(get: { textValues[p.name] ?? p.def.stringValue },
                                          set: { textValues[p.name] = $0 })) {
                ForEach(p.choices, id: \.self) { Text($0).tag($0) }
            }.labelsHidden()
        default:
            TextField("", text: Binding(get: { textValues[p.name] ?? "" },
                                        set: { textValues[p.name] = $0 }))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func gather() -> [String: Any] {
        var out: [String: Any] = [:]
        guard let s = strat else { return out }
        for p in s.params {
            if p.type == "bool" { out[p.name] = boolValues[p.name] ?? false }
            else { out[p.name] = textValues[p.name] ?? "" }
        }
        return out
    }

    private func field<C: View>(_ label: String, help: String = "",
                                @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Theme.muted).kerning(0.4)
                if !help.isEmpty {
                    Text("— \(help)").font(.system(size: 9.5))
                        .foregroundStyle(Theme.muted.opacity(0.7)).lineLimit(1)
                }
            }
            content()
        }
    }
}
