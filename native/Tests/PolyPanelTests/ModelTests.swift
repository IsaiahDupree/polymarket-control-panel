import XCTest
@testable import PolyPanel

final class ModelTests: XCTestCase {

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // ---------------- JSONValue ----------------
    func testJSONValueVariants() throws {
        struct Box: Decodable { let v: JSONValue }
        XCTAssertEqual((try decode("{\"v\": \"x\"}") as Box).v.stringValue, "x")
        XCTAssertEqual((try decode("{\"v\": 3}") as Box).v.stringValue, "3")
        XCTAssertEqual((try decode("{\"v\": 0.48}") as Box).v.stringValue, "0.48")
        XCTAssertEqual((try decode("{\"v\": true}") as Box).v.boolValue, true)
        XCTAssertEqual((try decode("{\"v\": null}") as Box).v.stringValue, "")
    }

    // ---------------- Position ----------------
    func testPositionDecodesNumbersAndNumericStrings() throws {
        // upstream APIs are inconsistent: numbers sometimes arrive as strings
        let p: Position = try decode("""
        {"title": "Will BTC go up?", "outcome": "Up",
         "size": "5", "avgPrice": 0.48, "curPrice": "0.52",
         "currentValue": "5.50", "cashPnl": 0.2, "percentPnl": "8.3",
         "endDate": "2026-07-07T16:00:00Z"}
        """)
        XCTAssertEqual(p.size, 5)
        XCTAssertEqual(p.avgPrice, 0.48)
        XCTAssertEqual(p.curPrice, 0.52)
        XCTAssertEqual(p.currentValue, 5.50)
        XCTAssertEqual(p.percentPnl, 8.3)
        XCTAssertNotNil(p.end)
    }

    func testWindowEndParsedFromSlug() throws {
        // 15m window starting at epoch 1783272600 → ends 900s later
        let p: Position = try decode("""
        {"slug": "eth-updown-15m-1783272600", "endDate": "2026-07-05"}
        """)
        XCTAssertEqual(p.end?.timeIntervalSince1970, 1783272600 + 900)

        // 5m window
        let q: Position = try decode("""
        {"slug": "btc-updown-5m-1783272600"}
        """)
        XCTAssertEqual(q.end?.timeIntervalSince1970, 1783272600 + 300)
    }

    func testEndFallsBackToISOAndDateOnly() throws {
        let iso: Position = try decode("""
        {"slug": "some-market", "endDate": "2026-07-07T16:00:00Z"}
        """)
        XCTAssertEqual(iso.end?.timeIntervalSince1970, 1783440000)  // 2026-07-07T16:00:00Z

        let dateOnly: Position = try decode("""
        {"slug": "another-market", "endDate": "2026-07-05"}
        """)
        XCTAssertNotNil(dateOnly.end)

        let none: Position = try decode("{\"slug\": \"x\"}")
        XCTAssertNil(none.end)
    }

    // ---------------- Bot ----------------
    func testBotOrderedParamsPutMoneyCriticalFirst() throws {
        let b: Bot = try decode("""
        {"module": "hold_roller", "pid": 1, "live": true,
         "params": {"interval": "6", "buy": "0.48", "zeta": "9",
                    "live": true, "size": "3", "alpha": "1"}}
        """)
        let keys = b.orderedParams.map(\.key)
        XCTAssertEqual(Array(keys.prefix(3)), ["live", "size", "buy"])
        // non-priority params alphabetical at the end
        XCTAssertEqual(Array(keys.suffix(2)), ["alpha", "zeta"])
    }

    func testBotsPayloadDecode() throws {
        let payload: BotsPayload = try decode("""
        {"bots": [{"module": "late_winner", "account": "btc", "pid": 42,
                   "etime": "01:00", "up_secs": 60, "live": false,
                   "params": {"coin": "ETH"}, "command": "python -m x"}]}
        """)
        XCTAssertEqual(payload.bots.count, 1)
        XCTAssertEqual(payload.bots[0].up_secs, 60)
        XCTAssertFalse(payload.bots[0].isLive)
    }

    // ---------------- accounts / history ----------------
    func testAccountsPayloadDecode() throws {
        let payload: AccountsPayload = try decode("""
        {"accounts": [{"id": "btc", "name": "BTC", "funder": "0x029375a110B6d5fF6085Aec8A8C18469a08321d2",
                       "has_creds": true, "balance_usd": 14.66, "positions_n": 1,
                       "open_orders_n": 0,
                       "running_strats": [{"module": "maker_rest", "pid": 7,
                                           "etime": "1-02:03:04", "up_secs": 93784,
                                           "live": true, "label": "Maker-Rest"}]}],
         "generated_at": 1783278300.0}
        """)
        let a = payload.accounts[0]
        XCTAssertEqual(a.balance_usd, 14.66)
        XCTAssertEqual(a.liveStrats.count, 1)
        XCTAssertEqual(a.paperStrats.count, 0)
        XCTAssertEqual(a.shortAddr, "0x0293…21d2")
        XCTAssertEqual(a.strats[0].up_secs, 93784)
    }

    func testHistoryDecode() throws {
        let h: BalanceHistory = try decode("""
        {"series": [{"ts": 1783278300.0, "balance_usd": 70.4}],
         "change": {"delta": 5.0, "pct": 50.0, "has_data": true}}
        """)
        XCTAssertEqual(h.series[0].balance_usd, 70.4)
        XCTAssertEqual(h.change?.pct, 50.0)

        let s: StratHistory = try decode("""
        {"series": [{"ts": 1783278300.0, "live": 9, "paper": 102}]}
        """)
        XCTAssertEqual(s.series[0].paper, 102)
    }

    func testStratParamDefaultKeyDecodes() throws {
        let strat: Strat = try decode("""
        {"key": "hold_roller", "label": "Hold", "module": "hold_roller",
         "desc": "d", "live_capable": true,
         "params": [{"name": "buy", "flag": "--buy", "type": "float",
                     "default": 0.48, "help": "h", "choices": []},
                    {"name": "complete_set", "flag": "--complete-set", "type": "bool",
                     "default": true, "help": "h", "choices": []}]}
        """)
        XCTAssertEqual(strat.params[0].def.stringValue, "0.48")
        XCTAssertTrue(strat.params[1].def.boolValue)
    }
}
