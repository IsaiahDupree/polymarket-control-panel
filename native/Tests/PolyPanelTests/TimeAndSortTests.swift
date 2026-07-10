import XCTest
@testable import PolyPanel

final class TimeAndSortTests: XCTestCase {

    // ---------------- duration / money formatting ----------------
    func testFmtDuration() {
        XCTAssertEqual(fmtDuration(0), "0s")
        XCTAssertEqual(fmtDuration(45), "45s")
        XCTAssertEqual(fmtDuration(125), "2m 5s")
        XCTAssertEqual(fmtDuration(3600), "1h 0m")
        XCTAssertEqual(fmtDuration(93784), "1d 2h")
        XCTAssertEqual(fmtDuration(-10), "0s")  // clamps, never negative
    }

    func testFmtSigned() {
        XCTAssertEqual(fmtSigned(5.5), "+" + fmtUSD(5.5))
        XCTAssertEqual(fmtSigned(-5.5), "−" + fmtUSD(5.5))
        XCTAssertEqual(fmtSigned(0), "+" + fmtUSD(0))
    }

    func testFmtUSD() {
        XCTAssertEqual(fmtUSD(nil), "—")
        XCTAssertTrue(fmtUSD(14.66).contains("14.66"))
        XCTAssertTrue(fmtUSD(14.66).hasPrefix("$"))
    }

    // ---------------- urgency sorting ----------------
    private func position(slug: String?, endDate: String? = nil,
                          value: Double? = nil) throws -> Position {
        var fields: [String] = []
        if let slug { fields.append("\"slug\": \"\(slug)\"") }
        if let endDate { fields.append("\"endDate\": \"\(endDate)\"") }
        if let value { fields.append("\"currentValue\": \(value)") }
        let json = "{\(fields.joined(separator: ", "))}"
        return try JSONDecoder().decode(Position.self, from: Data(json.utf8))
    }

    @MainActor
    func testPositionsByUrgency() throws {
        let store = AppStore()
        let now = Date()
        store.now = now
        let nowEpoch = Int(now.timeIntervalSince1970)

        // ends in 20 min
        let soon = try position(slug: "btc-updown-5m-\(nowEpoch + 900)")
        // ends in ~2h
        let later = try position(slug: "btc-updown-15m-\(nowEpoch + 6300)")
        // already resolved 1h ago (awaiting redeem)
        let resolved = try position(slug: "eth-updown-15m-\(nowEpoch - 4500)")
        // no end time, big value
        let openEnded = try position(slug: "who-wins-election", value: 100)

        store.positions = ["a": [openEnded, later], "b": [resolved, soon]]

        let sorted = store.positionsByUrgency.map { $0.position.slug ?? "" }
        XCTAssertEqual(sorted, [
            "btc-updown-5m-\(nowEpoch + 900)",      // soonest future first
            "btc-updown-15m-\(nowEpoch + 6300)",    // later future
            "eth-updown-15m-\(nowEpoch - 4500)",    // resolved next
            "who-wins-election",                     // no end time last
        ])
    }

    @MainActor
    func testDerivedTotals() throws {
        let store = AppStore()
        let p1 = try position(slug: "x", value: 5.5)
        let p2 = try position(slug: "y", value: 1.25)
        store.positions = ["a": [p1], "b": [p2]]
        XCTAssertEqual(store.inMarketsTotal, 6.75, accuracy: 0.001)
    }
}
