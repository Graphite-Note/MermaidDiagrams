/**
 * File: EntityRelationshipConstantCells.swift
 * -------------------------------------------
 * Layer: Core
 * Description: The cells of an entity's attribute rows that come from a closed set, measured once a diagram: the keys
 *              (`PK`, `PK, FK` and the other lists written) and a comment that is not written, into the layout's lines.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// The keys cells and the empty comment of a diagram's attribute rows, each measured the first time a row shows it into
/// the layout's lines, as `EntityRelationshipBoxMeasurement` measured it for every row: keys written as their keywords
/// joined by `, ` (no keys the empty one-line label), an unwritten comment as a label of no lines. A text measured once is
/// the text measuring it again gives. A list of at most four keys is known by its count and its packed keys, which tell
/// it exactly; the first `largestKeyListCount` such lists are kept, any other list is measured each time.
struct EntityRelationshipConstantCells {
    static let largestKeyListCount = 16

    /// The lists of keys measured, by count and packed keys, in a span of the thread's arena.
    private let keyLists: ScratchSpan<EntityRelationshipMeasuredKeys>
    private var keyListCount = 0
    private var unwrittenComment: DiagramMeasuredText?

    init(arena: DiagramScratchArena) {
        keyLists = arena.uninitializedSpan(count: Self.largestKeyListCount)
    }

    mutating func keys<Measurer: DiagramTextMeasuring>(of attribute: EntityRelationshipAttributeRecord, model: EntityRelationshipModel, measurer: Measurer,
                                                       into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        let isPacked = Int(attribute.keyCount) <= EntityRelationshipAttributeRecord.packedKeyLimit
        if isPacked {
            for index in 0..<keyListCount where keyLists[index].count == attribute.keyCount && keyLists[index].packed == attribute.keyStart {
                return keyLists[index].text
            }
        }
        let keys = (0..<Int(attribute.keyCount)).map { position in model.key(position, of: attribute).mermaidKeyword }
        let label = keys.isEmpty ? DiagramLabel("") : DiagramLabel(keys.joined(separator: ", "))
        let text = DiagramFlatTextMeasuring.copied(DiagramTextBlock(label: label, measurer: measurer, maximumWidth: .greatestFiniteMagnitude), into: &lines)
        if isPacked, keyListCount < Self.largestKeyListCount {
            keyLists[keyListCount] = EntityRelationshipMeasuredKeys(count: attribute.keyCount, packed: attribute.keyStart, text: text)
            keyListCount += 1
        }
        return text
    }

    mutating func noComment<Measurer: DiagramTextMeasuring>(measurer: Measurer, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        if let unwrittenComment { return unwrittenComment }
        let text = DiagramFlatTextMeasuring.copied(DiagramTextBlock(label: DiagramLabel(lines: []), measurer: measurer,
                                                                    maximumWidth: EntityRelationshipBoxMeasurement.commentWrappingWidth), into: &lines)
        unwrittenComment = text
        return text
    }
}

/// A list of keys measured: its count and packed keys, and its text.
struct EntityRelationshipMeasuredKeys {
    let count: Int32
    let packed: Int32
    let text: DiagramMeasuredText
}
