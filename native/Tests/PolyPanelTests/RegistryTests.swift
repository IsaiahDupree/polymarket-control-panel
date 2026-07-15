import XCTest
@testable import PolyPanel

final class RegistryTests: XCTestCase {

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private var catalogStrat: Strat {
        get throws {
            try decode("""
            {"key": "hold_roller", "label": "Hold-Set Roller", "module": "hold_roller",
             "desc": "d", "live_capable": true,
             "params": [
                {"name": "buy", "flag": "--buy", "type": "float", "default": 0.48,
                 "help": "h", "choices": []},
                {"name": "slug_prefix", "flag": "--slug-prefix", "type": "choice",
                 "default": "btc-updown-15m", "help": "h",
                 "choices": ["btc-updown-5m", "btc-updown-15m"]},
                {"name": "complete_set", "flag": "--complete-set", "type": "bool",
                 "default": true, "help": "h", "choices": []}
             ]}
            """)
        }
    }

    // flag names from a running process ("slug-prefix") must map onto catalog
    // param names ("slug_prefix") so a running bot can prefill a registration
    func testParamValuesFromFlags() throws {
        let flags: [String: JSONValue] = [
            "buy": .string("0.51"),
            "slug-prefix": .string("btc-updown-5m"),
            "complete-set": .bool(true),
            "live": .bool(true),          // not a catalog param -> dropped
            "unknown-flag": .string("x"), // -> dropped
        ]
        let mapped = try catalogStrat.paramValues(fromFlags: flags)
        XCTAssertEqual(mapped["buy"]?.stringValue, "0.51")
        XCTAssertEqual(mapped["slug_prefix"]?.stringValue, "btc-updown-5m")
        XCTAssertEqual(mapped["complete_set"]?.boolValue, true)
        XCTAssertNil(mapped["live"])
        XCTAssertEqual(mapped.count, 3)
    }

    func testRegistryPayloadDecode() throws {
        let payload: RegistryPayload = try decode("""
        {"registrations": [
            {"id": "abc12345", "name": "roller-main", "account": "btc",
             "strat": "hold_roller", "params": {"size": "3"},
             "desired": "live", "status": "paper", "drift": true,
             "account_verified": true,
             "instances": [{"pid": 42, "module": "hold_roller", "account": "btc",
                            "live": false, "etime": "10:00", "up_secs": 600}],
             "created_at": 1783278300.0}],
         "orphans": [{"pid": 7, "module": "late_winner", "account": "weather",
                      "live": false, "etime": "01:00", "up_secs": 60}],
         "unmapped": []}
        """)
        let r = payload.registrations[0]
        XCTAssertEqual(r.name, "roller-main")
        XCTAssertEqual(r.actualStatus, "paper")
        XCTAssertEqual(r.desired, "live")
        XCTAssertEqual(r.drift, true)                 // wanted live, running paper
        XCTAssertEqual(r.account_verified, true)
        XCTAssertEqual(r.instances?.first?.pid, 42)
        XCTAssertEqual(payload.orphans.first?.module, "late_winner")
        XCTAssertTrue(payload.unmapped.isEmpty)
    }

    func testRegistrationOffDefaults() throws {
        let r: Registration = try decode("""
        {"id": "x", "name": "n", "account": "a", "strat": "s",
         "desired": "off", "created_at": 1.0}
        """)
        XCTAssertEqual(r.actualStatus, "off")   // no status field -> off
        XCTAssertNil(r.account_verified)
        XCTAssertNil(r.instances)
    }
}
