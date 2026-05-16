import SwiftUI

struct SidebarView: View {
    let events: [AppEvent]

    private var totals: [(app: String, seconds: Int)] {
        var t: [String: Int] = [:]
        for e in events { t[e.app, default: 0] += e.durationSeconds }
        return t.map { (app: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    private var grandTotal: Int { totals.reduce(0) { $0 + $1.seconds } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("time by app")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(hex: "#3a3a3a"))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            Divider().background(Color(hex: "#1a1a1a"))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    let maxSecs = totals.first?.seconds ?? 1
                    ForEach(totals, id: \.app) { item in
                        AppTotalRow(
                            app: item.app,
                            seconds: item.seconds,
                            maxSeconds: maxSecs,
                            grandTotal: grandTotal
                        )
                    }
                }
                .padding(14)
            }
        }
        .background(Color(hex: "#0d0d0d"))
    }
}

struct AppTotalRow: View {
    let app: String
    let seconds: Int
    let maxSeconds: Int
    let grandTotal: Int

    private var barPct: Double { Double(seconds) / Double(maxSeconds) }
    private var sharePct: Int  { grandTotal > 0 ? Int(Double(seconds) / Double(grandTotal) * 100) : 0 }

    private var formatted: String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(AppColors.color(for: app))
                    .frame(width: 6, height: 6)
                    .shadow(color: AppColors.color(for: app).opacity(0.6), radius: 3)
                Text(app)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hex: "#c8c8c8"))
                    .lineLimit(1)
                Spacer()
                Text(formatted)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(hex: "#505050"))
            }
            HStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#1a1a1a"))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.color(for: app).opacity(0.75))
                            .frame(width: geo.size.width * barPct)
                    }
                }
                .frame(height: 3)
                Text("\(sharePct)%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(hex: "#3a3a3a"))
                    .frame(width: 28, alignment: .trailing)
            }
        }
    }
}
