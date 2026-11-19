/**
 * File: TreemapOptions.swift
 * --------------------------
 * Layer: Core
 * Description: The options of a treemap its front matter (`config:`, `treemap:`) and its directives set.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The options of treemaps a diagram's front matter (`config:`, then `treemap:`) and its `%%{init: …}%%` directives set, a
/// directive's over the front matter's. A number below its least, or of the wrong kind, is left at its default; one above
/// its largest is cut to it, as Pele reads them.
public struct TreemapOptions: Equatable, Sendable {
    /// `nodeWidth` and `nodeHeight`: a tenth of the treemap's width and height, 1 to 400 points (as Mermaid sizes it, ten
    /// nodes across and ten down).
    public internal(set) var nodeWidth: CGFloat = 64
    public internal(set) var nodeHeight: CGFloat = 40
    /// `diagramPadding`: the room around the treemap, 0 to 2000 points.
    public internal(set) var diagramPadding: CGFloat = 8
    /// `padding`: the gap between boxes, 0 to 200 points; nil for the one that follows the boxes' size, 2 to 4.
    public internal(set) var boxGap: CGFloat?
    /// `showValues`: whether values are written in the boxes.
    public internal(set) var showsValues = true
    /// `valueFormat`: a d3-format specifier for the values written (`,` unless it says otherwise).
    public internal(set) var valueFormat = ","

    /// Options that set nothing.
    public init() {}

    init(_ options: MermaidConfigurationOptions) {
        nodeWidth = CGFloat(options.boundedNumber("nodeWidth", fallback: 64, least: 1, largest: 400))
        nodeHeight = CGFloat(options.boundedNumber("nodeHeight", fallback: 40, least: 1, largest: 400))
        diagramPadding = CGFloat(options.boundedNumber("diagramPadding", fallback: 8, least: 0, largest: 2_000))
        if case .number(let written) = options.values["padding"], written >= 0 { boxGap = CGFloat(min(written, 200)) }
        if case .boolean(false) = options.values["showValues"] { showsValues = false }
        if case .text(let specifier) = options.values["valueFormat"] { valueFormat = specifier }
    }
}
