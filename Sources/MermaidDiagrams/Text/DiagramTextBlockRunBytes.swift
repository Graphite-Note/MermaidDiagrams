/**
 * File: DiagramTextBlockRunBytes.swift
 * ------------------------------------
 * Layer: Core
 * Description: A text block's runs read where its storage keeps them, each as its UTF-8 bytes, its emphasis and its
 *              width, for the writers and the painter that need no String of a run.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramTextBlock {
    /// How many runs line `index` has, for a block with emphasis (`record.hasEmphasis`); `index` is below `lineCount`.
    func runCount(ofLine index: Int) -> Int {
        precondition(index >= 0 && index < lineCount, "line index out of range")
        return runRecords(ofLine: index).count
    }

    /// Calls `body` with each run of line `index` of a block with emphasis, in order: its bytes, valid in `body` only,
    /// its emphasis and its width, which `runs(ofLine:)` makes a String and a `DiagramTextRun` of. A block without
    /// emphasis has no run records; its lines are read with `withUTF8(ofLine:_:)`.
    func forEachRun(ofLine index: Int, _ body: (UnsafeBufferPointer<UInt8>, DiagramTextStyle, CGFloat) throws -> Void) rethrows {
        precondition(index >= 0 && index < lineCount, "line index out of range")
        precondition(record.hasEmphasis, "a block without emphasis has no run records")
        let (first, count) = runRecords(ofLine: index)
        try withExtendedLifetime(storage) {
            for runIndex in 0..<count {
                let run = storage.record(at: first, index: runIndex, as: DiagramTextRunRecord.self)
                try body(storage.bytes(from: run.start, to: run.end), run.style, run.width)
            }
        }
    }
}
