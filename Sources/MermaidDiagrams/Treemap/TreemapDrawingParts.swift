/**
 * File: TreemapDrawingParts.swift
 * -------------------------------
 * Layer: Core
 * Description: A laid-out treemap's geometry grouped by how it is painted.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A box of a treemap with how it is painted: its rounded outline, its fill and its outline's paint, either of which a
/// class may take away or change.
public struct TreemapBoxParts {
    public let path: CGPath
    /// The inside's paint, or nil for none.
    public let fill: DiagramPaint?
    /// The outline's paint, or nil for none, and its stroke.
    public let outline: DiagramPaint?
    public let stroke: DiagramStroke
}

/// A text of a treemap with its paint.
public struct TreemapTextParts {
    public let block: DiagramTextBlock
    public let paint: DiagramPaint
}

/// A laid-out treemap's geometry grouped by how it is painted, so that drawing it in any colors is a few fills, strokes and
/// texts, by Core Graphics (`TreemapRenderer`) or by a view's own shapes. Back to front, as Pele draws: the title, the
/// sections' boxes and their names and totals, then the leaves' boxes and their names and values.
public struct TreemapDrawingParts {
    public let sectionBoxes: [TreemapBoxParts]
    /// The sections' names, drawn bold.
    public let sectionNames: [TreemapTextParts]
    /// The sections' totals, drawn in the muted color unless a class colors the text.
    public let sectionValues: [TreemapTextParts]
    public let leafBoxes: [TreemapBoxParts]
    public let leafNames: [TreemapTextParts]
    public let leafValues: [TreemapTextParts]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    /// The width of a box's outline.
    public static let lineWidth: CGFloat = 1
    /// How opaque a section's tint of its series color is.
    public static let sectionFillOpacity: CGFloat = 0.12

    public init(layout: TreemapLayout) {
        var sectionBoxes: [TreemapBoxParts] = []
        var sectionNames: [TreemapTextParts] = []
        var sectionValues: [TreemapTextParts] = []
        var leafBoxes: [TreemapBoxParts] = []
        var leafNames: [TreemapTextParts] = []
        var leafValues: [TreemapTextParts] = []
        for box in layout.boxes {
            let style = box.style
            let contrast = TreemapInk.paint(onFill: style.fill)
            if box.isSection {
                if box.hasHeader { sectionBoxes.append(Self.sectionBox(box)) }
                let namePaint = style.textColor.map(DiagramPaint.color) ?? contrast ?? .foreground
                if let name = box.name { sectionNames.append(TreemapTextParts(block: name, paint: namePaint)) }
                if let value = box.value {
                    sectionValues.append(TreemapTextParts(block: value, paint: style.textColor.map(DiagramPaint.color) ?? contrast ?? .muted))
                }
            } else {
                leafBoxes.append(Self.leafBox(box))
                let paint = style.textColor.map(DiagramPaint.color) ?? contrast ?? .background
                if let name = box.name { leafNames.append(TreemapTextParts(block: name, paint: paint)) }
                if let value = box.value { leafValues.append(TreemapTextParts(block: value, paint: paint)) }
            }
        }
        self.sectionBoxes = sectionBoxes
        self.sectionNames = sectionNames
        self.sectionValues = sectionValues
        self.leafBoxes = leafBoxes
        self.leafNames = leafNames
        self.leafValues = leafValues
        title = layout.title
    }

    /// A section's box: a tint of its series color and an outline in it, unless its class gives a fill or an outline.
    private static func sectionBox(_ box: TreemapLayoutBox) -> TreemapBoxParts {
        let series = DiagramPaint.series(box.seriesIndex)
        return TreemapBoxParts(path: roundedPath(box), fill: box.style.fill.map(DiagramPaint.color) ?? series.atOpacity(sectionFillOpacity),
                               outline: box.style.stroke.map(DiagramPaint.color) ?? series, stroke: stroke(of: box.style))
    }

    /// A leaf's box: its series color, with an outline only where its class gives one.
    private static func leafBox(_ box: TreemapLayoutBox) -> TreemapBoxParts {
        TreemapBoxParts(path: roundedPath(box), fill: box.style.fill.map(DiagramPaint.color) ?? .series(box.seriesIndex),
                        outline: box.style.stroke.map(DiagramPaint.color), stroke: stroke(of: box.style))
    }

    private static func stroke(of style: DiagramElementStyle) -> DiagramStroke {
        DiagramStroke(lineWidth: style.strokeWidth ?? lineWidth, dashLengths: style.strokeDashLengths ?? [])
    }

    private static func roundedPath(_ box: TreemapLayoutBox) -> CGPath {
        let radius = min(box.cornerRadius, box.frame.width / 2, box.frame.height / 2)
        return CGPath(roundedRect: box.frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}

/// The text color Pele picks on a fill a class sets: the dark ink on a light fill and the white on a dark one, by which
/// contrasts more; none when the fill is more than half transparent, where the page behind it decides.
enum TreemapInk {
    /// Pele's dark and light inks, `--pele-fg-on-light` and `--pele-fg-on-dark`.
    private static let onLight = DiagramColor(red: 31.0 / 255, green: 31.0 / 255, blue: 31.0 / 255)
    private static let onDark = DiagramColor(red: 1, green: 1, blue: 1)

    static func paint(onFill fill: DiagramColor?) -> DiagramPaint? {
        guard let fill, fill.alpha >= 0.5 else { return nil }
        return .color(luminance(fill) > evenLuminance ? onLight : onDark)
    }

    /// The luminance at which the dark ink and white contrast equally: past it the dark ink contrasts more.
    private static let evenLuminance = (1.05 * (luminance(onLight) + 0.05)).squareRoot() - 0.05

    /// The relative luminance of an sRGB color.
    private static func luminance(_ color: DiagramColor) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }
}
