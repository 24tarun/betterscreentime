import Foundation

struct HourSlice: Identifiable, Equatable {
    var id: String { "\(hour)-\(bundleId)" }
    let hour: Int
    let app: String
    let bundleId: String
    let seconds: Double
}

struct AggregateResult: Sendable {
    let totals: [(app: String, seconds: Int)]
    let totalSeconds: Int
    let hourlySlices: [HourSlice]
    let maxHourlySeconds: Double
}

enum ScreenTimeCore {
    static func computeAggregates(from events: [AppEvent], calendar: Calendar = .current) -> AggregateResult {
        var t: [String: Int] = [:]
        for e in events { t[e.app, default: 0] += e.durationSeconds }
        let totals = t.map { (app: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
        let totalSeconds = totals.reduce(0) { $0 + $1.seconds }

        var hourBuckets: [Int: [(app: String, seconds: Double, bundleId: String)]] = [:]
        for event in events {
            let startH = calendar.component(.hour, from: event.start)
            let endH = calendar.component(.hour, from: event.end)
            if startH == endH {
                hourBuckets[startH, default: []].append((event.app, Double(event.durationSeconds), event.bundleId))
            } else if startH < endH {
                for h in startH...min(endH, 23) {
                    let hStart = calendar.date(bySettingHour: h, minute: 0, second: 0, of: event.start)!
                    let hEnd = hStart.addingTimeInterval(3600)
                    let overlapStart = max(event.start, hStart)
                    let overlapEnd = min(event.end, hEnd)
                    let secs = overlapEnd.timeIntervalSince(overlapStart)
                    if secs > 0 {
                        hourBuckets[h, default: []].append((event.app, secs, event.bundleId))
                    }
                }
            }
        }

        var slices: [HourSlice] = []
        for (h, items) in hourBuckets {
            var merged: [String: (seconds: Double, bundleId: String)] = [:]
            for item in items {
                let existing = merged[item.app]
                merged[item.app] = (seconds: (existing?.seconds ?? 0) + item.seconds, bundleId: item.bundleId)
            }
            for (app, val) in merged {
                slices.append(HourSlice(hour: h, app: app, bundleId: val.bundleId, seconds: val.seconds))
            }
        }
        slices.sort {
            if $0.hour != $1.hour { return $0.hour < $1.hour }
            return $0.bundleId < $1.bundleId
        }
        var byHour: [Int: Double] = [:]
        for slice in slices { byHour[slice.hour, default: 0] += slice.seconds }
        let maxH = byHour.values.max() ?? 0

        return AggregateResult(totals: totals, totalSeconds: totalSeconds, hourlySlices: slices, maxHourlySeconds: maxH)
    }

    static func events(in range: ClosedRange<Date>, from events: [AppEvent]) -> [AppEvent] {
        events.compactMap { e in
            let s = max(e.start, range.lowerBound)
            let t = min(e.end, range.upperBound)
            guard t > s else { return nil }
            return AppEvent(app: e.app, bundleId: e.bundleId, start: s, end: t)
        }
    }

    static func topApps(from input: [AppEvent], limit: Int = 5) -> [(app: String, seconds: Int)] {
        var t: [String: Int] = [:]
        for e in input { t[e.app, default: 0] += e.durationSeconds }
        return t.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }.prefix(limit).map { $0 }
    }

    static func bridgedSpans(for events: [AppEvent], gapSeconds: TimeInterval = 300) -> [(start: Date, end: Date)] {
        let sorted = events.sorted { $0.start < $1.start }
        guard let first = sorted.first else { return [] }
        var spans: [(start: Date, end: Date)] = []
        var curStart = first.start
        var curEnd = first.end
        for event in sorted.dropFirst() {
            if event.start.timeIntervalSince(curEnd) < gapSeconds {
                curEnd = max(curEnd, event.end)
            } else {
                spans.append((curStart, curEnd))
                curStart = event.start
                curEnd = event.end
            }
        }
        spans.append((curStart, curEnd))
        return spans
    }

    static func mergeAdjacentEvents(_ events: [AppEvent], maxGapSeconds: TimeInterval = 2) -> [AppEvent] {
        guard !events.isEmpty else { return [] }
        let sorted = events.sorted { $0.start < $1.start }
        var currentByBundle: [String: AppEvent] = [:]
        var merged: [AppEvent] = []
        for nxt in sorted {
            let key = nxt.bundleId
            if let cur = currentByBundle[key] {
                if nxt.start.timeIntervalSince(cur.end) < maxGapSeconds {
                    currentByBundle[key] = AppEvent(
                        app: cur.app,
                        bundleId: cur.bundleId,
                        start: cur.start,
                        end: max(cur.end, nxt.end)
                    )
                } else {
                    merged.append(cur)
                    currentByBundle[key] = nxt
                }
            } else {
                currentByBundle[key] = nxt
            }
        }
        for (_, cur) in currentByBundle {
            merged.append(cur)
        }
        return merged.sorted { $0.start < $1.start }
    }

    static func filterQualifiedBundles(_ events: [AppEvent], minimumTotalSeconds: Int = 60) -> [AppEvent] {
        var totals: [String: Int] = [:]
        for e in events { totals[e.bundleId, default: 0] += Int(e.end.timeIntervalSince(e.start)) }
        let qualified = Set(totals.filter { $0.value >= minimumTotalSeconds }.keys)
        return events.filter { qualified.contains($0.bundleId) }
    }
}
