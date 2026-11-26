/**
 * File: FlowchartLayoutRecordBlock.swift
 * --------------------------------------
 * Layer: Core
 * Description: A laid-out flowchart's node, edge and segment records, with their text storages, styles and pictures, in
 *              one block of memory made once and only read after, read through small views that index it like lists, so
 *              that a layout costs one allocation for all its records, copies them as one reference and frees them in
 *              one step.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

/// How many records of each kind a block holds, and where each kind starts, in bytes from the block's elements.
struct FlowchartLayoutRecordCounts: Sendable {
    let nodeCount: Int
    let edgeCount: Int
    let segmentCount: Int
    let edgeOffset: Int
    let segmentOffset: Int

    init(nodeCount: Int, edgeCount: Int, segmentCount: Int) {
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.segmentCount = segmentCount
        edgeOffset = Self.roundedUp(nodeCount * MemoryLayout<FlowchartPlacedNode>.stride)
        segmentOffset = edgeOffset + Self.roundedUp(edgeCount * MemoryLayout<FlowchartPlacedEdge>.stride)
    }

    /// The words the three regions take.
    var wordCount: Int {
        (segmentOffset + segmentCount * MemoryLayout<DiagramPathSegment>.stride + MemoryLayout<FlowchartLayoutRecordWord>.stride - 1)
            / MemoryLayout<FlowchartLayoutRecordWord>.stride
    }

    private static func roundedUp(_ byteCount: Int) -> Int {
        let word = MemoryLayout<FlowchartLayoutRecordWord>.stride
        return (byteCount + word - 1) / word * word
    }
}

/// The unit a block is counted in: 16 bytes, which every record's alignment divides.
struct FlowchartLayoutRecordWord {
    var low: UInt64
    var high: UInt64
}

/// What a block keeps before its records: their counts, the text storages their texts were written in, and the styles
/// and icons or pictures of the few nodes and edges that have them.
struct FlowchartLayoutRecordHeader {
    let counts: FlowchartLayoutRecordCounts
    let textStorages: DiagramPlacedTextStorages
    let styles: [DiagramElementStyle]
    let assets: [FlowchartNodeAsset]
}

/// The records of one layout: nodes, then edges, then segments, each region aligned to a word, after the header, in one
/// allocation. Written once when it is made, then only read, so that a layout is handed between threads (hence sendable:
/// it is only read), and copied as one reference.
struct FlowchartLayoutRecordBlock: @unchecked Sendable {
    private let buffer: ManagedBuffer<FlowchartLayoutRecordHeader, FlowchartLayoutRecordWord>

    /// A block of `counts`, its regions written by `fill` with the start of each, which gives back the rest of the header:
    /// the storages of the texts it placed and the styles and assets it listed.
    static func make(counts: FlowchartLayoutRecordCounts,
                     fill: (UnsafeMutablePointer<FlowchartPlacedNode>, UnsafeMutablePointer<FlowchartPlacedEdge>, UnsafeMutablePointer<DiagramPathSegment>)
                         -> (textStorages: DiagramPlacedTextStorages, styles: [DiagramElementStyle], assets: [FlowchartNodeAsset]))
        -> FlowchartLayoutRecordBlock {
        let buffer = ManagedBuffer<FlowchartLayoutRecordHeader, FlowchartLayoutRecordWord>.create(minimumCapacity: counts.wordCount) { made in
            // The regions are written before the header, which `fill` completes.
            let rest = made.withUnsafeMutablePointerToElements { words in
                let base = UnsafeMutableRawPointer(words)
                return fill(base.bindMemory(to: FlowchartPlacedNode.self, capacity: counts.nodeCount),
                            (base + counts.edgeOffset).bindMemory(to: FlowchartPlacedEdge.self, capacity: counts.edgeCount),
                            (base + counts.segmentOffset).bindMemory(to: DiagramPathSegment.self, capacity: counts.segmentCount))
            }
            return FlowchartLayoutRecordHeader(counts: counts, textStorages: rest.textStorages, styles: rest.styles, assets: rest.assets)
        }
        return FlowchartLayoutRecordBlock(buffer: buffer)
    }

    /// The block of no records, shared.
    static let empty = make(counts: FlowchartLayoutRecordCounts(nodeCount: 0, edgeCount: 0, segmentCount: 0)) { _, _, _ in
        (DiagramPlacedTextStorages(), [], [])
    }

    /// Calls `body` with the header where the block keeps it.
    @inline(__always)
    func withHeader<Result>(_ body: (borrowing FlowchartLayoutRecordHeader) -> Result) -> Result {
        buffer.withUnsafeMutablePointerToHeader { header in body(header.pointee) }
    }

    var counts: FlowchartLayoutRecordCounts { withHeader { header in header.counts } }

    /// Calls `body` with the start of the region `offset` bytes into the elements, as `Record`, valid only inside it.
    @inline(__always)
    func withRegion<Record, Result>(at offset: Int, as type: Record.Type, _ body: (UnsafePointer<Record>) -> Result) -> Result {
        buffer.withUnsafeMutablePointerToElements { words in
            body(UnsafePointer((UnsafeMutableRawPointer(words) + offset).assumingMemoryBound(to: Record.self)))
        }
    }
}

/// One kind of a block's records, read as a list: a view that keeps the block alive.
struct FlowchartLayoutRecordList<Record>: RandomAccessCollection, Sendable {
    private let block: FlowchartLayoutRecordBlock
    private let offset: Int
    let count: Int

    init(block: FlowchartLayoutRecordBlock, offset: Int, count: Int) {
        self.block = block
        self.offset = offset
        self.count = count
    }

    var startIndex: Int { 0 }
    var endIndex: Int { count }

    @inline(__always)
    subscript(index: Int) -> Record {
        precondition(index >= 0 && index < count, "a record index outside the layout's records")
        return block.withRegion(at: offset, as: Record.self) { records in records[index] }
    }

    /// Calls `body` with records `range` where the block keeps them.
    func withRecords<Result>(in range: Range<Int>, _ body: (UnsafeBufferPointer<Record>) -> Result) -> Result {
        precondition(range.lowerBound >= 0 && range.upperBound <= count, "a record range outside the layout's records")
        return block.withRegion(at: offset, as: Record.self) { records in body(UnsafeBufferPointer(start: records + range.lowerBound, count: range.count)) }
    }
}
