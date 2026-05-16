import SwiftUI
import Charts

private enum SelectionState {
    case none
    case app(String)
    case block(AppEvent)
    case range(ClosedRange<Date>)
}

private enum CachedFormatters {
    static let eeeMMd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()
    static let hmmA: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mma"; return f
    }()
    static let HHmm: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }()
}

struct ContentView: View {
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @AppStorage("bridgeSmallGaps") private var bridgeSmallGaps: Bool = false
    @State private var events: [AppEvent] = []
    @State private var selectedDate = Date()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selection: SelectionState = .none
    @State private var legendSelectedApp: String?
    @State private var orderedApps: [String] = []
    @State private var pendingOrderApp: String?
    @State private var rightClickMonitor: Any?
    @State private var timelineResetToken: Int = 0
    @State private var loadTask: Task<Void, Never>?
    @State private var totalsCache: [(app: String, seconds: Int)] = []
    @State private var totalSecondsCache: Int = 0
    @State private var hourlySlicesCache: [HourSlice] = []
    @State private var maxHourlySecondsCache: Double = 0

    private let db = KnowledgeDB()
    private let orderKey = "customAppOrder"
    private let accentBlue = Color(nsColor: .systemBlue)

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var totals: [(app: String, seconds: Int)] { totalsCache }
    private var totalSeconds: Int { totalSecondsCache }
    private var hourlySlices: [HourSlice] { hourlySlicesCache }
    private var appOrder: [String] {
        let base = totals.map { $0.app }
        let custom = orderedApps.filter { base.contains($0) }
        let rest = base.filter { !custom.contains($0) }
        return custom + rest
    }

