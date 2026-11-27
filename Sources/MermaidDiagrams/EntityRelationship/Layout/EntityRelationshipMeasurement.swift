/**
 * File: EntityRelationshipMeasurement.swift
 * -----------------------------------------
 * Layer: Core
 * Description: An entity relationship diagram's text measured into one list of lines and its boxes sized, the boxes,
 *              rows, cells, labels and loops kept in lists of the thread's scratch arena.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.6
 * Date: 26/11/2026
 */

import CoreGraphics

/// The measurers an entity relationship diagram's texts are measured with on the flat path: names at the font's size,
/// rows and labels at seven eighths of it, keys at three quarters (`EntityRelationshipTextMeasurers`).
struct EntityRelationshipFlatMeasurers<Measurer: DiagramTextMeasuring> {
    let name: DiagramFlatMeasurer<Measurer>
    let row: DiagramFlatMeasurer<Measurer>
    let key: EntityRelationshipKeyTextMeasurer<Measurer>

    init(_ measurers: EntityRelationshipTextMeasurers<Measurer>) {
        name = DiagramFlatMeasurer(measurers.name)
        row = DiagramFlatMeasurer(measurers.row)
        key = measurers.key
    }
}

/// An entity relationship diagram's text measured and its boxes sized: what the layout needs before it places anything.
/// Every text is a measured text of `lines`; the boxes, their rows' heights and cells, each relationship's label and
/// each entity's loops are lists of the calling thread's arena, valid while the layout runs.
struct EntityRelationshipMeasurement {
    /// The widest a relationship's label is before it wraps.
    static let labelWrappingWidth: CGFloat = 200

    var lines = DiagramMeasuredLines()
    private(set) var boxes: ScratchList<EntityRelationshipMeasuredBox>
    var rowHeights: ScratchList<CGFloat>
    /// Four to a row: type, name, keys, comment.
    var cells: ScratchList<DiagramMeasuredText>
    /// Each relationship's label, a text of no line when it has none.
    let labels: ScratchSpan<DiagramMeasuredText>
    /// The relationships of each entity with itself, in their written order: `loopStarts[entity]..<loopStarts[entity + 1]`
    /// of `loopRelationships`.
    let loopStarts: ScratchSpan<Int32>
    let loopRelationships: ScratchSpan<Int32>
    /// By relationship, the band of its loop's side a relationship with itself takes.
    let loopBands: ScratchSpan<CGFloat>
    /// For each entity, whether its loops leave its box's bottom (its box's ranks run across) rather than its right.
    let loopsLeaveBelow: ScratchSpan<Bool>
    /// The diagram's title in the names' font, never wrapped, or nil.
    private(set) var title: DiagramMeasuredText?

    init<Measurer>(model: EntityRelationshipModel, measurers textMeasurers: EntityRelationshipTextMeasurers<Measurer>, loopsLeaveBelow: ScratchSpan<Bool>,
                   title: String?, arena: DiagramScratchArena) {
        let measurers = EntityRelationshipFlatMeasurers(textMeasurers)
        self.loopsLeaveBelow = loopsLeaveBelow
        boxes = arena.list(capacity: model.entities.count, of: EntityRelationshipMeasuredBox.self)
        rowHeights = arena.list(capacity: model.attributes.count, of: CGFloat.self)
        cells = arena.list(capacity: EntityRelationshipAttributeTable.cellsPerRow * model.attributes.count, of: DiagramMeasuredText.self)
        labels = arena.uninitializedSpan(count: model.relationships.count)
        loopBands = arena.span(count: model.relationships.count, repeating: CGFloat(0))
        (loopStarts, loopRelationships) = Self.loops(of: model, arena: arena)
        lines.reserveCapacity(lines: 2 * model.entities.count + 4 * model.attributes.count + model.relationships.count + 8, derivedBytes: 64)
        withUnsafePointer(to: model) { model in
            model.pointee.text.withUnsafeBufferPointer { bytes in measureTexts(of: model, bytes: bytes, measurers: measurers, arena: arena) }
        }
        self.title = title.map { title in
            DiagramFlatTextMeasuring.measure(DiagramLabel(title), measurer: measurers.name, maximumWidth: .greatestFiniteMagnitude, into: &lines)
        }
    }

