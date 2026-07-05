import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Polymarket-inspired dark palette — mirrors backend/static/index.html CSS vars.
enum Theme {
    static let bg = Color(hex: 0x141C27)
    static let panel = Color(hex: 0x1D2B39)
    static let panel2 = Color(hex: 0x22334A)
    static let border = Color(hex: 0x2C3F54)
    static let text = Color(hex: 0xE6EDF5)
    static let muted = Color(hex: 0x7E8DA0)
    static let blue = Color(hex: 0x2D9CDB)
    static let blueDim = Color(hex: 0x1F6FA0)
    static let green = Color(hex: 0x27AE60)
    static let red = Color(hex: 0xE64A45)
    static let yellow = Color(hex: 0xF2C94C)
    static let codeBg = Color(hex: 0x0E141D)
}

private let usdFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencySymbol = "$"
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f
}()

func fmtUSD(_ v: Double?) -> String {
    guard let v else { return "—" }
    return usdFormatter.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

/// Small colored capsule (LIVE / paper / idle chips, change badges).
struct Chip: View {
    let text: String
    let color: Color
    var filled = true

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 2.5)
            .foregroundStyle(color)
            .background(filled ? color.opacity(0.13) : .clear)
            .overlay(Capsule().stroke(color.opacity(filled ? 0 : 0.7), lineWidth: 1))
            .clipShape(Capsule())
    }
}

struct ChangeBadge: View {
    let delta: Double
    let pct: Double

    var body: some View {
        let up = delta >= 0
        Text("\(up ? "▲" : "▼") \(fmtUSD(abs(delta))) (\(String(format: "%.2f", abs(pct)))%)")
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 10).padding(.vertical, 3)
            .foregroundStyle(up ? Theme.green : Theme.red)
            .background((up ? Theme.green : Theme.red).opacity(0.12))
            .clipShape(Capsule())
    }
}
