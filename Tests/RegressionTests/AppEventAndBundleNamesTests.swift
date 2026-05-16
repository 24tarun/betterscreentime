import XCTest
@testable import BetterScreenTimeCore

final class AppEventAndBundleNamesTests: XCTestCase {
    func testFormattedDurationForHourMinuteAndSeconds() {
        let start = Date(timeIntervalSince1970: 1_000)
        let oneHourFiveMinutes = AppEvent(
            app: "A",
            bundleId: "a",
            start: start,
            end: start.addingTimeInterval(3900)
        )
        let oneMinuteFiveSeconds = AppEvent(
            app: "B",
            bundleId: "b",
            start: start,
            end: start.addingTimeInterval(65)
        )
        let pureSeconds = AppEvent(
            app: "C",
            bundleId: "c",
            start: start,
            end: start.addingTimeInterval(9)
        )

        XCTAssertEqual(oneHourFiveMinutes.formattedDuration, "1h 5m")
        XCTAssertEqual(oneMinuteFiveSeconds.formattedDuration, "1m 5s")
        XCTAssertEqual(pureSeconds.formattedDuration, "9s")
    }

    func testBundleNameResolutionKnownAndFallback() {
        XCTAssertEqual(BundleNames.resolve("com.google.Chrome"), "Chrome")
        XCTAssertEqual(BundleNames.resolve("com.example.deepwork"), "Deepwork")
        XCTAssertEqual(BundleNames.resolve("singleword"), "Singleword")
    }
}
