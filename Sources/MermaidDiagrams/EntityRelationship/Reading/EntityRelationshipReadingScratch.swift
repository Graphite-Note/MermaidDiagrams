/**
 * File: EntityRelationshipReadingScratch.swift
 * --------------------------------------------
 * Layer: Core
 * Description: The working lists an entity relationship diagram's reading fills and gives back (its name table, its
 *              records, the open and ended groups' names), kept per thread so that a reading allocates only the lists
 *              its model keeps, each made at its exact size.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// What a name names: the entity of that name, the first group to end with it as its identifier, each -1 for none,
/// whether a group that has ended holds it, and the last group closing that saw it, so that a group takes a name once.
struct EntityRelationshipNamed {
    var entityIndex: Int32 = -1
    var subgraphIndex: Int32 = -1
    var isClaimed = false
    var lastClosingThatSawIt: Int32 = -1
}

/// A `subgraph` open at the reading position: its identifier, title (an index of the labels), direction, and where the
/// names its statements write start in `writtenNames`.
struct EntityRelationshipOpenGroup {
    let identifier: MermaidTextRange
    let title: Int32
    var direction: FlowchartDirection?
    let firstWrittenName: Int
}

/// The lists an entity relationship diagram's reading works in, which the builder fills and copies into the model at
/// their exact sizes.
struct EntityRelationshipReadingLists {
    var names = GraphDiagramNameTable(isASCII: true)
    var namedByNumber: [EntityRelationshipNamed] = []
    var entities: [EntityRelationshipEntityRecord] = []
    /// The attributes in the order read, and each one's entity, which the model gathers entity by entity.
    var attributes: [EntityRelationshipAttributeRecord] = []
    var attributeOwners: [Int32] = []
    var keys: [EntityRelationshipAttributeKey] = []
    var relationships: [EntityRelationshipRelationshipRecord] = []
    var groups: [EntityRelationshipGroupRecord] = []
    var labels: [DiagramLabel] = []
    var openGroups: [EntityRelationshipOpenGroup] = []
    /// The names the open groups' statements write, by number, each group's after those of the groups around it.
    var writtenNames: [Int32] = []
    /// For each group that has ended, in that order, the names it holds, by number: `heldNames` from `heldNameStarts`.
    var heldNames: [Int32] = []
    var heldNameStarts: [Int32] = []
    /// The keys of the attribute being read.
    var attributeKeys: [EntityRelationshipAttributeKey] = []

    /// Every list emptied for the reading of a text, ASCII or not, its room kept unless a long text left too much of it.
    mutating func reset(isASCII: Bool) {
        names.reset(isASCII: isASCII)
        Self.empty(&namedByNumber)
        Self.empty(&entities)
        Self.empty(&attributes)
        Self.empty(&attributeOwners)
        Self.empty(&keys)
        Self.empty(&relationships)
        Self.empty(&groups)
        if !labels.isEmpty { labels = [] }
        Self.empty(&openGroups)
        Self.empty(&writtenNames)
        Self.empty(&heldNames)
        Self.empty(&heldNameStarts)
        Self.empty(&attributeKeys)
    }

    /// The most entries a list keeps room for between readings.
    private static let largestKeptCount = 4_096

    private static func empty<Element>(_ list: inout [Element]) {
        if list.capacity > largestKeptCount { list = [] } else if !list.isEmpty { list.removeAll(keepingCapacity: true) }
    }
}

/// Working storage of the entity relationship readings of one thread, reused by the next reading on the same thread;
/// never shared between threads.
final class EntityRelationshipReadingScratch {
    /// The lists, nil while a reading has them.
    private var lists: EntityRelationshipReadingLists?

    /// Calls `body` with the calling thread's lists, emptied for a text ASCII or not and moved out of its scratch: a
    /// reading inside another on the same thread finds none there and makes its own.
    static func withLists<Result, Failure: Error>(isASCII: Bool, _ body: (inout EntityRelationshipReadingLists) throws(Failure) -> Result) throws(Failure)
        -> Result {
        let scratch = current
        // The lists are moved in and out by swapping, never copied: a copy would make every list's first change copy it.
        var lists: EntityRelationshipReadingLists? = scratch.lists.take() ?? EntityRelationshipReadingLists()
        lists?.reset(isASCII: isASCII)
        defer { swap(&scratch.lists, &lists) }
        return try body(&lists!)
    }

    /// The scratch of the calling thread, made the first time the thread reads an entity relationship diagram.
    private static var current: EntityRelationshipReadingScratch {
        if let pointer = pthread_getspecific(key) {
            return Unmanaged<EntityRelationshipReadingScratch>.fromOpaque(pointer).takeUnretainedValue()
        }
        let scratch = EntityRelationshipReadingScratch()
        pthread_setspecific(key, Unmanaged.passRetained(scratch).toOpaque())
        return scratch
    }

    private static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { pointer in Unmanaged<EntityRelationshipReadingScratch>.fromOpaque(pointer).release() }
        return key
    }()
}
