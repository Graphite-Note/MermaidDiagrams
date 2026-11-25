/**
 * File: DiagramSVGScratch.swift
 * -----------------------------
 * Layer: Core
 * Description: One thread's block of bytes that SVG documents are written into one after another, kept between
 *              documents, and the escaped root style and font family of the last font written; a document begun while
 *              another is written on the thread gets a block of its own.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics
import Darwin

/// The bytes a thread's SVG documents are written into (`withThreadScratch`): the block is lent to each document's
/// buffer and given back, grown if it had to grow, so that a thread writing document after document allocates nothing
/// once its block holds its largest document. A block grown past `largestKeptByteCount` is freed when it comes back.
/// The root style and font a document writes (escaped, Pele's variables or none, `font-family:` and the font's family,
/// `;font-size:` and its size) are kept with the font and colors they are of, since a host writes the same few again and
/// again.
final class DiagramSVGScratch {
    private var block: UnsafeMutablePointer<UInt8>?
    private var blockCapacity = 0
    private var isLent = false

    /// The escaped root style and font last written, and what they are of.
    private(set) var rootStyle: [UInt8] = []
    private var rootStyleIsPeleVariables = false
    private var rootStylePostScriptName: String?
    private var rootStyleFontSize: CGFloat = 0
    private var hasRootStyle = false

    /// The bytes a block is made with, enough for most documents.
    static let firstBlockByteCount = 16 * 1_024
    /// The most bytes a thread keeps between documents.
    static let largestKeptByteCount = 1 << 20

    deinit {
        block?.deallocate()
    }

    private static let threadKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { scratch in Unmanaged<DiagramSVGScratch>.fromOpaque(scratch).release() }
        return key
    }()

    /// The calling thread's scratch, made on its first use and freed when the thread ends.
    static var current: DiagramSVGScratch {
        if let stored = pthread_getspecific(threadKey) { return Unmanaged<DiagramSVGScratch>.fromOpaque(stored).takeUnretainedValue() }
        let scratch = DiagramSVGScratch()
        pthread_setspecific(threadKey, Unmanaged.passRetained(scratch).toOpaque())
        return scratch
    }

    /// Runs `body` with the thread's scratch, or with one of its own when the thread's is lent to a document being
    /// written (a host writing a document from inside `DiagramSVGWriter.withDocumentBytes`).
    static func withThreadScratch<Result>(_ body: (DiagramSVGScratch) throws -> Result) rethrows -> Result {
        let threadScratch = current
        return try body(threadScratch.isLent ? DiagramSVGScratch() : threadScratch)
    }

    /// Lends the block, made if there is none, to a buffer; `takeBack` returns it.
    func lendBlock() -> (start: UnsafeMutablePointer<UInt8>, capacity: Int) {
        precondition(!isLent, "a scratch lends its block to one document at a time")
        isLent = true
        if let block { return (block, blockCapacity) }
        let made = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.firstBlockByteCount)
        block = made
        blockCapacity = Self.firstBlockByteCount
        return (made, blockCapacity)
    }

    /// Takes back the block lent, which the buffer may have replaced by a larger one; frees it past the largest kept.
    func takeBack(_ start: UnsafeMutablePointer<UInt8>, capacity: Int) {
        isLent = false
        guard capacity <= Self.largestKeptByteCount else {
            start.deallocate()
            block = nil
            blockCapacity = 0
            return
        }
        block = start
        blockCapacity = capacity
    }

    /// The bytes of the block kept, and where it is, for tests.
    var keptByteCount: Int { blockCapacity }
    var blockAddress: UnsafeMutablePointer<UInt8>? { block }

    /// Whether `rootStyle` is the root style and font of these colors and this font: the same size to the bit.
    func hasRootStyle(isPeleVariables: Bool, postScriptName: String?, fontSize: CGFloat) -> Bool {
        hasRootStyle && rootStyleIsPeleVariables == isPeleVariables && rootStyleFontSize.bitPattern == fontSize.bitPattern
            && rootStylePostScriptName == postScriptName
    }

    /// Keeps `bytes` as the root style and font of these colors and this font.
    func keepRootStyle(_ bytes: [UInt8], isPeleVariables: Bool, postScriptName: String?, fontSize: CGFloat) {
        rootStyle = bytes
        rootStyleIsPeleVariables = isPeleVariables
        rootStylePostScriptName = postScriptName
        rootStyleFontSize = fontSize
        hasRootStyle = true
    }
}
