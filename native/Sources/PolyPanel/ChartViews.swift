import SwiftUI
import Charts

// Chart language of the app:
//   - line color = trend over the visible window (green up / red down),
//     like Polymarket's market charts
//   - dashed baseline at the window's starting value, so "above/below where
//     I started" reads instantly
//   - glowing endpoint dot + current-value tag = "now"
//   - hover crosshair with value + delta-vs-start

/// Primary balance chart.
struct BalanceChart: View {
    let points: [HistoryPoint]
    var height: CGFloat = 230
    @State private var selected: Date?

    private var first: Double { points.first?.balance_usd ?? 0 }
    private var last: Double { points.last?.balance_usd ?? 0 }
    private var trend: Color { last >= first ? Theme.green : Theme.red }
    private var minPt: HistoryPoint? { points.min { $0.balance_usd < $1.balance_usd } }
    private var maxPt: HistoryPoint? { points.max { $0.balance_usd < $1.balance_usd } }

    var body: some View {
        Group {
            if points.count < 2 {
                VStack(spacing: 4) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 20)).foregroundStyle(Theme.muted.opacity(0.5))
                    Text("Collecting history…")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, minHeight: height)
            } else {
                chart
            }
        }
    }

    private var chart: some View {
        Chart {
            // baseline: where this window started
            RuleMark(y: .value("Start", first))
                .foregroundStyle(Theme.muted.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))

            ForEach(points) { p in
                AreaMark(x: .value("Time", p.date), y: .value("USD", p.balance_usd))
                    .foregroundStyle(LinearGradient(
                        colors: [trend.opacity(0.30), trend.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", p.date), y: .value("USD", p.balance_usd))
                    .foregroundStyle(trend)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .interpolationMethod(.monotone)
            }

            // min / max markers
            if let maxPt, maxPt.ts != points.last?.ts {
                PointMark(x: .value("Time", maxPt.date), y: .value("USD", maxPt.balance_usd))
                    .symbolSize(24)
                    .foregroundStyle(Theme.muted)
                    .annotation(position: .top) {
                        Text(fmtUSD(maxPt.balance_usd))
                            .font(.system(size: 9.5, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
            }
            if let minPt, minPt.ts != points.last?.ts {
                PointMark(x: .value("Time", minPt.date), y: .value("USD", minPt.balance_usd))
                    .symbolSize(24)
                    .foregroundStyle(Theme.muted)
                    .annotation(position: .bottom) {
                        Text(fmtUSD(minPt.balance_usd))
                            .font(.system(size: 9.5, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
            }

            // "now" endpoint: glow + value tag
            if let lastP = points.last {
                PointMark(x: .value("Time", lastP.date), y: .value("USD", lastP.balance_usd))
                    .symbolSize(160)
                    .foregroundStyle(trend.opacity(0.25))
                PointMark(x: .value("Time", lastP.date), y: .value("USD", lastP.balance_usd))
                    .symbolSize(45)
                    .foregroundStyle(trend)
                    .annotation(position: .topTrailing, alignment: .leading) {
                        Text(fmtUSD(lastP.balance_usd))
                            .font(.system(size: 10.5, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(trend.opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
            }

            // hover crosshair
            if let selected, let p = nearest(to: selected) {
                RuleMark(x: .value("Sel", p.date))
                    .foregroundStyle(Theme.text.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                PointMark(x: .value("Time", p.date), y: .value("USD", p.balance_usd))
                    .symbolSize(60)
                    .foregroundStyle(trend)
                    .annotation(position: .top, alignment: .leading) { tooltip(p) }
            }
        }
        .chartXSelection(value: $selected)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine().foregroundStyle(Theme.border.opacity(0.55))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(fmtUSD(d)).font(.system(size: 10)).monospacedDigit()
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }
        .frame(height: height)
    }

    private func tooltip(_ p: HistoryPoint) -> some View {
        let delta = p.balance_usd - first
        let pct = first != 0 ? delta / first * 100 : 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(p.date, format: .dateTime.month().day().hour().minute())
                .foregroundStyle(Theme.muted)
            Text(fmtUSD(p.balance_usd)).bold().foregroundStyle(Theme.text)
            Text("\(delta >= 0 ? "+" : "−")\(fmtUSD(abs(delta))) (\(String(format: "%.2f", abs(pct)))%) vs start")
                .foregroundStyle(delta >= 0 ? Theme.green : Theme.red)
        }
        .font(.system(size: 10.5))
        .monospacedDigit()
        .padding(7)
        .background(Theme.codeBg)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func nearest(to date: Date) -> HistoryPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

/// Live vs paper running-strategy counts. Both series toggleable via the
/// clickable legend chips in the owning card.
struct StratActivityChart: View {
    let points: [StratPoint]
    var showLive = true
    var showPaper = true
    var height: CGFloat = 150
    @State private var selected: Date?

    var body: some View {
        Group {
            if points.isEmpty {
                Text("Collecting history…")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: height)
            } else {
                chart
            }
        }
    }

    private var chart: some View {
        Chart {
            if showLive {
                ForEach(points) { p in
                    AreaMark(x: .value("Time", p.date), y: .value("Live", p.live),
                             series: .value("Kind", "Live"))
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.red.opacity(0.22), .clear],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.stepEnd)
                    LineMark(x: .value("Time", p.date), y: .value("Live", p.live),
                             series: .value("Kind", "Live"))
                        .foregroundStyle(Theme.red)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.stepEnd)
                }
            }
            if showPaper {
                ForEach(points) { p in
                    LineMark(x: .value("Time", p.date), y: .value("Paper", p.paper),
                             series: .value("Kind", "Paper"))
                        .foregroundStyle(Theme.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.stepEnd)
                }
            }
            if let selected, let p = nearestStrat(to: selected) {
                RuleMark(x: .value("Sel", p.date))
                    .foregroundStyle(Theme.text.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.date, format: .dateTime.month().day().hour().minute())
                                .foregroundStyle(Theme.muted)
                            if showLive { Text("● \(p.live) live").foregroundStyle(Theme.red) }
                            if showPaper { Text("● \(p.paper) paper").foregroundStyle(Theme.blue) }
                        }
                        .font(.system(size: 10.5)).monospacedDigit()
                        .padding(6)
                        .background(Theme.codeBg)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.border.opacity(0.55))
                AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
        }
        .frame(height: height)
    }

    private func nearestStrat(to date: Date) -> StratPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

/// Tiny axis-less trend-colored sparkline for account cards / menu bar.
struct Sparkline: View {
    let points: [HistoryPoint]
    var height: CGFloat = 54

    private var trend: Color {
        guard let f = points.first?.balance_usd, let l = points.last?.balance_usd
        else { return Theme.blue }
        return l >= f ? Theme.green : Theme.red
    }

    var body: some View {
        Group {
            if points.count < 2 {
                Rectangle().fill(.clear).frame(height: height)
            } else {
                Chart(points) { p in
                    AreaMark(x: .value("t", p.date), y: .value("v", p.balance_usd))
                        .foregroundStyle(LinearGradient(
                            colors: [trend.opacity(0.22), .clear],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("t", p.date), y: .value("v", p.balance_usd))
                        .foregroundStyle(trend)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: height)
            }
        }
    }
}