    var body: some View {
        VStack(spacing: 6) {
            topBar

            if let error = errorMessage {
                errorScreen(error)
            } else {
                GeometryReader { geo in
                    let topSectionHeight = geo.size.height * 0.40
                    let navHeight: CGFloat = 34
                    let panelHeight = max(0, topSectionHeight - navHeight - 8)

                    VStack(spacing: 0) {
                        VStack(spacing: 8) {
                            HStack(alignment: .top, spacing: 16) {
                                panelCard(leftPanel, height: panelHeight)
                                panelCard(rightPanel, height: panelHeight)
                            }
                            .frame(height: panelHeight)

                            navBar
                                .frame(height: navHeight)
                        }
                        .frame(height: topSectionHeight, alignment: .top)

                        GanttView(
                            events: events,
                            date: selectedDate,
                            zoom: .fullDay,
                            resetToken: timelineResetToken,
                            selectedRange: selectedTimelineRange,
                            appOrder: appOrder,
                            highlightedApp: legendSelectedApp,
                            onRangeSelected: { selection = .range($0) },
                            onBlockSelected: { selection = .block($0) },
                            onHourSelected: { selection = .range($0) },
                            onAppClicked: { app in
                                selection = .app(app)
                                legendSelectedApp = (legendSelectedApp == app) ? nil : app
                            },
                            onAppReordered: { app, to in
                                var current = appOrder
                                guard let fromIdx = current.firstIndex(of: app) else { return }
                                current.remove(at: fromIdx)
                                current.insert(app, at: min(to, current.count))
                                orderedApps = current
                                pendingOrderApp = app
                            },
                            onClearSelection: clearSelection,
                            bridgeSmallGaps: bridgeSmallGaps
                        )
                        .frame(height: geo.size.height - topSectionHeight)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .onTapGesture { clearSelection() }
        .preferredColorScheme(preferredScheme)
        .onAppear {
            loadSavedOrder()
            load()
            rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
                clearSelection()
                return event
            }
        }
        .onDisappear {
            if let m = rightClickMonitor { NSEvent.removeMonitor(m) }
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: selectedDate) { _, _ in load() }
        .onChange(of: events) { _, newEvents in
            let agg = ScreenTimeCore.computeAggregates(from: newEvents)
            totalsCache = agg.totals
            totalSecondsCache = agg.totalSeconds
            hourlySlicesCache = agg.hourlySlices
            maxHourlySecondsCache = agg.maxHourlySeconds
        }
        .onKeyPress(.leftArrow)  { navigate(-1); return .handled }
        .onKeyPress(.rightArrow) { navigate(1);  return .handled }
        .overlay(alignment: .bottom) {
            if let app = pendingOrderApp {
                HStack(spacing: 10) {
                    Text("Remember position for \(app)?")
                        .font(.system(size: 12, weight: .medium))
                    Button("Yes") {
                        saveOrder()
                        pendingOrderApp = nil
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accentBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    Button("No") {
                        loadSavedOrder()
                        pendingOrderApp = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 8)
            }
        }
        .simultaneousGesture(
            TapGesture().modifiers(.control).onEnded { clearSelection() }
        )
    }

    // MARK: - Top bar (minimal)

    private var topBar: some View {
        HStack {
            Spacer()
            if isLoading { ProgressView().scaleEffect(0.6) }
        }
        .frame(height: isLoading ? 8 : 0)
    }

    // MARK: - Nav bar (replaces zoom bar)

    private var navBar: some View {
        HStack(spacing: 12) {
            Spacer()

            HStack(spacing: 12) {
                iconBtn("chevron.left") { navigate(-1) }

                Text(dateNavLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                iconBtn("chevron.right") { navigate(1) }
                    .opacity(isToday ? 0.3 : 1)
                    .disabled(isToday)

                iconBtn("arrow.clockwise") {
                    clearSelection()
                    load()
                }
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func iconBtn(_ system: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    private var dateNavLabel: String {
        CachedFormatters.eeeMMd.string(from: selectedDate)
    }

    // MARK: - Actions

    private func clearSelection() {
        selection = .none
        legendSelectedApp = nil
        timelineResetToken += 1
    }

    private func navigate(_ days: Int) {
        if days > 0 && isToday { return }
        clearSelection()
        selectedDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
    }

    private func load() {
        loadTask?.cancel()
        loadTask = Task {
            isLoading = true
            errorMessage = nil
            do {
                let fetched = try await db.fetchEvents(for: selectedDate)
                guard !Task.isCancelled else { return }
                events = fetched
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                events = []
            }
            guard !Task.isCancelled else { return }
            isLoading = false
        }
    }

    private func loadSavedOrder() {
        orderedApps = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
    }

    private func saveOrder() {
        UserDefaults.standard.set(orderedApps, forKey: orderKey)
    }

    private func recomputeAggregates() {
        let agg = ScreenTimeCore.computeAggregates(from: events)
        totalsCache = agg.totals
        totalSecondsCache = agg.totalSeconds
        hourlySlicesCache = agg.hourlySlices
        maxHourlySecondsCache = agg.maxHourlySeconds
    }

    // MARK: - Left panel (flat, no container)

    private func panelCard<Content: View>(_ content: Content, height: CGFloat) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 8)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.9), lineWidth: 1)
            )
    }

    private var leftPanel: some View {
        GeometryReader { geo in
            let chartHeight = max(72, geo.size.height * 0.45)

            Group {
                switch selection {
                case .none:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SCREEN TIME").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                        Text(formatHM(totalSeconds)).font(.system(size: 42, weight: .bold)).tracking(-0.8).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                        Spacer(minLength: 2)
                        hourlyBarChart.frame(height: chartHeight)
                    }
                case .app, .block, .range:
                    switchTimeline(for: selectedEvents())
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private func switchTimeline(for selected: [AppEvent]) -> some View {
        let sorted = selected.sorted { $0.start < $1.start }
        let maxDuration = sorted.map(\.durationSeconds).max() ?? 1

        return VStack(alignment: .leading, spacing: 0) {
            Text("APP SWITCHES").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.bottom, 6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(sorted) { event in
                        HStack(spacing: 6) {
                            Text("\(CachedFormatters.HHmm.string(from: event.start))–\(CachedFormatters.HHmm.string(from: event.end))")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)

                            if let bid = bundleId(forApp: event.app),
                               let icon = AppIconProvider.icon(for: bid) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 14, height: 14)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            }

                            Text(event.app)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                                .frame(width: 80, alignment: .leading)

                            GeometryReader { bar in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppColors.color(for: event.app).opacity(0.8))
                                    .frame(width: max(2, bar.size.width * CGFloat(Double(event.durationSeconds) / Double(max(1, maxDuration)))))
                            }
                            .frame(height: 10)

                            Text(event.formattedDuration)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                        .frame(height: 20)
                    }
                }
            }
        }
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 10) {
                switch selection {
                case .none:
                    topAppSpotlight
                        .frame(maxHeight: .infinity, alignment: .top)
                case .block(let e):
                    Text("Session Detail").font(.system(size: 12, weight: .semibold))
                    Text(e.app).font(.system(size: 20, weight: .bold))
                    Text("\(timeLabel(e.start))–\(timeLabel(e.end))").font(.system(size: 13)).foregroundStyle(.secondary)
                    Text(e.formattedDuration).font(.system(size: 34, weight: .bold)).monospacedDigit()
                    durationMeter(seconds: min(e.durationSeconds, 3600))
                case .app(let app):
                    let appEvents = events.filter { $0.app == app }
                    let seconds = appEvents.reduce(0) { $0 + $1.durationSeconds }
                    Text("App Detail").font(.system(size: 12, weight: .semibold))
                    Text(app).font(.system(size: 24, weight: .bold))
                    statCard(formatHM(seconds), "total")
                case .range(let r):
                    let active = eventsInRange(r)
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(timeLabel(r.lowerBound))–\(timeLabel(r.upperBound))")
                            .font(.system(size: 18, weight: .bold))
                        Spacer()
                        Text("active \(formatHM(active.reduce(0) { $0 + $1.durationSeconds }))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(topApps(active), id: \.app) { item in
                        HStack {
                            if let bundleId = bundleId(forApp: item.app),
                               let icon = AppIconProvider.icon(for: bundleId) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 16, height: 16)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            } else {
                                Circle()
                                    .fill(AppColors.color(for: item.app))
                                    .frame(width: 7, height: 7)
                            }
                            Text(item.app).font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(formatHM(item.seconds)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: max(0, geo.size.height * 0.02))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .clipped()
    }

    private var topAppSpotlight: some View {
        let sorted = totals.prefix(3)
        let safeTotal = max(1, totalSeconds)

        return VStack(alignment: .leading, spacing: 0) {
            Text("TOP APPS").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.bottom, 8)
            if let top = sorted.first {
                let pct = Int(Double(top.seconds) / Double(safeTotal) * 100)
                HStack(spacing: 10) {
                    if let bid = bundleId(forApp: top.app),
                       let icon = AppIconProvider.icon(for: bid) {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(top.app)
                            .font(.system(size: 18, weight: .bold))
                            .lineLimit(1)
                        Text("\(formatHM(top.seconds)) · \(pct)%")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 12)

                GeometryReader { bar in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.color(for: top.app).opacity(0.3))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppColors.color(for: top.app))
                                .frame(width: bar.size.width * CGFloat(Double(top.seconds) / Double(safeTotal)))
                        }
                }
                .frame(height: 8)
                .padding(.bottom, 14)
            }

            ForEach(Array(sorted.dropFirst()), id: \.app) { item in
                let pct = Int(Double(item.seconds) / Double(safeTotal) * 100)
                HStack(spacing: 8) {
                    if let bid = bundleId(forApp: item.app),
                       let icon = AppIconProvider.icon(for: bid) {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(item.app)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(formatHM(item.seconds)) · \(pct)%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
        }
    }

    private func ringPanel(showLegend: Bool = true) -> some View {
        let selected = selectedEvents()
        let total = selected.reduce(0) { $0 + $1.durationSeconds }
        let safeTotal = max(1, total)
        let items = topApps(selected, limit: 4)
        let maxRadius: CGFloat = showLegend ? 56 : 150
        let ringGap: CGFloat = showLegend ? 10 : 24
        let ringLineWidth: CGFloat = showLegend ? 6 : 14
        return VStack(spacing: 10) {
            ZStack {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    let radius = max(20, maxRadius - CGFloat(idx) * ringGap)
                    Circle().stroke(Color.secondary.opacity(0.2), lineWidth: ringLineWidth).frame(width: radius, height: radius)
                    Circle().trim(from: 0, to: CGFloat(Double(item.seconds) / Double(safeTotal)))
                        .stroke(AppColors.color(for: item.app), style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: radius, height: radius)
                }
                Text(formatHM(total))
                    .font(.system(size: showLegend ? 12 : 28, weight: .bold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            if showLegend {
                ForEach(items, id: \.app) { item in
                    HStack(spacing: 6) {
                        Circle().fill(AppColors.color(for: item.app)).frame(width: 6, height: 6)
                        Text(item.app).font(.system(size: 10)).lineLimit(1)
                        Spacer()
                        Text(formatHM(item.seconds)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func selectedEvents() -> [AppEvent] {
        switch selection {
        case .none: return events
        case .app(let app): return events.filter { $0.app == app }
        case .block(let e): return events.filter { $0.app == e.app && $0.start == e.start && $0.end == e.end }
        case .range(let r): return eventsInRange(r)
        }
    }

    private var selectedTimelineRange: ClosedRange<Date>? {
        if case let .range(r) = selection { return r }
        return nil
    }

    private func eventsInRange(_ range: ClosedRange<Date>) -> [AppEvent] {
        ScreenTimeCore.events(in: range, from: events)
    }

    private func topApps(_ input: [AppEvent], limit: Int = 5) -> [(app: String, seconds: Int)] {
        ScreenTimeCore.topApps(from: input, limit: limit)
    }

    private func bundleId(forApp app: String) -> String? {
        events.first(where: { $0.app == app })?.bundleId
    }

    private func durationMeter(seconds: Int) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.2))
                RoundedRectangle(cornerRadius: 5).fill(accentBlue).frame(width: geo.size.width * CGFloat(Double(seconds) / 3600.0))
            }
        }
        .frame(height: 8)
    }

    private func statCard(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 40, weight: .bold)).tracking(-0.6).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
            Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var hourlyBarChart: some View {
        Chart(hourlySlices) { slice in
            BarMark(
                x: .value("Hour", slice.hour),
                y: .value("Seconds", slice.seconds),
                width: .fixed(6)
            )
            .foregroundStyle(AppColors.color(for: slice.app).opacity(0.9))
            .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                AxisValueLabel {
                    if let h = value.as(Int.self) {
                        let label = String(format: "%02d", h % 24)
                        Text(label)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxisTickValues) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel {
                    if let secs = value.as(Double.self) {
                        Text(yAxisLabel(for: secs))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXScale(domain: 0...24)
        .chartYScale(domain: 0...max(yAxisTickValues.last ?? 3600, 1800))
        .chartPlotStyle { $0.background(Color.clear) }
    }

    private var maxHourlySeconds: Double {
        maxHourlySecondsCache
    }

    private var yAxisStepSeconds: Double {
        if totalSeconds < 3600 { return 900 }      // 15m when total day usage is < 1h
        if maxHourlySeconds > 1800 { return 3600 } // 1h
        return 1800                                // 30m
    }

    private var yAxisTickValues: [Double] {
        let step = yAxisStepSeconds
        let maxVal = max(maxHourlySeconds, step)
        let top = ceil(maxVal / step) * step
        let ticks = stride(from: 0.0, through: top, by: step).map { $0 }
        return ticks.isEmpty ? [0, step] : ticks
    }

    private func yAxisLabel(for seconds: Double) -> String {
        if seconds == 0 { return "0m" }
        let mins = Int(seconds / 60)
        if mins % 60 == 0 { return "\(mins / 60)h" }
        return "\(mins)m"
    }

    private var currentHourPosition: Double? {
        guard isToday else { return nil }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        guard let hour = comps.hour, let minute = comps.minute else { return nil }
        return Double(hour) + (Double(minute) / 60.0)
    }

    private func formatHM(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func dateLabel(_ date: Date) -> String {
        CachedFormatters.eeeMMd.string(from: date)
    }

    private func timeLabel(_ date: Date) -> String {
        CachedFormatters.hmmA.string(from: date).lowercased()
    }

    private func errorScreen(_ msg: String) -> some View {
        let isPermissionIssue = msg.localizedCaseInsensitiveContains("permission")
            || msg.localizedCaseInsensitiveContains("Cannot copy DB")
            || msg.localizedCaseInsensitiveContains("knowledgeC.db")

        return VStack(spacing: 14) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color(hex: "#FF453A"))

            if isPermissionIssue {
                Text("To gain access to local Screen Time data, BetterScreenTime needs access to knowledgeC.db on your Mac. Please enable Full Disk Access for BetterScreenTime using the toggle below.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Text("BetterScreenTime.app")
                            .font(.system(size: 13, weight: .semibold))

                        Spacer()

                        ZStack(alignment: .trailing) {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.9))
                                .frame(width: 44, height: 26)
                            Circle()
                                .fill(.white)
                                .frame(width: 22, height: 22)
                                .padding(.trailing, 2)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: 560)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                )
                .padding(.horizontal, 24)
            } else {
                Text(msg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Text("Then open Full Disk Access settings and add BetterScreenTime if it is not listed.")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Open System Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                )
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }
}
