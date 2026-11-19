/**
 * File: RadarAppearance.swift
 * ---------------------------
 * Layer: Core
 * Description: The options of a radar chart its front matter (`config:`, `radar:`) and its directives set.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The options of radar charts a diagram's front matter (`config:`, then `radar:`) and its `%%{init: …}%%` directives set,
/// a directive's over the front matter's: the size of the chart, the room around it, and where the axes' labels and the
/// curves' corners stand. A number below its least, or of the wrong kind, is left at its default; one above its largest
/// is cut to it, as Pele reads them.
public struct RadarAppearance: Equatable, Sendable {
    /// `width` and `height`: the circle's diameter box, 1 to 4000 points.
    public internal(set) var width: CGFloat = 320
    public internal(set) var height: CGFloat = 320
    /// `marginTop`, `marginRight`, `marginBottom`, `marginLeft`: the room kept around the chart, 0 to 2000 points.
    public internal(set) var marginTop: CGFloat = 16
    public internal(set) var marginRight: CGFloat = 16
    public internal(set) var marginBottom: CGFloat = 16
    public internal(set) var marginLeft: CGFloat = 16
    /// `axisScaleFactor`: how far a spoke reaches, as a share of the radius, 0 to 10.
    public internal(set) var axisScaleFactor: CGFloat = 1
    /// `axisLabelFactor`: how far out an axis's label stands, as a share of the radius, 0 to 10.
    public internal(set) var axisLabelFactor: CGFloat = 1.05
    /// `curveTension`: how round a curve's corners are, 0 (straight) to 1.
    public internal(set) var curveTension: CGFloat = 0.17

    /// Options that set nothing.
    public init() {}

    init(_ options: MermaidConfigurationOptions) {
        func number(_ name: String, _ fallback: Double, _ least: Double, _ largest: Double) -> CGFloat {
            CGFloat(options.boundedNumber(name, fallback: fallback, least: least, largest: largest))
        }
        width = number("width", 320, 1, 4_000)
        height = number("height", 320, 1, 4_000)
        marginTop = number("marginTop", 16, 0, 2_000)
        marginRight = number("marginRight", 16, 0, 2_000)
        marginBottom = number("marginBottom", 16, 0, 2_000)
        marginLeft = number("marginLeft", 16, 0, 2_000)
        axisScaleFactor = number("axisScaleFactor", 1, 0, 10)
        axisLabelFactor = number("axisLabelFactor", 1.05, 0, 10)
        curveTension = number("curveTension", 0.17, 0, 1)
    }
}
