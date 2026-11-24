/**
 * File: BlockModelValues.swift
 * ----------------------------
 * Layer: Core
 * Description: A block model made of a diagram's values rather than read: each text written after the last into one
 *              block of bytes, each list into the model's lists, for a diagram made of values, as 0.7.0's reader made
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension BlockModel {
    /// A model holding these values, each text after the last: a diagram made of values rather than read.
    convenience init(blocks: [BlockDiagramBlock], edges: [BlockDiagramEdge], classes: [String: BlockClassDefinition]) {
        var encoding = BlockModelValueEncoding()
        let records = blocks.enumerated().map { index, block in encoding.record(of: block, isRoot: index == BlockDiagram.rootIndex) }
        let edgeRecords = edges.map { edge in encoding.record(of: edge) }
        encoding.addClasses(classes)
        self.init(bytes: encoding.bytes, blocks: records, edges: edgeRecords, classes: encoding.classes,
                  classIndicesByNameNumber: encoding.classIndices, classNames: encoding.classNames, childIndices: encoding.childIndices,
                  texts: encoding.texts, classLinks: encoding.classLinks, identifiers: encoding.identifiers)
    }
}

/// The lists of a model being written from values.
private struct BlockModelValueEncoding {
    var bytes: [UInt8] = []
    var texts: [BlockText] = []
    var childIndices: [Int32] = []
    var classLinks: [BlockClassLink] = []
    var identifiers = BlockNameTable()
    var classNames = BlockNameTable()
    var classIndices: [Int32] = []
    var classes: [BlockClassRecord] = []

    mutating func text(_ string: String) -> BlockText {
        let start = bytes.count
        bytes.append(contentsOf: string.utf8)
        return BlockText(start: start, count: bytes.count - start)
    }

    mutating func slice(_ strings: [String]) -> BlockSlice {
        let first = texts.count
        for string in strings { texts.append(text(string)) }
        return BlockSlice(first: first, count: strings.count)
    }

    mutating func record(of block: BlockDiagramBlock, isRoot: Bool) -> BlockRecord {
        let identifier = text(block.identifier)
        let (kind, shapeIndex): (BlockKindCode, UInt8) = switch block.kind {
        case .unshaped: (.unshaped, 0)
        case .shape(let shape): (.shape, UInt8(BlockModel.shapes.firstIndex(of: shape) ?? 0))
        case .arrow: (.arrow, 0)
        case .composite: (.composite, 0)
        case .space: (.space, 0)
        }
        var record = BlockRecord(identifier: identifier, identifierNumber: isRoot ? -1 : Int32(identifiers.intern(identifier, in: bytes)), kind: kind,
                                 shapeIndex: shapeIndex, label: text(block.label), widthInColumns: block.widthInColumns,
                                 directions: slice(block.directions))
        record.children = BlockSlice(first: childIndices.count, count: block.childIndices.count)
        childIndices.append(contentsOf: block.childIndices.map { child in Int32(truncatingIfNeeded: child) })
        record.columns = block.columns ?? 0
        record.hasColumns = block.columns != nil
        for name in block.classNames ?? [] {
            let link = Int32(classLinks.count)
            classLinks.append(BlockClassLink(name: text(name), next: -1))
            if record.lastClassLink >= 0 { classLinks[Int(record.lastClassLink)].next = link } else { record.firstClassLink = link }
            record.lastClassLink = link
        }
        record.styles = block.styles.map { styles in slice(styles) }
        record.colorIndex = block.colorIndex.map { index in Int32(truncatingIfNeeded: index) } ?? -1
        return record
    }

    mutating func record(of edge: BlockDiagramEdge) -> BlockEdgeRecord {
        let ordinal = Int32(edge.identifier.prefix { character in character != "-" }) ?? 0
        let source = text(edge.sourceIdentifier)
        let target = text(edge.targetIdentifier)
        return BlockEdgeRecord(ordinal: ordinal, source: source, target: target, sourceNumber: Int32(identifiers.intern(source, in: bytes)),
                               targetNumber: Int32(identifiers.intern(target, in: bytes)), label: text(edge.label),
                               sourceArrowhead: BlockHierarchy.arrowheadCode(edge.sourceArrowhead),
                               targetArrowhead: BlockHierarchy.arrowheadCode(edge.targetArrowhead), isThick: edge.isThick, isDotted: edge.isDotted)
    }

    mutating func addClasses(_ definitions: [String: BlockClassDefinition]) {
        for (name, definition) in definitions.sorted(by: { first, second in first.key < second.key }) {
            let nameText = text(name)
            let number = classNames.intern(nameText, in: bytes)
            while classIndices.count <= number { classIndices.append(-1) }
            classIndices[number] = Int32(classes.count)
            classes.append(BlockClassRecord(name: nameText, styles: definition.styles.map { style in text(style) }))
        }
    }
}
