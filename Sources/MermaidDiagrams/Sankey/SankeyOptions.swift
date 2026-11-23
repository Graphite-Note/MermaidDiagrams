/**
 * File: SankeyOptions.swift
 * -------------------------
 * Layer: Core
 * Description: A Sankey diagram's options from its front matter and directives, as Pele applies them.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// A Sankey diagram's options from its front matter (`config:` then `sankey:`) and its `%%{init: …}%%` directives, a
/// directive's over the front matter's, as Pele applies them: the chart's
/// size, the nodes' width and the padding between them, whether values are shown with their prefix and suffix, and
/// how nodes are put in columns. A number below its least is left at Pele's default, and one above its most is cut
/// to it. Labels outlined in the page's color (`labelStyle: outlined`), a band color other than the gradient
/// (`linkColor`: `source`, `target` or a color) and nodes' own colors (`nodeColors`, by node name) are drawn as Pele
/// draws them: a color, a CSS color name, or a CSS variable of Pele's palette (`var(--pele-accent)`, `var(--pele-series-3)`,
/// or any variable's fallback), which the page resolves (`DiagramPaint(cssColor:)`); anything else sets nothing, as a
/// browser leaves a style it cannot read.
public struct SankeyOptions: Equatable, Sendable {
    public internal(set) var chartWidth: Double = 600
    public internal(set) var chartHeight: Double = 400
    public internal(set) var nodeWidth: Double = 10
    /// Between two nodes of a column, before the room values add.
    public internal(set) var nodePadding: Double = 12
    /// Whether each label shows its node's value after its name: unless `showValues: false`.
    public internal(set) var showsValues = true
    public internal(set) var valuePrefix = ""
    public internal(set) var valueSuffix = ""
    public internal(set) var alignment = SankeyNodeAlignment.justify
    /// `labelStyle: outlined`: labels outlined in the page's color, and on the side of their bar that faces away from the
    /// chart's fullest column.
    public internal(set) var isOutlined = false
    /// `linkColor`: how the bands are colored.
    public internal(set) var linkColor = SankeyLinkColor.gradient
    /// `nodeColors`: the colors the nodes take instead of their series colors, by the node's name; those written as a
    /// palette's variable are in `nodePaints` only.
    public internal(set) var nodeColors: [String: DiagramColor] = [:]
    /// `nodeColors`: what the nodes are painted in instead of their series colors, colors and palette roles alike.
    public internal(set) var nodePaints: [String: DiagramPaint] = [:]
    /// `linkColor` written as a color or a palette's variable: what every band is painted in; nil for `gradient`,
    /// `source`, `target` and what does not read. `linkColor` is `.fixed` for a color and `.source` for a variable.
    public internal(set) var fixedLinkPaint: DiagramPaint?

    /// The most a chart's side, a node's width and the padding may be: Pele's.
    static let largestChartSide = 10_000.0
    static let largestNodeWidth = 200.0
    static let largestNodePadding = 200.0

    init() {}

    init(_ options: MermaidConfigurationOptions) {
        chartWidth = Self.number(options.values["width"], least: 1, most: Self.largestChartSide) ?? chartWidth
        chartHeight = Self.number(options.values["height"], least: 1, most: Self.largestChartSide) ?? chartHeight
        nodeWidth = min(Self.number(options.values["nodeWidth"], least: 1, most: Self.largestNodeWidth) ?? nodeWidth, chartWidth)
        nodePadding = Self.number(options.values["nodePadding"], least: 0, most: Self.largestNodePadding) ?? nodePadding
        showsValues = options.values["showValues"] != .boolean(false)
        valuePrefix = Self.text(options.values["prefix"])
        valueSuffix = Self.text(options.values["suffix"])
        if case .text(let written) = options.values["nodeAlignment"], let alignment = SankeyNodeAlignment(rawValue: written) { self.alignment = alignment }
        isOutlined = options.values["labelStyle"] == .text("outlined")
        if case .text(let written) = options.values["linkColor"] {
            linkColor = SankeyLinkColor(written)
            if !["gradient", "source", "target"].contains(written) { fixedLinkPaint = DiagramPaint(cssColor: written) }
        }
        nodePaints = Self.nodePaints(options.nestedValues)
        nodeColors = nodePaints.compactMapValues { paint in
            if case .color(let color) = paint.source { return color }
            return nil
        }
    }

    /// The paints under `nodeColors`, by the name written there: a text that reads as a color or a palette's variable; not
    /// an entry that is itself a mapping or has one above it.
    private static func nodePaints(_ nestedValues: [String: MermaidConfigurationOptions.Value]) -> [String: DiagramPaint] {
        let prefix = "nodeColors."
        var colors: [String: DiagramPaint] = [:]
        for (path, value) in nestedValues where path.hasPrefix(prefix) {
            guard case .text(let written) = value, let color = DiagramPaint(cssColor: written) else { continue }
            let name = String(path.dropFirst(prefix.count))
            let isInsideMapping = name.indices.contains { index in
                name[index] == "." && nestedValues[prefix + String(name[..<index])] == .collection
            }
            if !isInsideMapping { colors[name] = color }
        }
        return colors
    }

    private static func number(_ value: MermaidConfigurationOptions.Value?, least: Double, most: Double) -> Double? {
        guard case .number(let number) = value, number >= least else { return nil }
        return min(number, most)
    }

    /// Text, or a finite number written as JavaScript writes it; empty otherwise.
    private static func text(_ value: MermaidConfigurationOptions.Value?) -> String {
        switch value {
        case .text(let written): written
        case .number(let number) where number.isFinite: JavaScriptNumberText.text(number)
        case .number, .boolean, .collection, nil: ""
        }
    }
}

/// How a Sankey diagram's bands are colored (`linkColor`).
public enum SankeyLinkColor: Equatable, Sendable {
    /// From the source's color to the target's, across: Pele's default.
    case gradient
    /// The source's color.
    case source
    /// The target's color.
    case target
    /// One color for every band.
    case fixed(DiagramColor)

    /// What `linkColor: written` stands for: a color in a form that reads, else the source's color, as Pele colors a band
    /// whose `linkColor` is neither of the three words nor a style it accepts.
    init(_ written: String) {
        switch written {
        case "gradient": self = .gradient
        case "source": self = .source
        case "target": self = .target
        default:
            if case .color(let color)? = DiagramPaint(cssColor: written)?.source { self = .fixed(color) } else { self = .source }
        }
    }
}

/// How a Sankey diagram's nodes are put in columns (`nodeAlignment`).
public enum SankeyNodeAlignment: String, Equatable, Sendable {
    /// Each node in the column of its longest distance from a source, and nodes with no flow out in the last column.
    case justify
    /// Each node in the column of its longest distance from a source.
    case left
    /// Each node as many columns before the last as its longest distance to a node with no flow out.
    case right
    /// As `left`, but a source moves up to the column before its nearest target.
    case center
}
