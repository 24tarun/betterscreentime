import XCTest
@testable import BetterScreenTimeCore

final class ScreenTimeCoreAggregationTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func day(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 16
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return cal.date(from: comps)!
    }

    func testComputeAggregatesCalculatesTotalsAndHourlySlices() {
        let events = [
            AppEvent(app: "Chrome", bundleId: "com.google.Chrome", start: day(10, 10), end: day(10, 40)),
            AppEvent(app: "Chrome", bundleId: "com.google.Chrome", start: day(11, 20), end: day(11, 50)),
            AppEvent(app: "Slack", bundleId: "com.slack.Slack", start: day(10, 30), end: day(11, 0))
        ]

        let agg = ScreenTimeCore.computeAggregates(from: events, calendar: cal)

        XCTAssertEqual(agg.totalSeconds, 5400)
        XCTAssertEqual(agg.totals.first?.app, "Chrome")
        XCTAssertEqual(agg.totals.first?.seconds, 3600)
        XCTAssertEqual(agg.maxHourlySeconds, 3600, accuracy: 0.001)
        XCTAssertEqual(agg.hourlySlices.count, 3)
    }

    func testEventsInRangeClipsBoundariesAndDropsNonOverlap() {
        let events = [
            AppEvent(app: "A", bundleId: "a", start: day(9, 45), end: day(10, 15)),
            AppEvent(app: "B", bundleId: "b", start: day(10, 30), end: day(11, 0)),
            AppEvent(app: "C", bundleId: "c", start: day(12, 0), end: day(12, 15))
        ]
        let range = day(10, 0)...day(10, 45)

        let clipped = ScreenTimeCore.events(in: range, from: events)

        XCTAssertEqual(clipped.count, 2)
        XCTAssertEqual(clipped[0].durationSeconds, 900)
        XCTAssertEqual(clipped[1].durationSeconds, 900)
        XCTAssertTrue(clipped.allSatisfy { $0.start >= range.lowerBound && $0.end <= range.upperBound })
    }

    func testTopAppsAggregatesAndRespectsLimit() {
        let events = [
            AppEvent(app: "Safari", bundleId: "s", start: day(9), end: day(10)),
            AppEvent(app: "Slack", bundleId: "l", start: day(10), end: day(10, 20)),
            AppEvent(app: "Slack", bundleId: "l", start: day(11), end: day(11, 20)),
            AppEvent(app: "Mail", bundleId: "m", start: day(12), end: day(12, 5))
        ]

        let top2 = ScreenTimeCore.topApps(from: events, limit: 2)

        XCTAssertEqual(top2.count, 2)
        XCTAssertEqual(top2[0].app, "Safari")
        XCTAssertEqual(top2[0].seconds, 3600)
        XCTAssertEqual(top2[1].app, "Slack")
        XCTAssertEqual(top2[1].seconds, 2400)
    }
}
