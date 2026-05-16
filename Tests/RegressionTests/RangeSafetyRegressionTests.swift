import XCTest

final class RangeSafetyRegressionTests: XCTestCase {
    private var contentViewSource: String {
        let path = "/Users/tarun/Desktop/coding/betterscreentime/BetterScreenTime/BetterScreenTime/ContentView.swift"
        do {
            return try String(contentsOfFile: path)
        } catch {
            XCTFail("Could not load ContentView.swift: \(error)")
            return ""
        }
    }

    private var ganttViewSource: String {
        let path = "/Users/tarun/Desktop/coding/betterscreentime/BetterScreenTime/BetterScreenTime/GanttView.swift"
        do {
            return try String(contentsOfFile: path)
        } catch {
            XCTFail("Could not load GanttView.swift: \(error)")
            return ""
        }
    }

    private var coreSource: String {
        let path = "/Users/tarun/Desktop/coding/betterscreentime/BetterScreenTime/BetterScreenTime/ScreenTimeCore.swift"
        do {
            return try String(contentsOfFile: path)
        } catch {
            XCTFail("Could not load ScreenTimeCore.swift: \(error)")
            return ""
        }
    }

    // MARK: - ContentView range safety

    func testHourLoopGuardsStartLessThanEnd() {
        // The hour-bucketing loop must guard startH < endH before using closed range.
        // Without this guard, events where startH > endH crash with
        // "Range requires lowerBound <= upperBound".
        let src = contentViewSource
        XCTAssertTrue(
            src.contains("} else if startH < endH {") || coreSource.contains("} else if startH < endH {"),
            "Regression: hour-bucketing loop must guard startH < endH before forming startH...endH range (in ContentView or ScreenTimeCore)"
        )
        XCTAssertFalse(
            src.contains("} else {\n                for h in startH..."),
            "Regression: hour-bucketing loop uses unguarded else before startH...endH range"
        )
    }

    func testEventsInRangeGuardsEndAfterStart() {
        // eventsInRange must check t > s before constructing AppEvent.
        let src = contentViewSource
        XCTAssertTrue(
            src.contains("guard t > s else { return nil }") || coreSource.contains("guard t > s else { return nil }"),
            "Regression: eventsInRange must guard against inverted start/end before constructing event (in ContentView or ScreenTimeCore)"
        )
    }

    // MARK: - GanttView range safety

    func testDragSelectionUsesMinMaxBeforeRange() {
        // Drag selection must use min/max to order dates before creating ClosedRange.
        let src = ganttViewSource
        XCTAssertTrue(
            src.contains("let lo = min(s, e)") && src.contains("let hi = max(s, e)"),
            "Regression: drag selection must min/max order dates before forming range"
        )
        XCTAssertTrue(
            src.contains("if hi > lo { onRangeSelected(lo...hi) }"),
            "Regression: drag selection must guard hi > lo before creating ClosedRange"
        )
    }

    func testPersistedSelectionGuardsHiGreaterThanLo() {
        // Persisted selection highlight must check hi > lo before rendering.
        let src = ganttViewSource
        XCTAssertTrue(
            src.contains("if hi > lo {") || src.contains("guard hi > lo"),
            "Regression: persisted selection highlight must guard against inverted range"
        )
    }
}
