/**
 * File: RadarChartDrawingParts.swift
 * ----------------------------------
 * Layer: Core
 * Description: A laid-out radar chart's geometry grouped by how it is painted.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A laid-out radar chart's geometry grouped by how it is painted, so that drawing it in any colors is a few strokes and
/// fills, by Core Graphics (`RadarChartRenderer`) or by a view's own shapes. Back to front, as Pele draws: the title, the
/// graticule, the spokes, the curves, the axes' labels, the legend.
public struct RadarChartDrawingParts {
    /// The rings, circles or polygons, stroked in the second surface color.
    public let graticule: CGPath
    /// The spokes from the center, stroked in the border color.
    public let spokes: CGPath
    /// The curves, each filled and stroked in its series color.
    public let curves: [RadarChartCurveParts]
    public let axisLabels: [DiagramTextBlock]
    /// The legend's swatches, each filled and stroked in its curve's series color.
    public let legendSwatches: [RadarChartSwatchParts]
    public let legendTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    /// The width of the graticule's and the spokes' lines.
    public static let lineWidth: CGFloat = 1
    /// The width of a curve's outline.
    public static let curveLineWidth: CGFloat = 1.5
    /// How opaque a curve's fill is.
    public static let curveFillOpacity: CGFloat = 0.2
    /// How opaque a legend swatch's fill is.
    public static let swatchFillOpacity: CGFloat = 0.4
    /// The corner radius of a legend swatch.
    static let swatchCornerRadius: CGFloat = 2

    public init(layout: RadarChartLayout) {
        graticule = Self.graticule(of: layout)
        spokes = Self.spokes(of: layout)
        curves = layout.curves.map { curve in
            let path = curve.isRounded ? RadarCurveSpline.closedPath(through: curve.points, tension: curve.tension)
                : RadarCurveSpline.closedPolygon(through: curve.points)
            return RadarChartCurveParts(seriesIndex: curve.seriesIndex, path: path)
        }
        axisLabels = layout.axisLabels
        legendSwatches = layout.legend.map { entry in
            let path = CGMutablePath()
            path.addRoundedRect(in: entry.swatch, cornerWidth: Self.swatchCornerRadius, cornerHeight: Self.swatchCornerRadius)
            return RadarChartSwatchParts(seriesIndex: entry.seriesIndex, path: path)
        }
        legendTexts = layout.legend.map(\.text)
        title = layout.title
    }

    private static func graticule(of layout: RadarChartLayout) -> CGPath {
        let path = CGMutablePath()
        for ringRadius in layout.ringRadii {
            switch layout.graticule {
            case .circle:
                path.addEllipse(in: CGRect(x: layout.center.x - ringRadius, y: layout.center.y - ringRadius, width: 2 * ringRadius, height: 2 * ringRadius))
            case .polygon:
                let corners = layout.axisDirections.map { direction in
                    CGPoint(x: layout.center.x + direction.x * ringRadius, y: layout.center.y + direction.y * ringRadius)
                }
                path.addPath(RadarCurveSpline.closedPolygon(through: corners))
            }
        }
        return path
    }

    private static func spokes(of layout: RadarChartLayout) -> CGPath {
        let path = CGMutablePath()
        for direction in layout.axisDirections {
            path.move(to: layout.center)
            path.addLine(to: CGPoint(x: layout.center.x + direction.x * layout.spokeLength, y: layout.center.y + direction.y * layout.spokeLength))
        }
        return path
    }
}

/// A curve's outline in the page's coordinates, with the series that picks its color.
public struct RadarChartCurveParts {
    public let seriesIndex: Int
    public let path: CGPath
}

/// A legend swatch's outline, with the series that picks its color.
public struct RadarChartSwatchParts {
    public let seriesIndex: Int
    public let path: CGPath
}
