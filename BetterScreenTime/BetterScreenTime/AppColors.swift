import SwiftUI

enum AppColors {
    static let palette: [Color] = [
        Color(hex: "#ff6b2b"), Color(hex: "#ff9500"), Color(hex: "#ffd60a"),
        Color(hex: "#30d158"), Color(hex: "#32ade6"), Color(hex: "#5856d6"),
        Color(hex: "#bf5af2"), Color(hex: "#ff375f"), Color(hex: "#00c7be"),
        Color(hex: "#64d2ff"), Color(hex: "#ff9f0a"), Color(hex: "#34c759"),
        Color(hex: "#ff6961"), Color(hex: "#4fc3f7"), Color(hex: "#ce93d8"),
        Color(hex: "#a5d6a7"),
    ]

    static func color(for name: String) -> Color {
        let hash = TimelineColorAllocator.stableHash(name)
        return palette[hash % palette.count]
    }

    static func timelineColorMap(for orderedApps: [String]) -> [String: Color] {
        let indices = TimelineColorAllocator.paletteIndices(for: orderedApps, paletteCount: palette.count)
        var result: [String: Color] = [:]
        result.reserveCapacity(indices.count)
        for (app, index) in indices {
            result[app] = palette[index]
        }
        return result
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8)  & 0xFF) / 255,
            blue:  Double( int        & 0xFF) / 255
        )
    }
}
