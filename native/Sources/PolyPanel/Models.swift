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
    let live: Bool?
    let strat_key: String?
    let label: String?

    var id: String { "\(module ?? "?")-\(pid ?? 0)" }
    var displayName: String { label ?? module ?? "?" }
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
