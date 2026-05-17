import XCTest
@testable import BetterScreenTimeCore

final class TimelineColorAllocatorTests: XCTestCase {
    func testPaletteIndicesAreDeterministic() {
        let apps = ["Brave", "VS Code", "Slack", "Terminal", "Music"]
        let first = TimelineColorAllocator.paletteIndices(for: apps, paletteCount: 16)
        let second = TimelineColorAllocator.paletteIndices(for: apps, paletteCount: 16)
        XCTAssertEqual(first, second)
    }

    func testAvoidsAdjacentCollisionsWhenPossible() {
        let apps = ["Brave", "VS Code", "Slack", "Terminal", "Music", "Mail", "Notes"]
        let map = TimelineColorAllocator.paletteIndices(for: apps, paletteCount: 16)

        for i in 1..<apps.count {
            let prev = map[apps[i - 1]]
            let cur = map[apps[i]]
            XCTAssertNotNil(prev)
            XCTAssertNotNil(cur)
            XCTAssertNotEqual(prev, cur, "Adjacent apps should not share a color index when palette allows it.")
        }
    }

    func testBestEffortWithSingleColorPalette() {
        let apps = ["Brave", "VS Code", "Slack"]
        let map = TimelineColorAllocator.paletteIndices(for: apps, paletteCount: 1)
        XCTAssertEqual(map["Brave"], 0)
        XCTAssertEqual(map["VS Code"], 0)
        XCTAssertEqual(map["Slack"], 0)
    }

    func testOrderSensitiveButStablePerOrder() {
        let appsA = ["Brave", "VS Code", "Slack", "Terminal"]
        let appsB = ["VS Code", "Brave", "Slack", "Terminal"]

        let mapA1 = TimelineColorAllocator.paletteIndices(for: appsA, paletteCount: 16)
        let mapA2 = TimelineColorAllocator.paletteIndices(for: appsA, paletteCount: 16)
        let mapB = TimelineColorAllocator.paletteIndices(for: appsB, paletteCount: 16)

        XCTAssertEqual(mapA1, mapA2)
        XCTAssertNotEqual(mapA1, mapB)
    }
}
