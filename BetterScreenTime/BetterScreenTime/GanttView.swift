import AppKit
import SwiftUI

private let cachedHHmm: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
}()

struct GanttView: View {
    let events: [AppEvent]
    let date: Date
    let zoom: TimelineZoom
    let resetToken: Int
    let selectedRange: ClosedRange<Date>?
    let appOrder: [String]
    let highlightedApp: String?
    let onRangeSelected: ((ClosedRange<Date>) -> Void)?
    let onBlockSelected: ((AppEvent) -> Void)?
    let onHourSelected: ((ClosedRange<Date>) -> Void)?
    let onAppClicked: ((String) -> Void)?
    let onAppReordered: ((String, Int) -> Void)?
    let onClearSelection: (() -> Void)?
    var xRangeOverride: ClosedRange<Date>? = nil
    var minEventDuration: Int = 5
    var bridgeSmallGaps: Bool = false

    init(
        events: [AppEvent],
        date: Date,
        zoom: TimelineZoom,
        resetToken: Int = 0,
        selectedRange: ClosedRange<Date>? = nil,
        appOrder: [String] = [],
        highlightedApp: String? = nil,
        onRangeSelected: ((ClosedRange<Date>) -> Void)? = nil,
        onBlockSelected: ((AppEvent) -> Void)? = nil,
        onHourSelected: ((ClosedRange<Date>) -> Void)? = nil,
        onAppClicked: ((String) -> Void)? = nil,
        onAppReordered: ((String, Int) -> Void)? = nil,
        onClearSelection: (() -> Void)? = nil,
        xRangeOverride: ClosedRange<Date>? = nil,
        minEventDuration: Int = 5,
        bridgeSmallGaps: Bool = false
    ) {
        self.events = events
        self.date = date
        self.zoom = zoom
        self.resetToken = resetToken
        self.selectedRange = selectedRange
        self.appOrder = appOrder.isEmpty ? Array(Set(events.map(\.app))).sorted() : appOrder
        self.highlightedApp = highlightedApp
        self.onRangeSelected = onRangeSelected
        self.onBlockSelected = onBlockSelected
        self.onHourSelected = onHourSelected
        self.onAppClicked = onAppClicked
        self.onAppReordered = onAppReordered
        self.onClearSelection = onClearSelection
        self.xRangeOverride = xRangeOverride
        self.minEventDuration = minEventDuration
        self.bridgeSmallGaps = bridgeSmallGaps
    }

    @State private var hoveredEvent: AppEvent?
    @State private var tooltipPos: CGPoint = .zero
    @State private var dragStartX: CGFloat? = nil
    @State private var dragCurrentX: CGFloat? = nil
    @State private var hoveredHour: DateInterval?
    @State private var didSetInitialScroll = false
    @Environment(\.displayScale) private var displayScale
    @State private var currentWindowStartHour: Double = 0
    @State private var panDragStartHour: Double?
    @State private var windowHours: Double = 6
    @State private var isPointerInsideTimeline = false
    @State private var pointerXInTimeline: CGFloat = 0
    @State private var scrollWheelMonitor: Any?

    private let labelWidth: CGFloat = 160
    private let xAxisHeight: CGFloat = 22
    private let minWindowHours: Double = 1
    private let maxWindowHours: Double = 24

    private var visible: [AppEvent] {
        let base = events.filter { $0.durationSeconds >= minEventDuration }
        guard let highlightedApp else { return base }
        return base.filter { $0.app == highlightedApp }
    }
    private var visibleByApp: [String: [AppEvent]] {
        Dictionary(grouping: visible, by: \.app)
    }
    private var dayStart: Date { Calendar.current.startOfDay(for: date) }
    private var dayEnd: Date { dayStart.addingTimeInterval(86400) }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private func rowHeight(for totalHeight: CGFloat) -> CGFloat {
        let count = CGFloat(max(1, appOrder.count))
        let available = totalHeight - xAxisHeight
        return max(16, available / count)
    }

    private func barHeight(for rh: CGFloat) -> CGFloat {
        min(max(8, rh * 0.82), 72)
    }

    private func labelFontSize(for rh: CGFloat) -> CGFloat {
        min(13, max(10, rh * 0.32))
    }

    private func xFrac(_ d: Date) -> CGFloat {
        let clamped = min(max(d, dayStart), dayEnd)
        return CGFloat(clamped.timeIntervalSince(dayStart) / 86400.0)
    }

    private var hourTicks: [Date] {
        let firstTick = dayStart
        let lastTick = dayEnd
        return stride(
            from: firstTick.timeIntervalSinceReferenceDate,
            through: lastTick.timeIntervalSinceReferenceDate,
            by: 3600
        )
        .map { Date(timeIntervalSinceReferenceDate: $0) }
    }

