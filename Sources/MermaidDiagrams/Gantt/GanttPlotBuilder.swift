/**
 * File: GanttPlotBuilder.swift
 * ----------------------------
 * Layer: Core
 * Description: Places a Gantt chart's rows, axis and vertical markers once the chart is scheduled.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics

/// Places a Gantt chart's rows and axis, as Pele's renderer does, once the chart is scheduled: the time scale across
/// the plot, each task's bar or milestone and its text, the axis' dates and grid lines, the section bands and names,
/// the excluded days and today's line. `extent` grows to the right edge of whatever is placed.
struct GanttPlotBuilder<Measurer: DiagramTextMeasuring> {
    let metrics: GanttMetrics
    let scale: GanttTimeScale
    let top: CGFloat
    let bottom: CGFloat
    private(set) var extent: CGFloat
    private(set) var tasks: [GanttLayoutTask] = []
    private(set) var gridLineOffsets: [CGFloat] = []
    private(set) var axisDates: [DiagramTextBlock] = []
    private(set) var verticalMarkers: [GanttVerticalMarker] = []
    /// How many rows of text under the axis the vertical markers' texts take.
    private(set) var verticalMarkerRowCount = 0
    /// Where the grid lines and today's line start: the first row's top, or above it (`gridLineStartPadding`).
    let gridTop: CGFloat
    private let showsTopAxis: Bool
    private let chart: GanttChart
    private let schedule: [GanttSchedule.Entry]
    private let span: GanttTimeSpan
    private let zone: GanttTimeZone
    private let measurers: GanttMeasurers<Measurer>
    private let sections: GanttSectionRows
    private let rows: GanttRowAssignment
    /// The axis' format, read once for every date the axis writes.
    private let compiledAxisFormat: GanttCompiledAxisFormat
    /// The chart's excluded days, as its schedule read them.
    private let excludedDays: GanttExcludedDays

    /// `titleBottom` is where the title ends; `availableWidth` the container's, which narrows the plot (`capWidth`, not under 280).
    init(chart: GanttChart, schedule: [GanttSchedule.Entry], span: GanttTimeSpan, zone: GanttTimeZone, measurers: GanttMeasurers<Measurer>,
         top titleBottom: CGFloat, availableWidth: CGFloat? = nil, excludedDays: GanttExcludedDays) {
        self.chart = chart
        self.schedule = schedule
        self.span = span
        self.zone = zone
        self.measurers = measurers
        self.excludedDays = excludedDays
        let options = chart.options
        metrics = GanttMetrics(rowFontSize: measurers.row.fontSize, axisFontSize: measurers.axis.fontSize, options: options)
        rows = GanttRowAssignment(tasks: chart.tasks, schedule: schedule, isCompact: chart.isCompact)
        sections = GanttSectionRows(rowSections: rows.rowSections, measurer: measurers.section, styleCount: options.sectionStyleCount)
        let axisFormat = chart.axisFormat.isEmpty ? (chart.dateFormat == "D" ? "%d" : options.axisFormat ?? "%Y-%m-%d") : chart.axisFormat
        compiledAxisFormat = GanttCompiledAxisFormat(axisFormat)
        let sampleWidth = [span.start, span.stop].map { [compiledAxisFormat] time in measurers.axis.width(of: compiledAxisFormat.format(time, zone: zone)) }.max() ?? 0
        let left = GanttLayoutEngine.padding + (options.leftPadding.map { padding in CGFloat(padding) }
            ?? max(sections.widestName > 0 ? sections.widestName + GanttLayoutEngine.sectionGap : 0, sampleWidth / 2))
        let rightPadding = options.rightPadding.map { padding in CGFloat(padding) } ?? max(GanttLayoutEngine.minimumRightPadding, sampleWidth / 2)
        let pageWidth = DiagramWidthFitting.capWidth(availableWidth: availableWidth, natural: CGFloat(options.useWidth ?? Double(GanttLayoutEngine.pageWidth)),
                                                     least: GanttLayoutEngine.narrowestPageWidth)
        let plotWidth = max(GanttLayoutEngine.minimumPlotWidth, pageWidth - left - rightPadding - GanttLayoutEngine.padding)
        scale = GanttTimeScale(span: span, left: left, width: plotWidth, rightPadding: rightPadding, axisFormat: axisFormat, sampleWidth: sampleWidth)
        showsTopAxis = chart.showsTopAxis || options.showsTopAxis
        let headHeight = titleBottom + (showsTopAxis ? metrics.tickHeight : 0)
        let plotTop = max(headHeight, options.topPadding.map { padding in CGFloat(padding) } ?? 0)
        top = plotTop
        // Mermaid starts its grid lines above the first row by the difference between these two settings; here that only uses
        // the room a larger `topPadding` leaves free.
        var gridLead: CGFloat = 0
        if let topPadding = options.topPadding, let gridStart = options.gridLineStartPadding {
            gridLead = max(0, min(CGFloat(topPadding - gridStart), plotTop - headHeight))
        }
        gridTop = plotTop - gridLead
        bottom = top + CGFloat(max(rows.rowSections.count, 1)) * metrics.rowHeight
        extent = scale.right + rightPadding
    }

    /// Each task's shape and text, in its row.
    mutating func placeTasks() {
        for (index, task) in chart.tasks.enumerated() {
            guard let row = rows.rowOfTask[index] else { continue }
            var label = oneLineLabel(task)
            let rowMiddle = top + CGFloat(row) * metrics.rowHeight + metrics.rowHeight / 2
            let placed = GanttBarPlacement(task: task, entry: schedule[index], labelWidth: label.size.width, scale: scale, barHeight: metrics.barHeight)
            label.center = CGPoint(x: placed.labelCenter, y: rowMiddle)
            if !placed.isLabelInside { extent = max(extent, placed.labelCenter + label.size.width / 2) }
            tasks.append(GanttLayoutTask(shape: placed.shape(rowMiddle: rowMiddle), paint: GanttTaskPaint(task: task), label: label,
                                         labelColor: placed.labelColor))
        }
    }

    /// The task's text on one line: its lines as written, joined by spaces.
    private func oneLineLabel(_ task: GanttTask) -> DiagramTextBlock {
        let name = DiagramLabelDecoder.label(from: task.name, form: .plain).lines.joined(separator: " ")
        return DiagramTextBlock(label: DiagramLabel(name), measurer: measurers.row, maximumWidth: GanttLayoutEngine.wrappingWidth)
    }

    /// The tasks tagged `vert` that have a start and an end, by their start: a line across the rows at the start, and the text
    /// under the axis, centered on the line but not past the page's padding, on the first row of text where it keeps 8 points
    /// from the texts before it.
    mutating func placeVerticalMarkers() {
        let rowTop = bottom + metrics.tickHeight + GanttLayoutEngine.verticalMarkerGap
        var ends: [CGFloat] = []
        let markers = chart.tasks.indices.filter { index in
            chart.tasks[index].isVertical && schedule[index].start != nil && schedule[index].end != nil
        }.sorted { first, second in (schedule[first].start?.milliseconds ?? 0) < (schedule[second].start?.milliseconds ?? 0) }
        for index in markers {
            guard let start = schedule[index].start else { continue }
            var label = oneLineLabel(chart.tasks[index])
            let offset = scale.offset(of: start)
            let center = max(GanttLayoutEngine.padding + label.size.width / 2, offset)
            var line = 0
            while line < ends.count, center - label.size.width / 2 < ends[line] + GanttLayoutEngine.labelGap { line += 1 }
            if line == ends.count { ends.append(0) }
            ends[line] = center + label.size.width / 2
            extent = max(extent, ends[line])
            label.center = CGPoint(x: center, y: rowTop + CGFloat(line) * metrics.verticalMarkerLineHeight + metrics.verticalMarkerLineHeight / 2)
            verticalMarkers.append(GanttVerticalMarker(offset: offset, label: label))
        }
        verticalMarkerRowCount = ends.count
    }

    /// The axis' grid lines and dates, a date left out where it would run into the one before it or repeat it.
    mutating func placeAxis() {
        let fittingCount = Int((scale.width / (scale.sampleWidth + GanttLayoutEngine.tickSpacing)).rounded(.down))
        let tickCount = min(max(fittingCount, GanttLayoutEngine.tickCountRange.lowerBound), GanttLayoutEngine.tickCountRange.upperBound)
        var lastRight = -CGFloat.greatestFiniteMagnitude
        var lastText = ""
        let intervalLimit = Int((scale.width / GanttLayoutEngine.intervalTickWidth).rounded(.up))
        let ticks = GanttAxisTicks.interval(chart.tickInterval, weekStart: chart.weekStart, from: span.start, to: span.stop, limit: intervalLimit)
            ?? GanttAxisTicks.automatic(from: span.start, to: span.stop, count: tickCount)
        for tick in ticks {
            let offset = scale.offset(of: tick)
            gridLineOffsets.append(offset)
            let text = compiledAxisFormat.format(tick, zone: zone)
            let width = measurers.axis.width(of: text)
            guard offset - width / 2 >= lastRight + GanttLayoutEngine.labelGap, text != lastText else { continue }
            lastRight = offset + width / 2
            lastText = text
            extent = max(extent, lastRight)
            let distance = metrics.tickHeight / 2 + GanttLayoutEngine.axisDateGap
            let middles = [bottom + distance] + (showsTopAxis ? [gridTop - distance] : [])
            for middle in middles {
                var date = DiagramTextBlock(label: DiagramLabel(text), measurer: measurers.axis, maximumWidth: GanttLayoutEngine.wrappingWidth)
                date.center = CGPoint(x: offset, y: middle)
                axisDates.append(date)
            }
        }
    }

    /// The plot, with the section bands across the whole page, the excluded days and today's line.
    func finished(pageWidth: CGFloat, now: GanttTime) -> GanttPlot {
        let (bands, names) = sections.bandsAndNames(top: top, rowHeight: metrics.rowHeight, pageWidth: pageWidth)
        let isTodayShown = chart.todayMarker != .hidden && span.start < span.stop && now >= span.start && now <= span.stop
        let todayStyle: GanttTodayLineStyle?
        if case .styled(let declarations) = chart.todayMarker { todayStyle = GanttTodayLineStyle(declarations: declarations) } else { todayStyle = nil }
        return GanttPlot(frame: CGRect(x: scale.left, y: top, width: scale.width, height: bottom - top), showsTopAxis: showsTopAxis, gridTop: gridTop,
                         verticalMarkers: verticalMarkers, sectionBands: bands, sectionNames: names, excludedDays: excludedDayRuns(),
                         gridLineOffsets: gridLineOffsets, axisDates: axisDates, tasks: tasks, todayOffset: isTodayShown ? scale.offset(of: now) : nil,
                         todayStyle: todayStyle)
    }

    /// The runs of excluded days from the chart's start to its end, each from its first day's midnight to its last
    /// day's end, within the plot; none when the chart spans six years or more.
    private func excludedDayRuns() -> [CGRect] {
        guard !excludedDays.isEmpty, let shadedSpanEnd = span.start.addingMonths(GanttLayoutEngine.excludedDaySpanMonths),
              shadedSpanEnd > span.stop else { return [] }
        var runs: [CGRect] = []
        var run: (first: GanttTime, last: GanttTime)?
        func closeRun() {
            guard let (first, last) = run else { return }
            run = nil
            let left = max(scale.left, scale.offset(of: first.startOfDay))
            let right = min(scale.right, scale.offset(of: GanttTime(milliseconds: last.startOfDay.milliseconds + GanttTime.millisecondsPerDay - 1)))
            if right > left { runs.append(CGRect(x: left, y: top, width: right - left, height: bottom - top)) }
        }
        var day: GanttTime? = span.start
        while let current = day, current <= span.stop {
            if excludedDays.isExcluded(current) { run = (run?.first ?? current, current) } else { closeRun() }
            day = current.addingDays(1)
        }
        closeRun()
        return runs
    }
}

/// The heights of a Gantt chart's rows and axis, from its text sizes, as Pele derives them.
struct GanttMetrics {
    let barHeight: CGFloat
    let rowHeight: CGFloat
    /// The height the axis' dates take below the rows.
    let tickHeight: CGFloat

    /// The height of a row of text under the axis, which the vertical markers' texts stand on.
    let verticalMarkerLineHeight: CGFloat

    static let barHeightScale: CGFloat = 1.85
    /// The gap between rows, as a share of the bar's height.
    static let rowGapShare: CGFloat = 0.25
    static let tickHeightScale: CGFloat = 1.75
    static let verticalMarkerLineScale: CGFloat = 1.5

    /// `options` replace the bar's height and the gap between rows.
    init(rowFontSize: CGFloat, axisFontSize: CGFloat, options: GanttOptions = GanttOptions()) {
        barHeight = options.barHeight.map { height in CGFloat(height) } ?? (rowFontSize * Self.barHeightScale).rounded()
        rowHeight = barHeight + (options.barGap.map { gap in CGFloat(gap) } ?? (barHeight * Self.rowGapShare).rounded())
        tickHeight = (axisFontSize * Self.tickHeightScale).rounded()
        verticalMarkerLineHeight = (rowFontSize * Self.verticalMarkerLineScale).rounded()
    }
}

/// Where a time falls across a Gantt chart's plot.
struct GanttTimeScale {
    let start: GanttTime
    let left: CGFloat
    let width: CGFloat
    /// The axis' format, in d3's specifiers.
    let axisFormat: String
    /// The width of the widest of the axis' first and last dates.
    let sampleWidth: CGFloat
    /// Points per millisecond, or zero when the chart spans no time and everything is at the middle.
    private let pointsPerMillisecond: CGFloat
    let rightPadding: CGFloat

    init(span: GanttTimeSpan, left: CGFloat, width: CGFloat, rightPadding: CGFloat, axisFormat: String, sampleWidth: CGFloat) {
        start = span.start
        self.left = left
        self.width = width
        self.rightPadding = rightPadding
        self.axisFormat = axisFormat
        self.sampleWidth = sampleWidth
        let duration = span.stop.milliseconds - span.start.milliseconds
        pointsPerMillisecond = duration > 0 ? width / CGFloat(duration) : 0
    }

    var right: CGFloat { left + width }

    func offset(of time: GanttTime) -> CGFloat {
        pointsPerMillisecond == 0 ? left + width / 2 : left + CGFloat(time.milliseconds - start.milliseconds) * pointsPerMillisecond
    }
}
