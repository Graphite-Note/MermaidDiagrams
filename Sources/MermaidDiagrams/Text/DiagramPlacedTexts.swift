/**
 * File: DiagramPlacedTexts.swift
 * ------------------------------
 * Layer: Core
 * Description: Measured blocks kept by a layout as a few numbers each, without a reference to their text storage: the
 *              storages they were written in listed once beside them, so that a layout's flat records copy and free
 *              without reference counting and a block is made again only when it is read.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// A measured block where a layout keeps it: which of the layout's text storages holds its lines (`DiagramPlacedTextStorages`),
/// its record there, its size and its center. It copies as plain numbers; `DiagramPlacedTextStorages.block(_:)` makes the
/// block it stands for, equal to the one it was made from.
struct DiagramPlacedText: Sendable {
    var storageIndex: Int32
    var record: DiagramTextRecord
    var fontSize: CGFloat
    var lineHeight: CGFloat
    var center: CGPoint

    var lineCount: Int { Int(record.lineCount) }

    /// The block's size: its widest line by its lines' height, as `DiagramTextBlock.size` gives it.
    var size: CGSize { CGSize(width: record.widestLineWidth, height: CGFloat(record.lineCount) * lineHeight) }

    /// The rectangle around its center, as `DiagramTextBlock.frame` gives it.
    var frame: CGRect {
        let size = size
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

/// The text storages the placed texts of one layout were written in, each listed once, in the order they were met: most
/// layouts have one, the storage of the thread that measured them, which is kept without a list. A storage is looked for
/// where the last one was found, then at the end, then through the list, so that texts written one after the other in
/// one storage, or in storages of their own between them, are placed in constant time.
struct DiagramPlacedTextStorages: Sendable {
    /// The first storage met, index 0.
    private var first: DiagramTextStorage?
    /// The storages met after the first, from index 1.
    private var others: [DiagramTextStorage] = []
    /// Where the last storage was found.
    private var lastFound = 0

    /// How many storages are listed.
    var count: Int { first == nil ? 0 : 1 + others.count }

    /// `block` placed: its storage listed, its record, size and center kept.
    mutating func place(_ block: DiagramTextBlock) -> DiagramPlacedText {
        DiagramPlacedText(storageIndex: Int32(index(of: block.storage)), record: block.record, fontSize: block.fontSize,
                          lineHeight: block.lineHeight, center: block.center)
    }

    /// The block `text` stands for, its lines read from its storage as the block it was made from reads them.
    func block(_ text: DiagramPlacedText) -> DiagramTextBlock {
        DiagramTextBlock(storage: storage(at: Int(text.storageIndex)), record: text.record, fontSize: text.fontSize, lineHeight: text.lineHeight,
                         center: text.center)
    }

    @inline(__always)
    private func storage(at index: Int) -> DiagramTextStorage {
        if index == 0, let first { return first }
        precondition(index > 0 && index <= others.count, "a placed text of another layout's storages")
        return others[index - 1]
    }

    private mutating func index(of storage: DiagramTextStorage) -> Int {
        guard let first else {
            self.first = storage
            return 0
        }
        if first === storage { return 0 }
        if lastFound > 0, lastFound <= others.count, others[lastFound - 1] === storage { return lastFound }
        if let last = others.last, last === storage {
            lastFound = others.count
            return lastFound
        }
        for (index, listed) in others.enumerated() where listed === storage {
            lastFound = index + 1
            return lastFound
        }
        others.append(storage)
        lastFound = others.count
        return lastFound
    }
}
