/**
 * File: UseCaseEdgeLine.swift
 * ---------------------------
 * Layer: Core
 * Description: A use case diagram's line once drawn, made the relationship it shows: its dashes, its marks, its label
 *              on a patch, and how it is painted over the boundaries a style fills, as Pele's renderUsecase paints it.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

/// A line drawn from one end to the other: its path, its ends' tips and the ways the marks there point, and where its
/// label goes.
struct UseCaseEdgeLine {
    let path: DiagramPath
    let startTip: CGPoint
    let startDirection: CGVector
    let endTip: CGPoint
    let endDirection: CGVector
    let labelCenter: CGPoint

    /// A generalization's hollow triangle: its length, and the part of the line it takes.
    static let extensionLength: CGFloat = 12
    static let noteConnectorDashes: [CGFloat] = [2, 3]
    static let dottedDashes: [CGFloat] = [5, 4]
    static let animatedDashes: [CGFloat] = [9, 5]

    /// The relationship `edge` along this line, with `label`, painted over the filled boundaries `fills`: in the color
    /// Pele's ink picks for the fill it lies in, or cased where it crosses a border, or inside a fill it has no ink for
    /// or when its style sets a stroke.
    /// `fillFrames` are the frames of `fills`, and `look` the look of `edge`'s styles.
    func edge(_ edge: UseCaseGraphEdge, label: DiagramTextBlock, fills: [UseCaseLayoutBoundary], fillFrames: [CGRect], look: UseCaseLook) -> UseCaseLayoutEdge {
        var inkOverFill: DiagramColor?
        var fillUnderMarks: DiagramColor?
        var isCased = false
        // A line lies on no fill when no boundary is filled, which needs no list of its tips.
        let placement = fillFrames.isEmpty ? .onNone : DiagramFillPlacement.placement(of: path, tips: [startTip, endTip], among: fillFrames)
        switch placement {
        case .onNone: break
        case .acrossBorder: isCased = true
        case .inside(let place):
            if look.stroke == nil, let ink = fills[place].look.lineInk {
                inkOverFill = ink
                fillUnderMarks = fills[place].look.fill
            } else {
                isCased = true
            }
        }
        let dashes = edge.isNoteConnector ? Self.noteConnectorDashes : edge.isDotted ? Self.dottedDashes
            : edge.isAnimated ? Self.animatedDashes : look.strokeDashLengths ?? []
        var placedLabel: DiagramTextBlock?
        var patch: CGRect?
        if label.size.width > 0 {
            var placed = label
            placed.center = labelCenter
            placedLabel = placed
            let patchWidth = label.size.width + UseCaseLayoutEngine.edgeLabelPatchWidening
            patch = CGRect(x: labelCenter.x - patchWidth / 2, y: labelCenter.y - label.size.height / 2, width: patchWidth, height: label.size.height)
        }
        return UseCaseLayoutEdge(identifier: edge.identifier, path: path, dashLengths: dashes,
                                 startMark: mark(edge.startMarker, tip: startTip, direction: startDirection),
                                 endMark: mark(edge.endMarker, tip: endTip, direction: endDirection), label: placedLabel, labelPatch: patch,
                                 isSemantic: edge.isSemantic, look: look, inkOverFill: inkOverFill, fillUnderMarks: fillUnderMarks, isCased: isCased)
    }

    private func mark(_ marker: UseCaseMarker, tip: CGPoint, direction: CGVector) -> UseCaseLayoutMark? {
        marker == .none ? nil : UseCaseLayoutMark(marker: marker, tip: tip, direction: direction)
    }
}
