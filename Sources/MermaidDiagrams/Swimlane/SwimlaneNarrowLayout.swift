/**
 * File: SwimlaneNarrowLayout.swift
 * --------------------------------
 * Layer: Core
 * Description: A swimlane diagram's narrow layout for a preparation that has its regular layout: fitted to the column
 *              as SwimlaneLayoutEngine fits it, with the regular layout's width standing for the layout across in
 *              Pele's measurements, which is the regular layout, so that it is not laid out a second time.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

import CoreGraphics

extension SwimlaneLayoutEngine {
    /// A layout tried while fitting a diagram to a column: one laid out, or the regular layout, known by its width alone.
    private enum FittedLayout {
        case laidOut(SwimlaneLayout)
        case regular(width: CGFloat)

        var width: CGFloat {
            switch self {
            case .laidOut(let layout): layout.size.width
            case .regular(let width): width
            }
        }
    }

    /// Thrown when fitting picks the regular layout, which no narrow scene is drawn for: its width is not under the
    /// regular one's.
    struct RegularLayoutIsNarrowest: Error {}

    /// `layout(_:typography:availableWidth:)` of a diagram whose regular layout (`layout(_:typography:)`, across in Pele's
    /// measurements) is `regularWidth` wide: the same layouts tried in the same order, but the regular one not laid out
    /// again. Throws `RegularLayoutIsNarrowest` where fitting keeps the regular layout.
    static func narrowLayout(_ diagram: FlowchartDiagram, typography: DiagramTypography, availableWidth: CGFloat?,
                             regularWidth: CGFloat) throws(RegularLayoutIsNarrowest) -> SwimlaneLayout {
        var measurements: (standard: FlowchartMeasurement?, tight: FlowchartMeasurement?) = (nil, nil)
        func fitted(_ fitting: FlowchartDiagram, isDown: Bool) -> FittedLayout {
            DiagramWidthFitting.tighten(availableWidth: availableWidth, width: { (layout: FittedLayout) in layout.width }) { isTight in
                if !isTight && !isDown { return .regular(width: regularWidth) }
                let collapsed = FlowchartCollapsedGroups.collapsing(fitting)
                let measured = (isTight ? measurements.tight : measurements.standard)
                    ?? measurement(of: collapsed, nodeText: typography.nodeText, edgeText: typography.edgeText, isTight: isTight)
                if isTight { measurements.tight = measured } else { measurements.standard = measured }
                return .laidOut(layout(collapsed: collapsed, measured: measured, nodeText: typography.nodeText, titleText: typography.boldNodeText,
                                       font: typography.font, isTight: isTight, columnWidth: availableWidth))
            }
        }
        let chosen: FittedLayout
        if let turned = diagram.swimlaneTurnedToRunDown {
            chosen = DiagramWidthFitting.turnToFit(availableWidth: availableWidth, width: { (layout: FittedLayout) in layout.width }) { isDown in
                fitted(isDown ? turned : diagram, isDown: isDown)
            }
        } else {
            chosen = fitted(diagram, isDown: false)
        }
        guard case .laidOut(let layout) = chosen else { throw RegularLayoutIsNarrowest() }
        return layout
    }
}
