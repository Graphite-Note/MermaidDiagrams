/**
 * File: WardleyMapCanvas.swift
 * ----------------------------
 * Layer: Core
 * Description: The plot a Wardley map is laid out on before it is moved onto the page, as Pele's draw() keeps it: the
 *              projection from percent, the extent everything drawn reaches, and text centered or starting at a point.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 19/11/2026
 */

import CoreGraphics

/// The measurers of a Wardley map's text: the map's text (13 points at 16) regular and bold, links' labels (12)
/// regular, forces' names (12) bold, annotations' numbers (11) bold, and the title bold.
struct WardleyMapMeasurers<Measurer: DiagramTextMeasuring> {
    let text: Measurer
    let boldText: Measurer
    let linkText: Measurer
    let boldLinkText: Measurer
    let boldNumberText: Measurer
    let titleText: Measurer
}

/// The plot in its own coordinates, its top left corner at the origin, the extent of what is drawn around it, and
/// whether it is drawn tight for a narrow container, its labels wrapped narrower.
struct WardleyMapCanvas {
    let plotWidth: CGFloat
    let plotHeight: CGFloat
    let isTight: Bool
    private(set) var minimumX: CGFloat = 0
    private(set) var minimumY: CGFloat = 0
    private(set) var maximumX: CGFloat
    private(set) var maximumY: CGFloat

    init(plotWidth: CGFloat, plotHeight: CGFloat, isTight: Bool = false) {
        self.plotWidth = plotWidth
        self.plotHeight = plotHeight
        self.isTight = isTight
        maximumX = plotWidth
        maximumY = plotHeight
    }

    /// Where a component's label and the axes' titles wrap: nowhere, or tight from 64 to 120 points, half the plot.
    var textWidth: CGFloat {
        isTight ? max(64, min(120, plotWidth / 2)) : PlaneMapLabel.unwrappedWidth
    }

    /// Where an anchor's name wraps: nowhere, or tight at half the plot, at least 64 points.
    var anchorTextWidth: CGFloat {
        isTight ? max(64, plotWidth / 2) : PlaneMapLabel.unwrappedWidth
    }

    /// Where the annotations' list wraps: at 320 points, or tight at the plot less 20, at least 80.
    var annotationListWidth: CGFloat {
        isTight ? max(80, plotWidth - 20) : 320
    }

    /// Where the title wraps: nowhere, or tight at the plot's width, at least 80 points.
    var titleWidth: CGFloat {
        isTight ? max(80, plotWidth) : PlaneMapLabel.unwrappedWidth
    }

    /// An evolution in percent across the plot.
    func x(_ percent: Double) -> CGFloat {
        CGFloat(percent) / 100 * plotWidth
    }

    /// A visibility in percent up the plot.
    func y(_ percent: Double) -> CGFloat {
        plotHeight - CGFloat(percent) / 100 * plotHeight
    }

    func point(_ point: WardleyMapPoint) -> CGPoint {
        CGPoint(x: x(point.x), y: y(point.y))
    }

    /// Takes in the rectangle from (`minimumX`, `minimumY`) to (`maximumX`, `maximumY`).
    mutating func grow(_ left: CGFloat, _ top: CGFloat, _ right: CGFloat, _ bottom: CGFloat) {
        minimumX = min(minimumX, left)
        minimumY = min(minimumY, top)
        maximumX = max(maximumX, right)
        maximumY = max(maximumY, bottom)
    }

    /// `block` centered at `center`, taken in.
    mutating func centered(_ block: DiagramTextBlock, at center: CGPoint) -> DiagramTextBlock {
        grow(center.x - block.size.width / 2, center.y - block.size.height / 2, center.x + block.size.width / 2, center.y + block.size.height / 2)
        return PlaneMapLabel.placed(block, at: center)
    }

    /// `block`'s lines each starting at `x`, the first's baseline at `baseline` and each next a line lower, taken in with
    /// four points below, as Pele's `starting` writes them.
    mutating func starting(_ block: DiagramTextBlock, x: CGFloat, baseline: CGFloat) -> [DiagramTextBlock] {
        grow(x, baseline - block.fontSize, x + block.size.width, baseline - block.fontSize + block.size.height + Self.startingTextClearance)
        return Self.lines(of: block, x: x, baseline: baseline)
    }

    /// Below a starting text: Pele's 4 points.
    static let startingTextClearance: CGFloat = 4

    /// `block`'s lines as blocks of one line each, starting at `x`, the first's baseline at `baseline`.
    static func lines(of block: DiagramTextBlock, x: CGFloat, baseline: CGFloat) -> [DiagramTextBlock] {
        block.lines.indices.map { index in
            let lineBaseline = baseline + CGFloat(index) * block.lineHeight
            return DiagramTextBlock(planeMapLine: block.lines[index], width: block.lineWidths[index], fontSize: block.fontSize, lineHeight: block.lineHeight,
                                    center: CGPoint(x: x + block.lineWidths[index] / 2,
                                                    y: lineBaseline - block.fontSize * DiagramTextDrawing.baselineShiftRatio))
        }
    }
}

extension DiagramTextBlock {
    /// One line already measured, centered at `center`: a line of a text written from its start, as a Wardley map's
    /// labels are.
    init(planeMapLine line: String, width: CGFloat, fontSize: CGFloat, lineHeight: CGFloat, center: CGPoint) {
        lines = [line]
        lineWidths = [width]
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.center = center
    }
}
