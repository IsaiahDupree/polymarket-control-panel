import Foundation

/// Tolerant JSON scalar — backend param defaults can be bool/int/float/string.
enum JSONValue: Decodable, Hashable {
    case string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .null }
    }

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e12
            ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return ""
        }
    }
    var boolValue: Bool { if case .bool(let b) = self { return b }; return false }
}

// ---------------- accounts ----------------
struct AccountsPayload: Decodable {
    let accounts: [Account]
    let generated_at: Double?
}

struct Account: Decodable, Identifiable {
    let id: String
    let name: String
    let funder: String?
    let signer: String?
    let has_creds: Bool?
    let error: String?
    let balance_usd: Double?
    let balance_source: String?
    let balance_error: String?
    let positions_n: Int?
    let positions_value: Double?
    let open_orders_n: Int?
    let running_strats: [RunningStrat]?

    var strats: [RunningStrat] { running_strats ?? [] }
    var liveStrats: [RunningStrat] { strats.filter { $0.live ?? false } }
    var paperStrats: [RunningStrat] { strats.filter { !($0.live ?? false) } }
    var shortAddr: String {
        guard let f = funder, f.count > 10 else { return funder ?? "" }
        return "\(f.prefix(6))…\(f.suffix(4))"
    }
}

struct RunningStrat: Decodable, Identifiable, Hashable {
    let module: String?
    let pid: Int?
    let etime: String?
    let up_secs: Double?
    let live: Bool?
    let strat_key: String?
    let label: String?

    var id: String { "\(module ?? "?")-\(pid ?? 0)" }
    var displayName: String { label ?? module ?? "?" }
}

// ---------------- positions ----------------
struct PositionsPayload: Decodable { let positions: [String: [Position]] }

/// One open position. Numeric fields decode tolerantly (number OR numeric
/// string) because upstream APIs are inconsistent about this.
struct Position: Decodable, Identifiable {
    let title: String?
    let slug: String?
    let outcome: String?
    let size: Double?
    let avgPrice: Double?
    let curPrice: Double?
    let currentValue: Double?
    let initialValue: Double?
    let cashPnl: Double?
    let percentPnl: Double?
    let endDate: String?
    let redeemable: Bool?

    var id: String { "\(slug ?? title ?? "?")|\(outcome ?? "?")" }

    /// Best-effort resolution time. Up/Down window markets encode the exact
    /// window in their slug ("…-15m-<epochStart>"), which beats the date-only
    /// endDate the API returns for them.
    var end: Date? { Position.windowEnd(fromSlug: slug) ?? Position.parseISO(endDate) }

    static func windowEnd(fromSlug slug: String?) -> Date? {
        guard let slug else { return nil }
        // pattern: -<minutes>m-<epoch>   e.g. btc-updown-15m-1783272600
        let parts = slug.split(separator: "-")
        guard parts.count >= 2,
              let epoch = Double(parts[parts.count - 1]), epoch > 1_000_000_000,
              parts[parts.count - 2].hasSuffix("m"),
              let mins = Double(parts[parts.count - 2].dropLast()) else { return nil }
        return Date(timeIntervalSince1970: epoch + mins * 60)
    }

    enum K: String, CodingKey {
        case title, slug, outcome, size, avgPrice, curPrice, currentValue,
             initialValue, cashPnl, percentPnl, endDate, redeemable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        func dbl(_ k: K) -> Double? {
            if let v = try? c.decode(Double.self, forKey: k) { return v }
            if let s = try? c.decode(String.self, forKey: k) { return Double(s) }
            return nil
        }
        title = try? c.decode(String.self, forKey: .title)
        slug = try? c.decode(String.self, forKey: .slug)
        outcome = try? c.decode(String.self, forKey: .outcome)
        size = dbl(.size)
        avgPrice = dbl(.avgPrice)
        curPrice = dbl(.curPrice)
        currentValue = dbl(.currentValue)
        initialValue = dbl(.initialValue)
        cashPnl = dbl(.cashPnl)
        percentPnl = dbl(.percentPnl)
        endDate = try? c.decode(String.self, forKey: .endDate)
        redeemable = try? c.decode(Bool.self, forKey: .redeemable)
    }

    private static let isoPlain = ISO8601DateFormatter()
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    static func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return isoPlain.date(from: s) ?? isoFrac.date(from: s) ?? dateOnly.date(from: s)
    }
}

// ---------------- health ----------------
struct Health: Decodable {
    let ok: Bool
    let uptime_secs: Double?
    let proxy_exit: String?
    let proxy_on: Bool?
    let strats_enabled: Bool?
}

// ---------------- history ----------------
struct HistoryPoint: Decodable, Identifiable {
    let ts: Double
    let balance_usd: Double
    var id: Double { ts }
    var date: Date { Date(timeIntervalSince1970: ts) }
}

struct Change: Decodable {
    let delta: Double
    let pct: Double
    let has_data: Bool
}

