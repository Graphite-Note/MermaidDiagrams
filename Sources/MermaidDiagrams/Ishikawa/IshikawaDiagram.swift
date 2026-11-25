/**
 * File: IshikawaDiagram.swift
 * ---------------------------
 * Layer: Core
 * Description: A Mermaid Ishikawa (fishbone) diagram as its text describes it: the effect, its categories of causes and
 *              their causes, nested by indentation, kept as small records of byte ranges into the text it was read from
 *              and each node's children in one list.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// A Mermaid Ishikawa diagram (`ishikawa-beta`, `ishikawa`): the first line is the effect, the fish's head; the lines
/// after it are causes, nested by their indentation relative to the first cause, so the effect may be indented more than
/// the causes. The effect's children are the categories, theirs the causes, and so on as deep as the text goes.
///
/// The diagram keeps the bytes it was read from and a record per node of where its text is in them; `nodes` makes the
/// node values when read. Two diagrams are equal when their nodes and titles are, wherever their texts were read from.
public struct IshikawaDiagram: Equatable, Sendable {
    /// The bytes the nodes' texts are ranges of: the text read, then the trimmed texts beyond ASCII (`derivedStart` on).
    let bytes: [UInt8]
    /// The effect first, then the causes in the order they are written, which is depth first.
    let records: [IshikawaNodeRecord]
    /// Node `index`'s children are `children[childStarts[index]..<childStarts[index + 1]]`, in the order written.
    let childStarts: [Int32]
    let children: [Int32]
    /// `title:` in the front matter, or nil: the diagram has no title statement.
    public internal(set) var title: String?

    init(bytes: [UInt8] = [], records: [IshikawaNodeRecord] = [], childStarts: [Int32] = [0], children: [Int32] = [], title: String? = nil) {
        self.bytes = bytes
        self.records = records
        self.childStarts = childStarts
        self.children = children
        self.title = title
    }

    /// How many nodes the diagram has: 0 when the text names none.
    var nodeCount: Int { records.count }

    /// The effect first, then the causes in the order they are written, made when read. Empty when the text names none.
    public var nodes: [IshikawaNode] {
        (0..<records.count).map { index in
            IshikawaNode(text: text(of: index), parentIndex: records[index].parent < 0 ? nil : Int(records[index].parent),
                         childIndices: childIndices(of: index).map { child in Int(child) })
        }
    }

    /// Node `index`'s text, made as a String.
    func text(of index: Int) -> String {
        withText(of: index) { text in String(decoding: text, as: UTF8.self) }
    }

    /// Calls `body` with node `index`'s text, borrowed.
    func withText<Result>(of index: Int, _ body: (UnsafeBufferPointer<UInt8>) -> Result) -> Result {
        let record = records[index]
        return bytes.withUnsafeBufferPointer { all in body(UnsafeBufferPointer(rebasing: all[Int(record.textStart)..<Int(record.textEnd)])) }
    }

    /// Node `index`'s children, in the order written.
    func childIndices(of index: Int) -> ArraySlice<Int32> {
        children[Int(childStarts[index])..<Int(childStarts[index + 1])]
    }

    /// The end of the nodes under node `index`, which follow it: the nodes run depth first, so a node after it is under
    /// it while its parent is it or a node after it.
    func subtreeEnd(of index: Int) -> Int {
        var end = index + 1
        while end < records.count, records[end].parent >= Int32(index) { end += 1 }
        return end
    }

    func childCount(of index: Int) -> Int {
        Int(childStarts[index + 1] - childStarts[index])
    }

    public static func == (first: IshikawaDiagram, second: IshikawaDiagram) -> Bool {
        guard first.title == second.title, first.records.count == second.records.count, first.children == second.children,
              first.childStarts == second.childStarts else { return false }
        for index in first.records.indices {
            guard first.records[index].parent == second.records[index].parent,
                  first.withText(of: index, { text in second.withText(of: index) { other in text.elementsEqual(other) } }) else { return false }
        }
        return true
    }
}

/// Where a node's text is in its diagram's bytes, and its parent's index, -1 for the effect.
struct IshikawaNodeRecord: Equatable, Sendable {
    var textStart: Int32
    var textEnd: Int32
    var parent: Int32
}

/// The effect or a cause.
public struct IshikawaNode: Equatable, Sendable {
    /// The line's text without the blanks around it.
    public let text: String
    /// The index of its parent in `IshikawaDiagram.nodes`, nil for the effect.
    public let parentIndex: Int?
    public internal(set) var childIndices: [Int] = []
}

extension IshikawaDiagram: TitledMermaidDiagram {}
