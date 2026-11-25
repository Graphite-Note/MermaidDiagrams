/**
 * File: StateDiagramNotePlacement.swift
 * -------------------------------------
 * Layer: Core
 * Description: Puts a placed state diagram's notes on the page, each beside its state or its composite's box with the
 *              dashed line from the side that faces it.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

extension StateDiagramPageAssembly {
    /// Each note beside its state, with the dashed line from the state's side that faces it.
    func notes() -> [StateDiagramLayoutNote] {
        var notes: [StateDiagramLayoutNote] = []
        notes.reserveCapacity(diagram.notes.count)
        for (noteIndex, note) in diagram.notes.enumerated() {
            if noteIndex < compositeNoteCenters.count, let center = compositeNoteCenters[noteIndex],
               let composite = clustered?.compositeOfState[note.stateIndex] {
                notes.append(compositeNote(at: noteIndex, center: center, compositeFrame: compositeFrames[composite]))
            } else {
                notes.append(stateNote(at: noteIndex, note: note))
            }
        }
        return notes
    }

    /// A note laid out beside a composite, with its dashed line from the middle of the composite's side that faces it.
    private func compositeNote(at noteIndex: Int, center: CGPoint, compositeFrame: CGRect) -> StateDiagramLayoutNote {
        let size = measured.noteSizes[noteIndex]
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let isBeside = frame.maxX <= compositeFrame.minX || frame.minX >= compositeFrame.maxX
        let compositeSide: DiagramSide = isBeside ? (frame.midX < compositeFrame.midX ? .left : .right) : (frame.midY < compositeFrame.midY ? .top : .bottom)
        let compositeCenter = CGPoint(x: compositeFrame.midX, y: compositeFrame.midY)
        let start = StateDiagramEdgePorts.sidePoint(center: compositeCenter, size: compositeFrame.size, side: compositeSide, offset: 0)
        let end = StateDiagramEdgePorts.sidePoint(center: center, size: size, side: Self.opposite(compositeSide), offset: 0)
        let connector = DiagramRouteDrawing.path(through: [start, end], flowIsVertical: !isBeside, startTrim: 0, endTrim: 0).path
        var text = measured.noteTexts[noteIndex]
        text.center = center
        return StateDiagramLayoutNote(frame: frame, text: text, connector: connector)
    }

    /// A note beside its state, where the state's surroundings put it.
    private func stateNote(at noteIndex: Int, note: StateDiagramNote) -> StateDiagramLayoutNote {
        let stateCenter = stateCenters[note.stateIndex]
        let offset = surroundings.noteOffsets[noteIndex]
        let size = measured.noteSizes[noteIndex]
        let center = CGPoint(x: stateCenter.x + offset.dx, y: stateCenter.y + offset.dy)
        let stateSide = noteSide(note.side)
        let stateSize = measured.stateSizes[note.stateIndex]
        let stackPosition = surroundings.noteStackPositions[noteIndex]
        let offsets = StateDiagramEdgePorts.offsets(count: stackPosition.count, placement: diagram.states[note.stateIndex].kind.portPlacement,
                                                    sideLength: stateSide.isHorizontal ? stateSize.width : stateSize.height)
        let start = StateDiagramEdgePorts.sidePoint(center: stateCenter, size: stateSize, side: stateSide, offset: offsets[stackPosition.index])
        let end = StateDiagramEdgePorts.sidePoint(center: center, size: size, side: Self.opposite(stateSide), offset: 0)
        let connector = DiagramRouteDrawing.path(through: [start, end], flowIsVertical: !axes.flowIsVertical, startTrim: 0, endTrim: 0).path
        var text = measured.noteTexts[noteIndex]
        text.center = center
        return StateDiagramLayoutNote(frame: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                                      text: text, connector: connector)
    }

    /// The side of a state that faces its notes on `side`: across the flow, before or after it.
    private func noteSide(_ side: StateDiagramNoteSide) -> DiagramSide {
        switch side {
        case .left: axes.flowIsVertical ? .left : .top
        case .right: axes.flowIsVertical ? .right : .bottom
        }
    }

    private static func opposite(_ side: DiagramSide) -> DiagramSide {
        switch side {
        case .top: .bottom
        case .bottom: .top
        case .left: .right
        case .right: .left
        }
    }
}