struct BalanceHistory: Decodable {
    let series: [HistoryPoint]
    let change: Change?
}

struct StratPoint: Decodable, Identifiable {
    let ts: Double
    let live: Int
    let paper: Int
    var id: Double { ts }
    var date: Date { Date(timeIntervalSince1970: ts) }
}

struct StratHistory: Decodable { let series: [StratPoint] }

// ---------------- strategy catalog ----------------
struct CatalogPayload: Decodable {
    let strats: [Strat]
    let enabled: Bool?
}

struct Strat: Decodable, Identifiable, Hashable {
    let key: String
    let label: String
    let module: String
    let desc: String
    let live_capable: Bool?
    let params: [StratParam]
    var id: String { key }
}

struct StratParam: Decodable, Hashable {
    let name: String
    let flag: String
    let type: String          // int | float | bool | choice
    let help: String
    let choices: [String]
    let def: JSONValue

    enum CodingKeys: String, CodingKey {
        case name, flag, type, help, choices
        case def = "default"
    }
}

struct RunningPayload: Decodable {
    let running: [String: [RunningStrat]]
}

// ---------------- bots ----------------
struct BotsPayload: Decodable { let bots: [Bot] }

/// One running bot process with its parsed launch config (--flag params).
struct Bot: Decodable, Identifiable, Hashable {
    let account: String?
    let module: String?
    let sub: String?
    let pid: Int?
    let etime: String?
    let up_secs: Double?
    let live: Bool?
    let params: [String: JSONValue]?
    let command: String?

    var id: String { "\(module ?? "?")-\(pid ?? 0)" }
    var isLive: Bool { live ?? false }

    /// Params ordered by importance: money-critical first, then alphabetical.
    var orderedParams: [(key: String, value: JSONValue)] {
        let priority = ["live", "size", "coin", "minutes", "buy", "floor",
                        "tilt-size", "max-buys", "min-price", "max-price",
                        "slug-prefix", "interval"]
        return (params ?? [:]).sorted { a, b in
            let ia = priority.firstIndex(of: a.key) ?? Int.max
            let ib = priority.firstIndex(of: b.key) ?? Int.max
            return ia != ib ? ia < ib : a.key < b.key
        }.map { ($0.key, $0.value) }
    }
}

// ---------------- registry ----------------
struct RegistryPayload: Decodable {
    let registrations: [Registration]
    let orphans: [RegInstance]
    let unmapped: [RegInstance]
}

/// A named bot→account binding with desired vs actual state.
struct Registration: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let account: String
    let strat: String
    let params: [String: JSONValue]?
    let desired: String
    let status: String?          // off | paper | live (actual, from scan)
    let drift: Bool?             // actual != desired
    let account_verified: Bool?  // nil while off
    let instances: [RegInstance]?

    var actualStatus: String { status ?? "off" }
}

struct RegInstance: Decodable, Identifiable, Hashable {
    let pid: Int?
    let module: String?
    let account: String?
    let live: Bool?
    let etime: String?
    let up_secs: Double?
    var id: String { "\(module ?? "?")-\(pid ?? 0)" }
}

extension Strat {
    /// Map parsed --flag values from a running process onto this strategy's
    /// catalog param names (flag "slug-prefix" → param "slug_prefix"), so a
    /// running bot's config can prefill a registration.
    func paramValues(fromFlags flags: [String: JSONValue]) -> [String: JSONValue] {
        var out: [String: JSONValue] = [:]
        for p in params {
            let flagKey = p.flag.hasPrefix("--") ? String(p.flag.dropFirst(2)) : p.flag
            if let v = flags[flagKey] { out[p.name] = v }
        }
        return out
    }
}

// ---------------- markets ----------------
struct MarketsPayload: Decodable { let markets: [Market] }

struct Market: Decodable, Identifiable {
    let question: String?
    let slug: String?
    let volume24hr: Double?
    let outcomes: String?
    let clobTokenIds: [String]?
    var id: String { slug ?? question ?? UUID().uuidString }
}

struct BookPayload: Decodable { let book: Book }
struct Book: Decodable {
    let bids: [BookLevel]?
    let asks: [BookLevel]?
    let error: String?
}
struct BookLevel: Decodable, Identifiable {
    let price: String?
    let size: String?
    var id: String { "\(price ?? "?")-\(size ?? "?")" }
}

// ---------------- logs / audit ----------------
struct LogListPayload: Decodable { let logs: [LogFile]? , tail: String? }
struct LogFile: Decodable, Identifiable {
    let name: String
    let mtime: Double
    let size: Int
    var id: String { name }
}

struct AuditPayload: Decodable { let audit: [AuditEntry] }
struct AuditEntry: Decodable, Identifiable {
    let ts: Double
    let iso: String?
    let action: String?
    let account: String?
    let detail: [String: JSONValue]?
    var id: Double { ts }
    var detailText: String {
        (detail ?? [:]).map { "\($0.key)=\($0.value.stringValue)" }
            .sorted().joined(separator: "  ")
    }
}
