import Foundation

enum TimelineColorAllocator {
    static func stableHash(_ name: String) -> Int {
        var hash = 0
        for scalar in name.unicodeScalars {
            hash = 31 &* hash &+ Int(scalar.value)
        }
        return abs(hash)
    }

    static func paletteIndices(for orderedApps: [String], paletteCount: Int) -> [String: Int] {
        guard paletteCount > 0 else { return [:] }

        var assignment: [String: Int] = [:]
        var previousIndex: Int?

        for app in orderedApps {
            let base = stableHash(app) % paletteCount
            var chosen = base

            if let previousIndex, base == previousIndex {
                for delta in 1..<paletteCount {
                    let plus = (base + delta) % paletteCount
                    if plus != previousIndex {
                        chosen = plus
                        break
                    }

                    let minus = (base - delta + paletteCount) % paletteCount
                    if minus != previousIndex {
                        chosen = minus
                        break
                    }
                }
            }

            assignment[app] = chosen
            previousIndex = chosen
        }

        return assignment
    }
}
