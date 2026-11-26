/**
 * File: EntityRelationshipConstantCells.swift
 * -------------------------------------------
 * Layer: Core
 * Description: The cells of an entity's attribute rows that come from a closed set, measured once a diagram: the keys
 *              (`PK`, `PK, FK` and the other lists written) and a comment that is not written.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// The keys cells and the empty comment of a diagram's attribute rows, each measured the first time a row shows it, as
/// `EntityRelationshipBoxMeasurement` measured it for every row: keys written as their keywords joined by `, ` (no keys
/// the empty one-line label), an unwritten comment as a label of no lines. A block measured once is the block measuring
/// its text again gives. The lists of keys are compared in a short list, as an attribute holds at most a few keys and a
/// diagram writes few lists of them; past `largestKeyListCount` lists, a list is measured each time.
struct EntityRelationshipConstantCells {
    static let largestKeyListCount = 16

    private var keyLists: [(keys: [EntityRelationshipAttributeKey], block: DiagramTextBlock)] = []
    private var unwrittenComment: DiagramTextBlock?

    mutating func keys<Measurer: DiagramTextMeasuring>(_ keys: [EntityRelationshipAttributeKey], measurer: Measurer) -> DiagramTextBlock {
        for known in keyLists where known.keys == keys { return known.block }
        let label = keys.isEmpty ? DiagramLabel("") : DiagramLabel(keys.map(\.mermaidKeyword).joined(separator: ", "))
        let block = DiagramTextBlock(label: label, measurer: measurer, maximumWidth: .greatestFiniteMagnitude)
        if keyLists.count < Self.largestKeyListCount { keyLists.append((keys, block)) }
        return block
    }

    mutating func noComment<Measurer: DiagramTextMeasuring>(measurer: Measurer) -> DiagramTextBlock {
        if let unwrittenComment { return unwrittenComment }
        let block = DiagramTextBlock(label: DiagramLabel(lines: []), measurer: measurer, maximumWidth: EntityRelationshipBoxMeasurement.commentWrappingWidth)
        unwrittenComment = block
        return block
    }
}
