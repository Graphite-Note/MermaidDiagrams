/**
 * File: FlowchartReadingScratch.swift
 * -----------------------------------
 * Layer: Core
 * Description: The working lists a flowchart's reading needs and gives back (the name table, the open and ended
 *              groups, the look-ahead lists), kept per thread so that a reading allocates only the lists its model
 *              keeps.
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

/// A group open at the reading position.
struct FlowchartOpenGroup {
    /// The name of the identifier written after `subgraph`, or -1 when Mermaid makes one as the group ends.
    var writtenName: Int32
    var writtenIdentifier: MermaidTextRange
    var title: FlowchartLabelReference
    /// How many groups opened before this one, which also tells the group apart while it is open.
    var openingOrder: Int32
    var direction: FlowchartDirection?
    /// Where the group's members start in `FlowchartReadingLists.openMembers`.
    var membersStart: Int32
}

/// A name an open group listed, and the serial of the group that had listed it before, given back when this one ends.
struct FlowchartOpenMember {
    var name: Int32
    var previousListingSerial: Int32
}

/// A group ended: its identifier, and its members as a chain of runs of `FlowchartReadingLists.endedMembers` (a group
/// ended again under the same identifier adds a run).
struct FlowchartEndedGroup {
    var name: Int32
    var writtenIdentifier: MermaidTextRange
    /// The number in `subGraph<number>` when the identifier is Mermaid's, else -1.
    var generatedNumber: Int32
    var title: FlowchartLabelReference
    var direction: FlowchartDirection?
    var openingOrder: Int32
    var firstRun: Int32
    var lastRun: Int32
}

/// A run of an ended group's members, and the next run of the same group, or -1.
struct FlowchartMemberRun {
    var start: Int32
    var count: Int32
    var next: Int32
}

/// The working lists of a reading, moved out of the thread's scratch for the reading and back after it.
struct FlowchartReadingLists {
    var names = FlowchartNameTable()
    /// The node indexes of the node groups of the chain being read (`A & B --> C`).
    var chainNodes: [Int32] = []
    var openGroups: [FlowchartOpenGroup] = []
    var openMembers: [FlowchartOpenMember] = []
    var endedGroups: [FlowchartEndedGroup] = []
    var endedMembers: [Int32] = []
    var memberRuns: [FlowchartMemberRun] = []
    var lookAhead = FlowchartLookAheadLists()

    /// Empties the lists for another reading, keeping their room unless a large reading left too much of it.
    mutating func reset() {
        names.reset()
        if chainNodes.capacity > 4_096 { chainNodes = [] } else { chainNodes.removeAll(keepingCapacity: true) }
        if !openGroups.isEmpty { openGroups.removeAll(keepingCapacity: true) }
        if !openMembers.isEmpty { openMembers.removeAll(keepingCapacity: true) }
        if !endedGroups.isEmpty { endedGroups.removeAll(keepingCapacity: true) }
        if !endedMembers.isEmpty { endedMembers.removeAll(keepingCapacity: true) }
        if !memberRuns.isEmpty { memberRuns.removeAll(keepingCapacity: true) }
    }
}

/// Working storage of the flowchart readings of one thread, reused by the next reading on the same thread; never
/// shared between threads.
final class FlowchartReadingScratch {
    /// The lists, nil while a reading has them.
    private var lists: FlowchartReadingLists?

    /// Calls `body` with the calling thread's lists, moved out of its scratch: a reading inside another on the same
    /// thread finds none there and makes its own.
    static func withLists<Result>(_ body: (inout FlowchartReadingLists) -> Result) -> Result {
        let scratch = current
        var lists = scratch.lists.take() ?? FlowchartReadingLists()
        lists.reset()
        let result = body(&lists)
        scratch.lists = consume lists
        return result
    }

    /// The scratch of the calling thread, made the first time the thread reads.
    private static var current: FlowchartReadingScratch {
        if let pointer = pthread_getspecific(key) { return Unmanaged<FlowchartReadingScratch>.fromOpaque(pointer).takeUnretainedValue() }
        let scratch = FlowchartReadingScratch()
        pthread_setspecific(key, Unmanaged.passRetained(scratch).toOpaque())
        return scratch
    }

    private static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { pointer in Unmanaged<FlowchartReadingScratch>.fromOpaque(pointer).release() }
        return key
    }()
}
