import XCTest
@testable import BetterScreenTimeCore

final class ScreenTimeCoreNormalizationTests: XCTestCase {
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

    func testMergeAdjacentEventsMergesSameBundleWithinGap() {
        let events = [
            AppEvent(app: "Chrome", bundleId: "com.google.Chrome", start: day(9, 0, 0), end: day(9, 10, 0)),
            AppEvent(app: "Chrome", bundleId: "com.google.Chrome", start: day(9, 10, 1), end: day(9, 20, 0)),
            AppEvent(app: "Chrome", bundleId: "com.google.Chrome", start: day(9, 20, 3), end: day(9, 30, 0))
        ]

        let merged = ScreenTimeCore.mergeAdjacentEvents(events, maxGapSeconds: 2)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].start, day(9, 0, 0))
        XCTAssertEqual(merged[0].end, day(9, 20, 0))
        XCTAssertEqual(merged[1].start, day(9, 20, 3))
    }

    func testMergeAdjacentEventsNeverMergesAcrossBundles() {
        let events = [
            AppEvent(app: "Chrome", bundleId: "chrome", start: day(9, 0), end: day(9, 5)),
            AppEvent(app: "Safari", bundleId: "safari", start: day(9, 5, 1), end: day(9, 10))
        ]

        let merged = ScreenTimeCore.mergeAdjacentEvents(events)
        XCTAssertEqual(merged.count, 2)
    }

    func testFilterQualifiedBundlesKeepsOnlyBundlesAboveThreshold() {
        let events = [
            AppEvent(app: "Slack", bundleId: "slack", start: day(10, 0), end: day(10, 1, 5)),
            AppEvent(app: "Mail", bundleId: "mail", start: day(11, 0), end: day(11, 0, 40))
        ]

        let filtered = ScreenTimeCore.filterQualifiedBundles(events, minimumTotalSeconds: 60)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].bundleId, "slack")
    }

    func testBridgedSpansBridgesSmallGapsOnly() {
        let events = [
            AppEvent(app: "Xcode", bundleId: "x", start: day(8, 0), end: day(8, 10)),
            AppEvent(app: "Xcode", bundleId: "x", start: day(8, 12), end: day(8, 20)),
            AppEvent(app: "Xcode", bundleId: "x", start: day(8, 30), end: day(8, 40))
        ]

        let spans = ScreenTimeCore.bridgedSpans(for: events, gapSeconds: 300)

        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].start, day(8, 0))
        XCTAssertEqual(spans[0].end, day(8, 20))
        XCTAssertEqual(spans[1].start, day(8, 30))
    }

    func testIntegrationFixtureBalancedDataAndTimelineSignals() {
        let fixture = [
            AppEvent(app: "Chrome", bundleId: "chrome", start: day(9, 0), end: day(9, 45)),
            AppEvent(app: "Chrome", bundleId: "chrome", start: day(10, 0), end: day(10, 30)),
            AppEvent(app: "Slack", bundleId: "slack", start: day(9, 30), end: day(10, 0)),
            AppEvent(app: "Xcode", bundleId: "xcode", start: day(11, 0), end: day(12, 0))
        ]

        let merged = ScreenTimeCore.mergeAdjacentEvents(fixture)
        let filtered = ScreenTimeCore.filterQualifiedBundles(merged)
        let agg = ScreenTimeCore.computeAggregates(from: filtered, calendar: cal)
        let selection = ScreenTimeCore.events(in: day(9, 15)...day(10, 15), from: filtered)
        let top = ScreenTimeCore.topApps(from: selection, limit: 2)

        XCTAssertEqual(filtered.count, 4)
        XCTAssertEqual(agg.totalSeconds, 9900)
        XCTAssertEqual(agg.totals.first?.app, "Chrome")
        XCTAssertEqual(top.first?.app, "Chrome")
        XCTAssertEqual(top.first?.seconds, 2700)
    }
}
