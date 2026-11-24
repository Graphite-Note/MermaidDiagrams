/**
 * File: FlatReadingScratch.swift
 * ------------------------------
 * Layer: Core (design prototype, not for merging as is)
 * Description: The working lists a reading needs and gives back, kept per thread so that reading allocates only the
 *              lists its result keeps; and the table that interns names by their bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// One name read (a node's identifier, a group's), what it names, and its interning hash.
struct FlatNameEntry {
    var range: FlatTextRange
    var hash: UInt32
    var slot: Int32 = 0
    var nodeIndex: Int32 = -1
    var endedSubgraphIndex: Int32 = -1
    /// The serial of the open group that last listed the name as a member, so that a group lists a name once.
    var listedByGroupSerial: Int32 = -1
    var isTaken = false
    var isCollapsed = false
    var isEdgeIdentifier = false
}

/// A group open at the reading position.
struct FlatOpenSubgraph {
    /// The name index of the identifier written after `subgraph`, or -1 when Mermaid makes one as the group ends.
    var writtenName: Int32
    var writtenRange: FlatTextRange
    var title: FlatLabel
    var openingOrder: Int32
    var serial: Int32
    var direction: FlowchartDirection?
    /// Start of the group's members in `openMembers`.
    var membersStart: Int32
    /// Whether a group inside this one has ended: a name it listed may then be listed here already with another serial.
    var hasClosedChild = false
}

/// A group ended, its members a range of `endedMembers`.
struct FlatEndedSubgraph {
    var nameIndex: Int32
    var writtenRange: FlatTextRange
    /// The number in `subGraph<number>` when the identifier is Mermaid's, else -1.
    var generatedNumber: Int32
    var title: FlatLabel
    var direction: FlowchartDirection?
    var openingOrder: Int32
    var membersStart: Int32
    var membersCount: Int32
}

/// The working lists of a reading, moved out of the thread's scratch in one piece for the reading and back after it.
struct FlatReadingLists {
    /// Open addressing: name index + 1, 0 for an empty slot; a power of two long.
    var slots: [Int32] = Array(repeating: 0, count: 64)
    var names: [FlatNameEntry] = []
    var sideBytes: [UInt8] = []
    var groupIndices: [Int32] = []
    var openSubgraphs: [FlatOpenSubgraph] = []
    var openMembers: [Int32] = []
    var endedSubgraphs: [FlatEndedSubgraph] = []
    var endedMembers: [Int32] = []
    /// Positions of `direction` statements and of link identifiers' `@`, found only when the text holds them.
    var directionStatementStarts: [Int] = []
    var linkIdentifierEnds: [Int] = []

    mutating func reset() {
        for name in names { slots[Int(name.slot)] = 0 }
        names.removeAll(keepingCapacity: true)
        if !sideBytes.isEmpty { sideBytes.removeAll(keepingCapacity: true) }
        if !openSubgraphs.isEmpty { openSubgraphs.removeAll(keepingCapacity: true) }
        if !openMembers.isEmpty { openMembers.removeAll(keepingCapacity: true) }
        if !endedSubgraphs.isEmpty { endedSubgraphs.removeAll(keepingCapacity: true) }
        if !endedMembers.isEmpty { endedMembers.removeAll(keepingCapacity: true) }
        if !directionStatementStarts.isEmpty { directionStatementStarts.removeAll(keepingCapacity: true) }
        if !linkIdentifierEnds.isEmpty { linkIdentifierEnds.removeAll(keepingCapacity: true) }
    }
}

/// Working storage of a reading, reused by the next reading on the same thread.
final class FlatReadingScratch {
    var lists = FlatReadingLists()

    /// The scratch of the calling thread, made the first time the thread reads.
    static var current: FlatReadingScratch {
        if let pointer = pthread_getspecific(key) { return Unmanaged<FlatReadingScratch>.fromOpaque(pointer).takeUnretainedValue() }
        let scratch = FlatReadingScratch()
        pthread_setspecific(key, Unmanaged.passRetained(scratch).toOpaque())
        return scratch
    }

    private static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { pointer in Unmanaged<FlatReadingScratch>.fromOpaque(pointer).release() }
        return key
    }()
}
