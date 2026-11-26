/**
 * File: IshikawaFishboneRecords.swift
 * -----------------------------------
 * Layer: Core
 * Description: An Ishikawa fishbone as its layout keeps it: every category's bones in one list, every cause in one
 *              list, each category a record of ranges into them, and every text a measured text of the diagram's
 *              bytes, which the scene draws from directly and the public categories and head are made from.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// A category placed: its bones `boneLines[firstBone...]`, its causes `causes[firstCause...]`, its arrow, box and name.
struct IshikawaPlacedCategory: Sendable {
    var firstBone: Int32
    var boneCount: Int32
    var firstCause: Int32
    var causeCount: Int32
    var arrow: DiagramEdgeMark
    var box: CGRect
    var label: DiagramMeasuredText

    var boneRange: Range<Int> { Int(firstBone)..<Int(firstBone + boneCount) }
    var causeRange: Range<Int> { Int(firstCause)..<Int(firstCause + causeCount) }
}

/// A cause's text, ending where its bone starts; a cause of a cause is drawn muted.
struct IshikawaPlacedCause: Sendable {
    var text: DiagramMeasuredText
    let isMuted: Bool
}

/// The fishbone's categories, causes and head with their texts, none for a diagram that runs down.
struct IshikawaFishboneRecords: Sendable {
    /// The texts' lines, ranges of `bytes` (the diagram's) or derived.
    var lines = DiagramMeasuredLines()
    var bytes: [UInt8] = []
    var boneLines: [IshikawaBoneLine] = []
    var categoryRecords: [IshikawaPlacedCategory] = []
    var causes: [IshikawaPlacedCause] = []
    /// The effect's box and bold name, when the diagram has an effect.
    var headFrame: CGRect?
    var headLabel = DiagramMeasuredText(firstLine: 0, lineCount: 0, width: 0, height: 0, lineHeight: 0, fontSize: 0)

    /// Moves everything by `offset`, in place, as 0.7.0 moved each category, its texts and the head.
    mutating func translate(by offset: CGVector) {
        for index in boneLines.indices {
            boneLines[index].start = CGPoint(x: boneLines[index].start.x + offset.dx, y: boneLines[index].start.y + offset.dy)
            boneLines[index].end = CGPoint(x: boneLines[index].end.x + offset.dx, y: boneLines[index].end.y + offset.dy)
        }
        for index in categoryRecords.indices {
            categoryRecords[index].arrow = categoryRecords[index].arrow.translated(by: offset)
            categoryRecords[index].box = categoryRecords[index].box.offsetBy(dx: offset.dx, dy: offset.dy)
            categoryRecords[index].label = categoryRecords[index].label.translated(by: offset)
        }
        for index in causes.indices { causes[index].text = causes[index].text.translated(by: offset) }
        headFrame = headFrame?.offsetBy(dx: offset.dx, dy: offset.dy)
        headLabel = headLabel.translated(by: offset)
    }

    /// The categories with their texts as blocks, made when read.
    var categories: [IshikawaLayoutCategory] {
        bytes.withUnsafeBufferPointer { source in
            categoryRecords.map { category in
                IshikawaLayoutCategory(boneLines: Array(boneLines[category.boneRange]), arrow: category.arrow, box: category.box,
                                       label: DiagramTextBlock(category.label, of: lines, source: source),
                                       causes: causes[category.causeRange].map { cause in
                                           IshikawaLayoutCause(text: DiagramTextBlock(cause.text, of: lines, source: source), isMuted: cause.isMuted)
                                       })
            }
        }
    }

    var head: IshikawaLayoutHead? {
        headFrame.map { frame in
            bytes.withUnsafeBufferPointer { source in IshikawaLayoutHead(frame: frame, label: DiagramTextBlock(headLabel, of: lines, source: source)) }
        }
    }
}
