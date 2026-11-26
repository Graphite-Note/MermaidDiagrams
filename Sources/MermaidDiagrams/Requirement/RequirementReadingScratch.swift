/**
 * File: RequirementReadingScratch.swift
 * -------------------------------------
 * Layer: Core
 * Description: The working lists a requirement diagram's reading fills and gives back (its name table, records,
 *              declarations, copies and the parser's lists), kept per thread so that a reading allocates only the
 *              lists its model keeps, each made at its exact size.
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

/// The lists a requirement diagram's reading works in: what the builder collects, then copies into the model at their
/// exact sizes, and the names, values and declaration parts of the statement the parser reads.
struct RequirementReadingLists {
    var names = GraphDiagramNameTable(isASCII: true)
    /// What each name number names, by the number.
    var namedByNumber: [RequirementNamed] = []
    /// The nodes given each class other than `default`, as lists from `RequirementNamed.firstMember`.
    var classMembers: [RequirementClassMember] = []
    /// Each node and class given, as `RequirementClassMember.key`, so that a node given a class twice is listed once.
    var givenClasses: Set<UInt64> = []
    var requirements: [RequirementNodeRecord] = []
    var elements: [RequirementNodeRecord] = []
    /// The relations, their ends' name numbers in `sourceBox` and `targetBox` until the diagram is finished.
    var relations: [RequirementRelationRecord] = []
    var styleClasses: [RequirementStyleClassRecord] = []
    /// The declarations read or given, as ranges of `derived`.
    var derived: [UInt8] = []
    var declarations: [MermaidTextRange] = []
    /// Each declaration copied onto a node and each class given to one, in the order they were made.
    var declarationCopies: [RequirementNodeEntry] = []
    var classGifts: [RequirementNodeClass] = []
    /// Each class's declarations as a list through `classDeclarationLinks`, from its `RequirementClassDeclarations.first`.
    var classDeclarationLists: [RequirementClassDeclarations] = []
    var classDeclarationLinks: [RequirementClassMember] = []
    /// The names and values of the statement the parser reads, and the parts of the declaration it reads.
    var statementNames: [Range<Int>] = []
    var statementValues: [Range<Int>] = []
    var declarationParts: [Range<Int>] = []

    /// Every list emptied for the reading of a text, ASCII or not, its room kept unless a long text left too much of it.
    mutating func reset(isASCII: Bool) {
        names.reset(isASCII: isASCII)
        Self.empty(&namedByNumber)
        Self.empty(&classMembers)
        if !givenClasses.isEmpty { givenClasses.removeAll(keepingCapacity: givenClasses.count <= Self.largestKeptCount) }
        Self.empty(&requirements)
        Self.empty(&elements)
        Self.empty(&relations)
        Self.empty(&styleClasses)
        Self.empty(&derived)
        Self.empty(&declarations)
        Self.empty(&declarationCopies)
        Self.empty(&classGifts)
        Self.empty(&classDeclarationLists)
        Self.empty(&classDeclarationLinks)
        Self.empty(&statementNames)
        Self.empty(&statementValues)
        Self.empty(&declarationParts)
    }

    /// The most entries a list keeps room for between readings.
    private static let largestKeptCount = 4_096

    private static func empty<Element>(_ list: inout [Element]) {
        if list.capacity > largestKeptCount { list = [] } else if !list.isEmpty { list.removeAll(keepingCapacity: true) }
    }

    /// A list of exactly `list`'s elements, made for the model to keep: an empty list makes nothing. Inlined, so that each
    /// kind of list's storage is made without looking its type up at run time.
    @inline(__always)
    static func exactCopy<Element>(_ list: [Element]) -> [Element] {
        guard !list.isEmpty else { return [] }
        return [Element](unsafeUninitializedCapacity: list.count) { buffer, initializedCount in
            _ = buffer.initialize(from: list)
            initializedCount = list.count
        }
    }
}

/// Working storage of the requirement readings of one thread, reused by the next reading on the same thread; never
/// shared between threads.
final class RequirementReadingScratch {
    /// The lists, nil while a reading has them.
    private var lists: RequirementReadingLists?

    /// Calls `body` with the calling thread's lists, emptied for a text ASCII or not and moved out of its scratch: a
    /// reading inside another on the same thread finds none there and makes its own.
    static func withLists<Result, Failure: Error>(isASCII: Bool, _ body: (inout RequirementReadingLists) throws(Failure) -> Result) throws(Failure) -> Result {
        let scratch = current
        var lists = scratch.lists.take() ?? RequirementReadingLists()
        lists.reset(isASCII: isASCII)
        defer { scratch.lists = lists }
        return try body(&lists)
    }

    /// The scratch of the calling thread, made the first time the thread reads a requirement diagram.
    private static var current: RequirementReadingScratch {
        if let pointer = pthread_getspecific(key) { return Unmanaged<RequirementReadingScratch>.fromOpaque(pointer).takeUnretainedValue() }
        let scratch = RequirementReadingScratch()
        pthread_setspecific(key, Unmanaged.passRetained(scratch).toOpaque())
        return scratch
    }

    private static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { pointer in Unmanaged<RequirementReadingScratch>.fromOpaque(pointer).release() }
        return key
    }()
}
