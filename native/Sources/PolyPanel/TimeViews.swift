import SwiftUI

// Every time-based element in the app is live (ticks with store.now) and
// clickable (toggles format / changes range). These are the shared pieces.

/// "2d 4h" / "3h 12m" / "4m 32s" / "58s"
func fmtDuration(_ secs: Double) -> String {
    let s = max(0, Int(secs))
    if s >= 86400 { return "\(s / 86400)d \((s % 86400) / 3600)h" }
    if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
    if s >= 60 { return "\(s / 60)m \(s % 60)s" }
    return "\(s)s"
}

/// Shared clickable range selector used by every chart.
struct RangeChips: View {
    @Binding var hours: Double
    var compact = false

    static let ranges: [(String, Double)] = [
        ("1H", 1), ("6H", 6), ("1D", 24), ("1W", 168), ("1M", 720), ("ALL", 87600)
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.ranges, id: \.0) { label, h in
                Button {
                    hours = h
                } label: {
                    Text(label)
                        .font(.system(size: compact ? 10 : 11.5, weight: .bold))
                        .foregroundStyle(hours == h ? Theme.blue : Theme.muted)
                        .padding(.horizontal, compact ? 8 : 11)
                        .padding(.vertical, compact ? 3.5 : 5)
                        .background(hours == h ? Theme.panel2 : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Countdown to a market's resolution. Ticks every second; escalates color as
/// time runs out (muted → yellow < 5m → red < 1m). Click toggles to the
/// absolute end time.
struct CountdownChip: View {
    @EnvironmentObject var store: AppStore
    let end: Date?
    @State private var showAbsolute = false

    var body: some View {
        Button {
            showAbsolute.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "timer").font(.system(size: 9, weight: .bold))
                Text(text).monospacedDigit()
            }
            .font(.system(size: 10.5, weight: .bold))
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .foregroundStyle(color)
            .background(color.opacity(0.13))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(end.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "no end time")
    }

    private var remaining: Double? { end.map { $0.timeIntervalSince(store.now) } }

    private var text: String {
        guard let end else { return "—" }
        if showAbsolute {
            return end.formatted(date: .omitted, time: .shortened)
        }
        guard let r = remaining else { return "—" }
        return r <= 0 ? "resolving" : fmtDuration(r)
    }

    private var color: Color {
        guard let r = remaining else { return Theme.muted }
        if r <= 0 { return Theme.blue }
        if r < 60 { return Theme.red }
        if r < 300 { return Theme.yellow }
        return Theme.muted
    }
}

/// Live-ticking process uptime: server-reported seconds + elapsed since fetch.
struct TickingUptime: View {
    @EnvironmentObject var store: AppStore
    let baseSecs: Double?
    let fallback: String?

    var body: some View {
        Text("up \(text)")
            .monospacedDigit()
    }

    private var text: String {
        guard let baseSecs else { return fallback ?? "?" }
        return fmtDuration(baseSecs + store.now.timeIntervalSince(store.fetchedAt))
    }
}

/// Epoch timestamp that renders relative ("3m ago", ticking) and toggles to
/// absolute on click.
struct ClickableTimestamp: View {
    @EnvironmentObject var store: AppStore
    let ts: Double
    @State private var absolute = false

    var body: some View {
        Button {
            absolute.toggle()
        } label: {
            Text(text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .monospacedDigit()
        }
        .buttonStyle(.plain)
        .help(Date(timeIntervalSince1970: ts).formatted(date: .abbreviated, time: .standard))
    }

    private var text: String {
        let d = Date(timeIntervalSince1970: ts)
        if absolute {
            return d.formatted(date: .numeric, time: .shortened)
        }
        let ago = store.now.timeIntervalSince(d)
        return ago < 5 ? "just now" : "\(fmtDuration(ago)) ago"
    }
}
