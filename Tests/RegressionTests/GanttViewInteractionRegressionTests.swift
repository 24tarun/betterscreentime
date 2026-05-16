import XCTest

final class GanttViewInteractionRegressionTests: XCTestCase {
    private var ganttSource: String {
        let path = "/Users/tarun/Desktop/coding/betterscreentime/BetterScreenTime/BetterScreenTime/GanttView.swift"
        do {
            return try String(contentsOfFile: path)
        } catch {
            XCTFail("Could not load GanttView.swift: \(error)")
            return ""
        }
    }

    func testDoesNotUseBlockingWheelOverlayView() {
        XCTAssertFalse(
            ganttSource.contains("ScrollWheelCaptureView"),
            "Regression: wheel-capture overlay blocked hover/click interactions on timeline."
        )
        XCTAssertFalse(
            ganttSource.contains("WheelCaptureNSView"),
            "Regression: NSView overlay catcher blocked timeline hit testing."
        )
    }

    func testTimelineStillContainsHoverAndTapInteractionHooks() {
        XCTAssertTrue(
            ganttSource.contains(".onContinuousHover"),
            "Timeline hover interaction hook is missing."
        )
        XCTAssertTrue(
            ganttSource.contains("SpatialTapGesture"),
            "Timeline tap interaction hook is missing."
        )
        XCTAssertTrue(
            ganttSource.contains("DragGesture(minimumDistance: 8).modifiers(.shift)"),
            "Timeline shift-drag range selection hook is missing."
        )
    }
}
