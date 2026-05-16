import Foundation

struct AppEvent: Identifiable, Equatable {
    let id = UUID()
    let app: String
    let bundleId: String
    let start: Date
    let end: Date

    nonisolated var durationSeconds: Int { Int(end.timeIntervalSince(start)) }

    nonisolated var formattedDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        let s = durationSeconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}
