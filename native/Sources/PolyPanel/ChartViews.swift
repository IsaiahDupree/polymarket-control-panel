import SwiftUI
import Charts

/// Polymarket-style balance line: blue line + gradient fill, hover crosshair.
struct BalanceChart: View {
    let points: [HistoryPoint]
    var height: CGFloat = 230
    @State private var selected: Date?

    var body: some View {
        Group {
            if points.isEmpty {
                Text("Collecting history…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: height)
            } else {
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Time", p.date),
                                 y: .value("USD", p.balance_usd))
                            .foregroundStyle(
                                LinearGradient(colors: [Theme.blue.opacity(0.32), .clear],
                                               startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Time", p.date),
                                 y: .value("USD", p.balance_usd))
                            .foregroundStyle(Theme.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                    }
                    if let selected, let p = nearest(to: selected) {
                        RuleMark(x: .value("Sel", p.date))
                            .foregroundStyle(Theme.text.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        PointMark(x: .value("Time", p.date),
                                  y: .value("USD", p.balance_usd))
                            .foregroundStyle(Theme.blue)
                            .annotation(position: .top, alignment: .leading) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.date, format: .dateTime.month().day().hour().minute())
                                        .foregroundStyle(Theme.muted)
                                    Text(fmtUSD(p.balance_usd)).bold()
                                        .foregroundStyle(Theme.text)
                                }
                                .font(.system(size: 11))
                                .padding(6)
                                .background(Theme.codeBg)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(Theme.border, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                    }
                }
                .chartXSelection(value: $selected)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                        AxisValueLabel {
                            if let d = v.as(Double.self) {
                                Text(fmtUSD(d)).font(.system(size: 10))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(.clear)
                        AxisValueLabel().font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(height: height)
            }
        }
    }

    private func nearest(to date: Date) -> HistoryPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

/// Live vs paper running-strategy counts (stepped lines).
struct StratActivityChart: View {
    let points: [StratPoint]
    var height: CGFloat = 150

    var body: some View {
        Group {
            if points.isEmpty {
                Text("Collecting history…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: height)
            } else {
                Chart {
                    ForEach(points) { p in
                        LineMark(x: .value("Time", p.date),
                                 y: .value("Count", p.live),
                                 series: .value("Kind", "Live"))
                            .foregroundStyle(Theme.red)
                            .interpolationMethod(.stepEnd)
                        LineMark(x: .value("Time", p.date),
                                 y: .value("Count", p.paper),
                                 series: .value("Kind", "Paper"))
                            .foregroundStyle(Theme.blue)
                            .interpolationMethod(.stepEnd)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Theme.border.opacity(0.6))
                        AxisValueLabel().font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(height: height)
            }
        }
    }
}

/// Tiny axis-less balance sparkline for account cards.
struct Sparkline: View {
    let points: [HistoryPoint]
    var height: CGFloat = 54

    var body: some View {
        Group {
            if points.count < 2 {
                Rectangle().fill(.clear).frame(height: height)
            } else {
                Chart(points) { p in
                    AreaMark(x: .value("t", p.date), y: .value("v", p.balance_usd))
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.blue.opacity(0.25), .clear],
                                           startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("t", p.date), y: .value("v", p.balance_usd))
                        .foregroundStyle(Theme.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
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
