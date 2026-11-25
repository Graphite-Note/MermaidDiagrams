/**
 * File: SequenceDrawingPaths.swift
 * --------------------------------
 * Layer: Core
 * Description: A laid-out sequence diagram's paths, grouped as its drawing parts group them, recorded into Core
 *              Graphics paths for the drawing parts or into lanes of the thread's scene workspace for the scene.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

/// A sequence diagram's paths, grouped as `SequenceDrawingParts` groups them, recorded into the paths a maker makes:
/// Core Graphics paths for the drawing parts, lanes of the thread's scene workspace for the scene. Both record the same
/// elements, bit for bit.
struct SequenceDrawingPaths<Path: DiagramCurvedPathRecording> {
    /// Each box's and each highlight's rounded rectangle, made whole; each activation's.
    let boxes: [Path]
    let highlights: [Path]
    let lifelines: Path
    let activations: [Path]
    let blockOutlines: Path
    let blockSectionLines: Path
    let blockTextPatches: Path
    let blockTabs: Path
    let messages: SequenceMessagePaths<Path>
    let destructions: Path
    let notes: Path
    let participants: SequenceParticipantShapeDrawing<Path>

    init<Maker: DiagramPathMaking>(layout: SequenceLayout, making maker: Maker) where Maker.Path == Path {
        let radius = SequenceDrawingParts.cornerRadius
        boxes = layout.boxes.map { box in maker.roundedRectangle(box.frame, cornerWidth: radius, cornerHeight: radius) }
        highlights = layout.highlights.map { highlight in maker.roundedRectangle(highlight.frame, cornerWidth: radius, cornerHeight: radius) }
        lifelines = maker.makePath()
        for lifeline in layout.lifelines where lifeline.bottom > lifeline.top {
            lifelines.move(to: CGPoint(x: lifeline.x, y: lifeline.top))
            lifelines.addLine(to: CGPoint(x: lifeline.x, y: lifeline.bottom))
        }
        let activationRadius = SequenceDrawingParts.activationCornerRadius
        activations = layout.activations.map { activation in maker.roundedRectangle(activation, cornerWidth: activationRadius, cornerHeight: activationRadius) }
        blockOutlines = maker.makePath()
        blockSectionLines = maker.makePath()
        blockTextPatches = maker.makePath()
        blockTabs = maker.makePath()
        for block in layout.blocks {
            maker.addMadeRoundedRectangle(block.frame, cornerWidth: radius, cornerHeight: radius, to: blockOutlines)
            for section in block.sections {
                blockSectionLines.move(to: CGPoint(x: block.frame.minX, y: section.lineY))
                blockSectionLines.addLine(to: CGPoint(x: block.frame.maxX, y: section.lineY))
            }
            for patch in block.textPatches { maker.addMadeRoundedRectangle(patch, cornerWidth: radius, cornerHeight: radius, to: blockTextPatches) }
            maker.addMadeRoundedRectangle(block.tab, cornerWidth: radius, cornerHeight: radius, to: blockTabs)
        }
        messages = SequenceMessagePaths(messages: layout.messages, making: maker)
        destructions = maker.makePath()
        let halfSize = SequenceSpacing.destructionHalfSize
        for center in layout.destructions {
            destructions.addLines(between: [CGPoint(x: center.x - halfSize, y: center.y - halfSize), CGPoint(x: center.x + halfSize, y: center.y + halfSize)])
            destructions.addLines(between: [CGPoint(x: center.x + halfSize, y: center.y - halfSize), CGPoint(x: center.x - halfSize, y: center.y + halfSize)])
        }
        notes = maker.makePath()
        for note in layout.notes { maker.addMadeRoundedRectangle(note.frame, cornerWidth: radius, cornerHeight: radius, to: notes) }
        participants = SequenceParticipantShapeDrawing(participants: layout.participants, making: maker)
    }

    /// Each block's title and section texts with the color each takes on its background, block by block.
    static func forEachBlockText(of blocks: [SequenceLayoutBlock], _ body: (DiagramTextBlock, DiagramColor?) -> Void) {
        for block in blocks {
            if let title = block.title { body(title, SequenceTextInk.ink(on: block.titleBackground)) }
            for section in block.sections {
                guard let text = section.text else { continue }
                body(text, SequenceTextInk.ink(on: section.textBackground))
            }
        }
    }
}
