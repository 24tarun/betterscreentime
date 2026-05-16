import SwiftUI

enum TimelineZoom: String, CaseIterable {
    case activity = "auto"
    case last6h   = "6h"
    case last12h  = "12h"
    case fullDay  = "24h"
}