    private var bundleIdByApp: [String: String] {
        var map: [String: String] = [:]
        for event in events where map[event.app] == nil {
            map[event.app] = event.bundleId
        }
        return map
    }
    private var timelineColorMap: [String: Color] {
        AppColors.timelineColorMap(for: appOrder)
    }

    private func xPos(_ date: Date, chartW: CGFloat) -> CGFloat {
        let raw = xFrac(date) * chartW
        return (raw * 2).rounded() / 2
    }

    private var lineWidth: CGFloat {
        max(1.0 / max(displayScale, 1), 0.5)
    }

    private func snappedX(_ x: CGFloat) -> CGFloat {
        let scale = max(displayScale, 1)
        return (x * scale).rounded() / scale
    }

    private var maxWindowStartHour: Double {
        max(0, 24.0 - windowHours)
    }

    private var initialWindowStartHour: Double {
        let hour = Calendar.current.component(.hour, from: initialScrollTarget)
        let start = Double(hour) - windowHours + 1
        return min(max(0, start), maxWindowStartHour)
    }

    private func clampWindowHours(_ value: Double) -> Double {
        min(max(value, minWindowHours), maxWindowHours)
    }

    private func clampWindowStart(_ value: Double, hours: Double) -> Double {
        min(max(value, 0), max(0, 24 - hours))
    }

    private func zoomBy(scale: Double, anchorX: CGFloat, viewportW: CGFloat) {
        guard viewportW > 0 else { return }
        let oldHours = windowHours
        let nextHours = clampWindowHours(oldHours / scale)
        guard abs(nextHours - oldHours) > 0.001 else { return }

        let anchorFraction = min(max(Double(anchorX / viewportW), 0), 1)
        let anchorHour = currentWindowStartHour + (anchorFraction * oldHours)
        let nextStart = anchorHour - (anchorFraction * nextHours)

        windowHours = nextHours
        currentWindowStartHour = clampWindowStart(nextStart, hours: nextHours)
    }

