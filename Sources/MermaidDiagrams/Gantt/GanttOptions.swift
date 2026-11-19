/**
 * File: GanttOptions.swift
 * ------------------------
 * Layer: Core
 * Description: The options of Gantt charts a diagram's front matter and directives set, as Pele's Gantt renderer reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// The options of Gantt charts the front matter (`config:`, then `gantt:`, in block or flow form) and the `%%{init: …}%%`
/// directives set, a directive's over the front matter's, as Pele's Gantt renderer reads them. A number is kept from its
/// least to its most (a finite number outside them is cut, not refused); any other value leaves the default, which is nil
/// here: a size that follows the diagram's font size, or a padding the chart works out.
public struct GanttOptions: Equatable, Sendable {
    /// `fontSize` and `sectionFontSize`: the size of the tasks' text, from 4 to 72 points, and of the sections' names (the
    /// tasks' size unless it is set).
    public internal(set) var fontSize: Double?
    public internal(set) var sectionFontSize: Double?
    /// `barHeight`, from 4 to 400 points, and `barGap`, the room between two rows' bars, from 0 to 400.
    public internal(set) var barHeight: Double?
    public internal(set) var barGap: Double?
    /// `numberSectionStyles`: how many section styles alternate, from 1 to 1,000, rounded; the even ones are shaded.
    public internal(set) var sectionStyleCount = 4
    /// `leftPadding` and `rightPadding`, from 0 to 2,000 points: the room left of the plot and right of it.
    public internal(set) var leftPadding: Double?
    public internal(set) var rightPadding: Double?
    /// `useWidth`, from 100 to 20,000 points: the width the chart is drawn to, 800 unless it is set.
    public internal(set) var useWidth: Double?
    /// `topPadding` and `gridLineStartPadding`, from 0 to 2,000 points: where the first row starts, and how far above the
    /// first row the grid lines start.
    public internal(set) var topPadding: Double?
    public internal(set) var gridLineStartPadding: Double?
    /// `topAxis: true`: the axis' dates are shown above the tasks too.
    public internal(set) var showsTopAxis = false
    /// `axisFormat` and `tickInterval`, which the chart's own statements of the same name replace.
    public internal(set) var axisFormat: String?
    public internal(set) var tickInterval: String?

    /// The least and most of each number.
    static let textSizeRange = 4.0...72.0
    static let barHeightRange = 4.0...400.0
    static let barGapRange = 0.0...400.0
    static let sectionStyleRange = 1.0...1_000.0
    static let paddingRange = 0.0...2_000.0
    static let useWidthRange = 100.0...20_000.0

    /// Options that set nothing: Pele's defaults.
    public init() {}

    init(_ options: MermaidConfigurationOptions) {
        let values = options.values
        fontSize = Self.number(values["fontSize"], in: Self.textSizeRange)
        sectionFontSize = Self.number(values["sectionFontSize"], in: Self.textSizeRange)
        barHeight = Self.number(values["barHeight"], in: Self.barHeightRange)
        barGap = Self.number(values["barGap"], in: Self.barGapRange)
        if let styles = Self.number(values["numberSectionStyles"], in: Self.sectionStyleRange) { sectionStyleCount = Int((styles + 0.5).rounded(.down)) }
        leftPadding = Self.number(values["leftPadding"], in: Self.paddingRange)
        rightPadding = Self.number(values["rightPadding"], in: Self.paddingRange)
        useWidth = Self.number(values["useWidth"], in: Self.useWidthRange)
        topPadding = Self.number(values["topPadding"], in: Self.paddingRange)
        gridLineStartPadding = Self.number(values["gridLineStartPadding"], in: Self.paddingRange)
        showsTopAxis = values["topAxis"] == .boolean(true)
        if case .text(let format) = values["axisFormat"] { axisFormat = format }
        if case .text(let interval) = values["tickInterval"] { tickInterval = interval }
    }

    /// A finite number cut to `range`; nil for any other value.
    private static func number(_ value: MermaidConfigurationOptions.Value?, in range: ClosedRange<Double>) -> Double? {
        guard case .number(let number) = value, number.isFinite else { return nil }
        return min(range.upperBound, max(range.lowerBound, number))
    }
}
