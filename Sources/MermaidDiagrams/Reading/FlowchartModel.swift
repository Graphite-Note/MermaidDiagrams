/**
 * File: FlowchartModel.swift
 * --------------------------
 * Layer: Core
 * Description: A flowchart read into flat lists of small records whose names and texts are ranges of the text read:
 *              two lists for the usual diagram, its nodes and its edges, and one box for what few flowcharts have
 *              (groups, labels decoded while reading, icons and pictures, styles), all kept in one box so that the model
 *              copies as one reference.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

/// The text of a node, an edge or a group, by reference: none; the range that is the label's one line, trimmed and
/// without markup; the range of text written with markup, decoded by `DiagramLabelDecoder` in its plain or Markdown form
/// when it is read; or a label decoded while reading, by its index among the model's `decodedLabels`.
struct FlowchartLabelReference: Equatable, Sendable {
    enum Kind: UInt8, Sendable {
        case none
        case line
        case plain
        case markdown
        case decoded
    }

    var kind: Kind
    /// The text's range; for `decoded`, `start` is the label's index.
    var range: MermaidTextRange

    static let none = FlowchartLabelReference(kind: .none, range: .empty)

    static func decoded(at index: Int) -> FlowchartLabelReference {
        FlowchartLabelReference(kind: .decoded, range: MermaidTextRange(start: index, end: index))
    }

    /// The label of one line without markup, its bytes written into the thread's text storage as `DiagramLabelDecoder`
    /// writes a text it finds without markup; a debug build shows it to the decoding's observer, as the decoder does.
    static func lineLabel(_ bytes: UnsafeBufferPointer<UInt8>) -> DiagramLabel {
        let label = DiagramLabelWriting.oneLine(bytes, flags: .isReadWithoutMarkup)
        #if DEBUG
        DiagramLabelDecodingObservation.observer?(String(decoding: bytes, as: UTF8.self), .plain, label)
        #endif
        return label
    }
}

/// A node: its identifier's range, its text, its shape, and its icon's or picture's attributes by index, or -1.
struct FlowchartNodeRecord: Sendable {
    var identifier: MermaidTextRange
    var label: FlowchartLabelReference
    var shape: FlowchartNodeShape
    var assetIndex: Int32 = -1
}

/// An edge: its ends by node index, how it is drawn, and its text.
struct FlowchartEdgeRecord: Sendable {
    var sourceIndex: Int32
    var targetIndex: Int32
    var minimumRankSpan: Int32
    var stroke: FlowchartEdgeStroke
    var sourceArrowhead: FlowchartArrowhead
    var targetArrowhead: FlowchartArrowhead
    var label: FlowchartLabelReference
}

/// A group, each before the groups inside it: its identifier (written, or Mermaid's `subGraph` and a number), its
/// title, and what is directly inside it as ranges of the model's `groupMembers`.
struct FlowchartGroupRecord: Sendable {
    /// The identifier's range when `generatedNumber` is -1.
    var identifier: MermaidTextRange
    /// The number of Mermaid's identifier `subGraph<number>`, or -1 for an identifier written.
    var generatedNumber: Int32
    var title: FlowchartLabelReference
    var direction: FlowchartDirection?
    var representingNodeIndex: Int32
    var isCollapsed: Bool
    var nodeIndices: Range<Int32>
    var childGroupIndices: Range<Int32>
}

/// What few flowcharts have, kept in one box made only when a flowchart has any of it, and never changed after.
final class FlowchartModelExtras: Sendable {
    let groups: [FlowchartGroupRecord]
    /// Node indexes and group indexes, by the ranges of `groups`.
    let groupMembers: [Int32]
    let decodedLabels: [DiagramLabel]
    let assetAttributes: [FlowchartNodeAssetAttributes]
    /// One for each node and each edge when any statement styles the diagram, else empty.
    let nodeStyles: [DiagramElementStyle?]
    let edgeStyles: [DiagramElementStyle?]
    /// Identifiers that stand nowhere in the text (a node a `style` statement adds), by ranges whose start is negative:
    /// the bytes at `~start`.
    let sideBytes: [UInt8]

    init(groups: [FlowchartGroupRecord], groupMembers: [Int32], decodedLabels: [DiagramLabel], assetAttributes: [FlowchartNodeAssetAttributes],
         nodeStyles: [DiagramElementStyle?], edgeStyles: [DiagramElementStyle?], sideBytes: [UInt8]) {
        self.groups = groups
        self.groupMembers = groupMembers
        self.decodedLabels = decodedLabels
        self.assetAttributes = assetAttributes
        self.nodeStyles = nodeStyles
        self.edgeStyles = edgeStyles
        self.sideBytes = sideBytes
    }
}

/// A flowchart as flat lists, over the text it was read from: the usual diagram is its nodes and its edges. The lists
/// and the text are kept in one box that nothing changes once made (`FlowchartModelStorage`), so that a flowchart, which
/// its reading, its preparation and its layout hand on by value, copies as one reference.
struct FlowchartModel: Sendable {
    private let storage: FlowchartModelStorage

    init(text: MermaidSourceText, nodes: [FlowchartNodeRecord], edges: [FlowchartEdgeRecord], extras: FlowchartModelExtras?) {
        storage = FlowchartModelStorage(text: text, nodes: nodes, edges: edges, extras: extras)
    }

    var text: MermaidSourceText { storage.text }
    var nodes: [FlowchartNodeRecord] { storage.nodes }
    var edges: [FlowchartEdgeRecord] { storage.edges }
    var extras: FlowchartModelExtras? { storage.extras }

    /// The text of `range`: of the text read, or of the side bytes when its start is negative.
    func string(_ range: MermaidTextRange) -> String {
        guard range.start < 0 else { return text.string(range) }
        let start = Int(~range.start)
        let bytes = extras?.sideBytes ?? []
        return String(decoding: bytes[start..<start + range.count], as: UTF8.self)
    }

    /// The label a reference stands for, decoded now when it was written with markup; nil for none.
    func label(_ reference: FlowchartLabelReference) -> DiagramLabel? {
        switch reference.kind {
        case .none: nil
        case .line: lineLabel(reference.range)
        case .plain: DiagramLabelDecoder.label(from: string(reference.range), form: .plain)
        case .markdown: DiagramLabelDecoder.label(from: string(reference.range), form: .markdown)
        case .decoded: extras?.decodedLabels[reference.range.lowerBound]
        }
    }

    /// The label of the line at `range`, read from the text's bytes or the side bytes without making a String.
    private func lineLabel(_ range: MermaidTextRange) -> DiagramLabel {
        guard range.start < 0 else {
            return text.withBytes { bytes in FlowchartLabelReference.lineLabel(UnsafeBufferPointer(rebasing: bytes[range.lowerBound..<range.upperBound])) }
        }
        let start = Int(~range.start)
        return (extras?.sideBytes ?? []).withUnsafeBufferPointer { side in
            FlowchartLabelReference.lineLabel(UnsafeBufferPointer(rebasing: side[start..<start + range.count]))
        }
    }

    /// The identifier of the group at `index`.
    func groupIdentifier(_ group: FlowchartGroupRecord) -> String {
        group.generatedNumber >= 0 ? "subGraph\(group.generatedNumber)" : string(group.identifier)
    }
}

/// What a flowchart's model holds, made once and only read after.
final class FlowchartModelStorage: Sendable {
    let text: MermaidSourceText
    let nodes: [FlowchartNodeRecord]
    let edges: [FlowchartEdgeRecord]
    let extras: FlowchartModelExtras?

    init(text: MermaidSourceText, nodes: [FlowchartNodeRecord], edges: [FlowchartEdgeRecord], extras: FlowchartModelExtras?) {
        self.text = text
        self.nodes = nodes
        self.edges = edges
        self.extras = extras
    }
}