    var body: some View {
        GeometryReader { geo in
            let rh = rowHeight(for: geo.size.height)
            let viewportW = geo.size.width - labelWidth
            let contentW = max(viewportW * (24.0 / CGFloat(windowHours)), viewportW)
            let availableRowAreaH = max(0, geo.size.height - xAxisHeight)
            let rowAreaH = CGFloat(appOrder.count) * rh
            let xOffset = CGFloat(currentWindowStartHour / 24.0) * contentW
            let needsVerticalScroll = rowAreaH > availableRowAreaH + 0.5

            ZStack(alignment: .topLeading) {
                ScrollView(.vertical, showsIndicators: needsVerticalScroll) {
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(appOrder, id: \.self) { app in
                                appLabel(app: app, rh: rh)
                                    .frame(width: labelWidth, height: rh)
                            }
                            Color.clear.frame(width: labelWidth, height: xAxisHeight)
                        }

                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                ForEach(appOrder, id: \.self) { app in
                                    timelineRow(app: app, rh: rh, chartW: contentW)
                                        .frame(width: contentW, height: rh)
                                        .clipped()
                                }
                                xAxisRow(chartW: contentW)
                                    .frame(width: contentW, height: xAxisHeight)
                            }
                            .offset(x: -xOffset)

                            interactionLayer(
                                rh: rh,
                                chartW: contentW,
                                totalH: rowAreaH,
                                xOffset: xOffset,
                                onPanToHour: { hour in
                                    let clamped = min(max(hour, 0), maxWindowStartHour)
                                    currentWindowStartHour = clamped
                                }
                            )
                            .frame(width: viewportW, height: rowAreaH)
                        }
                        .frame(width: viewportW, height: rowAreaH + xAxisHeight, alignment: .topLeading)
                        .clipped()
                        .onAppear {
                            guard !didSetInitialScroll else { return }
                            didSetInitialScroll = true
                            windowHours = 6
                            currentWindowStartHour = initialWindowStartHour
                            if scrollWheelMonitor == nil {
                                scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                                    guard isPointerInsideTimeline else { return event }
                                    let dx = event.scrollingDeltaX
                                    let dy = event.scrollingDeltaY
                                    if abs(dx) > abs(dy), abs(dx) > 0.01 {
                                        let deltaHours = Double(dx / viewportW) * windowHours
                                        let next = clampWindowStart(currentWindowStartHour - deltaHours, hours: windowHours)
                                        currentWindowStartHour = next
                                        return nil
                                    }
                                    return event
                                }
                            }
                        }
                        .onChange(of: date) { _, _ in
                            didSetInitialScroll = false
                            windowHours = 6
                            currentWindowStartHour = initialWindowStartHour
                            didSetInitialScroll = true
                        }
                        .onChange(of: resetToken) { _, _ in
                            windowHours = 6
                            currentWindowStartHour = initialWindowStartHour
                        }
                        .onDisappear {
                            if let monitor = scrollWheelMonitor {
                                NSEvent.removeMonitor(monitor)
                                scrollWheelMonitor = nil
                            }
                        }
                    }
                    .frame(height: max(rowAreaH + xAxisHeight, geo.size.height))
                }

                if let evt = hoveredEvent {
                    TooltipView(event: evt)
                        .offset(
                            x: min(tooltipPos.x + 14, geo.size.width - 180),
                            y: max(tooltipPos.y - 78, 8)
                        )
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - App label chip

    private func appLabel(app: String, rh: CGFloat) -> some View {
        let fs = labelFontSize(for: rh)
        let icon = bundleIdByApp[app].flatMap { AppIconProvider.icon(for: $0) }
        return HStack {
            HStack(spacing: 5) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 5, height: 5)
                }
                Text(app)
                    .font(.system(size: fs, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 0)
            .padding(.vertical, 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .opacity(highlightedApp == nil || highlightedApp == app ? 1 : 0.28)
        .contentShape(Rectangle())
        .onTapGesture { onAppClicked?(app) }
    }

    // MARK: - Timeline row (blocks only)

    private func bridgedSpans(for events: [AppEvent]) -> [(start: Date, end: Date)] {
        ScreenTimeCore.bridgedSpans(for: events)
    }

    private func timelineRow(app: String, rh: CGFloat, chartW: CGFloat) -> some View {
        let bh = barHeight(for: rh)
        let appEvents = visibleByApp[app] ?? []
        let opacity = highlightedApp == nil || highlightedApp == app ? 1.0 : 0.18
        let baseColor = timelineColorMap[app] ?? AppColors.color(for: app)
        let color = baseColor.opacity(0.88)
        let cr = min(4, bh * 0.3)

        return ZStack(alignment: .leading) {
            Color.clear
            if bridgeSmallGaps {
                let spans = bridgedSpans(for: appEvents)
                ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                    let startF = xFrac(span.start)
                    let endF   = xFrac(span.end)
                    let x      = startF * chartW
                    let w      = (endF - startF) * chartW
                    if w >= 1 {
                        RoundedRectangle(cornerRadius: cr)
                            .fill(color)
                            .frame(width: max(2, w), height: bh)
                            .offset(x: x)
                            .opacity(opacity)
                    }
                }
            } else {
                ForEach(appEvents) { event in
                    let startF = xFrac(event.start)
                    let endF   = xFrac(event.end)
                    let x      = startF * chartW
                    let w      = (endF - startF) * chartW
                    if w >= 1 {
                        RoundedRectangle(cornerRadius: cr)
                            .fill(color)
                            .frame(width: max(2, w), height: bh)
                            .offset(x: x)
                            .opacity(opacity)
                    }
                }
            }
        }
    }

    // MARK: - X axis

    private func xAxisRow(chartW: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Color.clear
            ForEach(hourTicks, id: \.self) { h in
                Text(cachedHHmm.string(from: h))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .monospacedDigit()
                    .offset(x: xPos(h, chartW: chartW))
            }
        }
    }

    // MARK: - Interaction overlay

    private func interactionLayer(
        rh: CGFloat,
        chartW: CGFloat,
        totalH: CGFloat,
        xOffset: CGFloat,
        onPanToHour: @escaping (Double) -> Void
    ) -> some View {
        ZStack(alignment: .topLeading) {
            // Vertical grid lines
            ForEach(hourTicks, id: \.self) { h in
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: lineWidth, height: totalH)
                    .offset(x: snappedX(xPos(h, chartW: chartW) - xOffset))
            }

            // Hovered hour highlight
            if let hour = hoveredHour, dragStartX == nil {
                let lf = xFrac(hour.start)
                let hf = xFrac(hour.end)
                let x  = lf * chartW - xOffset
                let w  = (hf - lf) * chartW
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: w, height: totalH)
                    .offset(x: x)
                    .allowsHitTesting(false)
            }

            // Drag selection
            if let sx = dragStartX, let ex = dragCurrentX {
                let lo = min(sx, ex)
                let hi = max(sx, ex)
                if hi - lo > 3 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.14))
                        .overlay(Rectangle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.8))
                        .frame(width: hi - lo, height: totalH)
                        .offset(x: lo)
                        .allowsHitTesting(false)
                }
            }

            // Persisted selection highlight
            if dragStartX == nil, let sel = selectedRange {
                let lo = max(dayStart, sel.lowerBound)
                let hi = min(dayEnd, sel.upperBound)
                if hi > lo {
                    let x0 = xFrac(lo) * chartW - xOffset
                    let w = (xFrac(hi) - xFrac(lo)) * chartW
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .overlay(Rectangle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.8))
                        .frame(width: max(1, w), height: totalH)
                        .offset(x: x0)
                        .allowsHitTesting(false)
                }
            }

            // Now line
            if isToday {
                let nowF = xFrac(Date())
                if nowF >= 0 && nowF <= 1 {
                    let nowX = nowF * chartW - xOffset
                    Rectangle()
                        .fill(Color(hex: "#FF453A").opacity(0.62))
                        .frame(width: max(1.0, lineWidth), height: totalH)
                        .shadow(color: Color(hex: "#FF453A").opacity(0.22), radius: 2)
                        .offset(x: snappedX(nowX))
                        .allowsHitTesting(false)
                }
            }

            // Gesture capture
            Color.clear.contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if NSEvent.modifierFlags.contains(.shift) { return }
                            guard dragStartX == nil else { return }
                            let dx = value.translation.width
                            let dy = value.translation.height
                            guard abs(dx) > abs(dy) else { return }
                            if panDragStartHour == nil {
                                panDragStartHour = currentWindowStartHour
                            }
                            guard let start = panDragStartHour else { return }
                            let deltaHours = Double(dx / chartW) * 24.0
                            onPanToHour(start - deltaHours)
                        }
                        .onEnded { _ in
                            panDragStartHour = nil
                        }
                )
                .onContinuousHover { phase in
                    guard dragStartX == nil else { return }
                    switch phase {
                    case .active(let loc):
                        isPointerInsideTimeline = true
                        pointerXInTimeline = loc.x
                        let t = dateForX(loc.x + xOffset, chartW: chartW)
                        hoveredHour = Calendar.current.dateInterval(of: .hour, for: t)
                        let rowIdx = Int(loc.y / rh)
                        if rowIdx >= 0 && rowIdx < appOrder.count {
                            let app = appOrder[rowIdx]
                            hoveredEvent = (visibleByApp[app] ?? []).first { $0.start <= t && $0.end >= t }
                            tooltipPos = CGPoint(x: loc.x + labelWidth, y: loc.y)
                        } else {
                            hoveredEvent = nil
                        }
                    case .ended:
                        isPointerInsideTimeline = false
                        hoveredEvent = nil
                        hoveredHour = nil
                    }
                }
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { val in
                        let loc = val.location
                        let t = dateForX(loc.x + xOffset, chartW: chartW)
                        let rowIdx = Int(loc.y / rh)
                        if rowIdx >= 0 && rowIdx < appOrder.count {
                            let app = appOrder[rowIdx]
                            if let evt = (visibleByApp[app] ?? []).first(where: { $0.start <= t && $0.end >= t }) {
                                onBlockSelected?(evt)
                                return
                            }
                        }
                        if let interval = Calendar.current.dateInterval(of: .hour, for: t) {
                            onHourSelected?(interval.start...interval.end)
                        }
                    }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8).modifiers(.shift)
                        .onChanged { val in
                            hoveredEvent = nil
                            dragStartX = val.startLocation.x
                            dragCurrentX = val.location.x
                        }
                        .onEnded { val in
                            defer { dragStartX = nil; dragCurrentX = nil }
                            guard let onRangeSelected else { return }
                            let sx = max(0, Double((val.startLocation.x + xOffset) / chartW))
                            let ex = max(0, Double((val.location.x + xOffset) / chartW))
                            let s = dayStart.addingTimeInterval(sx * 86400)
                            let e = dayStart.addingTimeInterval(ex * 86400)
                            let lo = min(s, e); let hi = max(s, e)
                            if hi > lo { onRangeSelected(lo...hi) }
                        }
                )
                .gesture(TapGesture().modifiers(.control).onEnded { onClearSelection?() })
        }
    }

    private var initialScrollTarget: Date {
        if isToday { return min(Date(), dayEnd) }
        return dayEnd
    }

    private func dateForX(_ x: CGFloat, chartW: CGFloat) -> Date {
        guard chartW > 0 else { return dayStart }
        let fraction = min(max(x / chartW, 0), 1)
        return dayStart.addingTimeInterval(Double(fraction) * 86400)
    }
}

struct TooltipView: View {
    let event: AppEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.app).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.primary)
            Text("\(time(event.start)) → \(time(event.end))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.secondary)
            Text(event.formattedDuration)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemBlue))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1))
    }

    private func time(_ date: Date) -> String {
        cachedHHmm.string(from: date)
    }
}
