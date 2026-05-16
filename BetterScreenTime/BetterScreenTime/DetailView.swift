import SwiftUI
import Charts

struct DetailView: View {
    let events: [AppEvent]
    let range: ClosedRange<Date>
    @Environment(\.dismiss) private var dismiss

    private var filtered: [AppEvent] {
        events.compactMap { event in
            let s = max(event.start, range.lowerBound)
            let e = min(event.end, range.upperBound)
            guard e > s else { return nil }
            return AppEvent(app: event.app, bundleId: event.bundleId, start: s, end: e)
        }
    }

    private var totals: [(app: String, seconds: Int)] {
        var t: [String: Int] = [:]
        for e in filtered { t[e.app, default: 0] += e.durationSeconds }
        return t.map { (app: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    private let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()

    private var rangeLabel: String {
        "\(timeFmt.string(from: range.lowerBound)) → \(timeFmt.string(from: range.upperBound))"
    }

    private var durationLabel: String {
        let secs = Int(range.upperBound.timeIntervalSince(range.lowerBound))
        let h = secs / 3600; let m = (secs % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rangeLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("\(durationLabel) · \(totals.count) app\(totals.count == 1 ? "" : "s")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("✕") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider().overlay(Color(nsColor: .separatorColor))

            if filtered.isEmpty {
                VStack {
                    Spacer()
                    Text("no activity in this window")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("breakdown")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 14)

                        Chart(totals, id: \.app) { item in
                            SectorMark(
                                angle: .value("Time", item.seconds),
                                innerRadius: .ratio(0.55),
                                angularInset: 1.5
                            )
                            .foregroundStyle(AppColors.color(for: item.app))
                            .cornerRadius(3)
                        }
                        .frame(width: 140, height: 140)
                        .padding(.leading, 28)

                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 9) {
                                ForEach(totals, id: \.app) { item in
                                    HStack(spacing: 7) {
                                        Circle()
                                            .fill(AppColors.color(for: item.app))
                                            .frame(width: 6, height: 6)
                                        Text(item.app)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(fmt(item.seconds))
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 14)
                            .padding(.bottom, 16)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(width: 210)

                    Divider().overlay(Color(nsColor: .separatorColor))

                    VStack(alignment: .leading, spacing: 0) {
                        Text("timeline")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 4)

                        GanttView(
                            events: filtered,
                            date: range.lowerBound,
                            zoom: .fullDay,
                            onRangeSelected: nil,
                            xRangeOverride: range,
                            minEventDuration: 5
                        )
                    }
                }
            }
        }
        .frame(minWidth: 740, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func fmt(_ s: Int) -> String {
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }
}