    /// Each entity's relationships with itself, gathered entity by entity in their written order.
    private static func loops(of model: EntityRelationshipModel, arena: DiagramScratchArena) -> (starts: ScratchSpan<Int32>, relationships: ScratchSpan<Int32>) {
        let starts = arena.span(count: model.entities.count + 1, repeating: Int32(0))
        var loopCount = 0
        for relationship in model.relationships where relationship.firstEntityIndex == relationship.secondEntityIndex {
            starts[Int(relationship.firstEntityIndex) + 1] += 1
            loopCount += 1
        }
        for entity in 0..<model.entities.count { starts[entity + 1] += starts[entity] }
        let relationships: ScratchSpan<Int32> = arena.uninitializedSpan(count: loopCount)
        let next = arena.copy(of: starts)
        for (index, relationship) in model.relationships.enumerated() where relationship.firstEntityIndex == relationship.secondEntityIndex {
            let entity = Int(relationship.firstEntityIndex)
            relationships[Int(next[entity])] = Int32(index)
            next[entity] += 1
        }
        return (starts, relationships)
    }

    /// The relationships' labels, the loops' bands, then the boxes with their cells.
    private mutating func measureTexts<Measurer>(of model: UnsafePointer<EntityRelationshipModel>, bytes: UnsafeBufferPointer<UInt8>,
                                                 measurers: EntityRelationshipFlatMeasurers<Measurer>, arena: DiagramScratchArena) {
        let cellMeasuring = EntityRelationshipCellMeasuring<Measurer>(bytes: bytes, model: model)
        for (index, relationship) in model.pointee.relationships.enumerated() {
            labels[index] = cellMeasuring.label(relationship.label, measurer: measurers.row, maximumWidth: Self.labelWrappingWidth, into: &lines)
        }
        var constantCells = EntityRelationshipConstantCells(arena: arena)
        for entity in 0..<model.pointee.entities.count {
            let loops = loopIndices(of: entity)
            var bandsLength: CGFloat = 0
            if !loops.isEmpty {
                for position in loops {
                    let relationship = Int(loopRelationships[position])
                    loopBands[relationship] = EntityRelationshipSelfLoops.band(labelSize: labelSize(of: relationship), leavesBelow: loopsLeaveBelow[entity])
                }
                // The bands added up in their order, as `reduce(0, +)` adds them, and the side's margin.
                var total: CGFloat = 0
                for position in loops { total += loopBands[Int(loopRelationships[position])] }
                bandsLength = total + EntityRelationshipSelfLoops.sideMargin
            }
            let minimumSize = loopsLeaveBelow[entity] ? CGSize(width: bandsLength, height: 0) : CGSize(width: 0, height: bandsLength)
            let box = EntityRelationshipBoxMeasurement.box(ofEntity: entity, cells: cellMeasuring, measurers: measurers, minimumSize: minimumSize, into: &self,
                                                           constantCells: &constantCells)
            boxes.append(box)
        }
    }

    /// The positions in `loopRelationships` of `entity`'s relationships with itself.
    func loopIndices(of entity: Int) -> Range<Int> {
        Int(loopStarts[entity])..<Int(loopStarts[entity + 1])
    }

    /// The size of relationship `index`'s label, or nil when it has none.
    func labelSize(of index: Int) -> CGSize? {
        labels[index].lineCount == 0 ? nil : labels[index].size
    }

    /// Each entity's size in its rank: its box, widened on both sides across the flow by the room its loops take.
    func layoutSizes(arena: DiagramScratchArena) -> ScratchSpan<CGSize> {
        let sizes: ScratchSpan<CGSize> = arena.uninitializedSpan(count: boxes.count)
        for entity in 0..<boxes.count {
            let box = boxes[entity]
            let loops = loopIndices(of: entity)
            guard !loops.isEmpty else {
                sizes[entity] = box.size
                continue
            }
            let room = 2 * EntityRelationshipSelfLoops.room(labelSizes: loops.lazy.map { position in labelSize(of: Int(loopRelationships[position])) },
                                                            leavesBelow: loopsLeaveBelow[entity])
            sizes[entity] = loopsLeaveBelow[entity] ? CGSize(width: box.size.width, height: box.size.height + room)
                                                    : CGSize(width: box.size.width + room, height: box.size.height)
        }
        return sizes
    }
}
