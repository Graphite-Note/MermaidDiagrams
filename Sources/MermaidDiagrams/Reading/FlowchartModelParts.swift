/**
 * File: FlowchartModelParts.swift
 * -------------------------------
 * Layer: Core
 * Description: The lists of a flowchart's model as its reading fills them, made into the model when the reading ends:
 *              the box of what few flowcharts have is made only when one of its lists holds anything.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// The lists of a flowchart's model that few flowcharts fill, in one box made when the first is written to.
final class FlowchartRareModelParts {
    var groups: [FlowchartGroupRecord] = []
    var groupMembers: [Int32] = []
    var decodedLabels: [DiagramLabel] = []
    var assetAttributes: [FlowchartNodeAssetAttributes] = []
    var nodeStyles: [DiagramElementStyle?] = []
    var edgeStyles: [DiagramElementStyle?] = []
    var sideBytes: [UInt8] = []
}

/// A flowchart's model while it is read: its nodes and edges, and the box of the rest when anything is in it.
struct FlowchartModelParts {
    var nodes: [FlowchartNodeRecord] = []
    var edges: [FlowchartEdgeRecord] = []
    private(set) var rareIfAny: FlowchartRareModelParts?

    /// The box of the rarer lists, made when it is first asked for.
    var rare: FlowchartRareModelParts {
        mutating get {
            if let rareIfAny { return rareIfAny }
            let made = FlowchartRareModelParts()
            rareIfAny = made
            return made
        }
    }

    /// The model over `text`, its lists moved out of these parts, which are left empty.
    mutating func takeModel(text: MermaidSourceText) -> FlowchartModel {
        let extras = rareIfAny.map { rare in
            FlowchartModelExtras(groups: rare.groups, groupMembers: rare.groupMembers, decodedLabels: rare.decodedLabels,
                                 assetAttributes: rare.assetAttributes, nodeStyles: rare.nodeStyles, edgeStyles: rare.edgeStyles, sideBytes: rare.sideBytes)
        }
        rareIfAny = nil
        return FlowchartModel(text: text, nodes: Self.taken(&nodes), edges: Self.taken(&edges), extras: extras)
    }

    /// The list, moved out, and an empty one left in its place.
    private static func taken<Element>(_ list: inout [Element]) -> [Element] {
        var moved: [Element] = []
        swap(&moved, &list)
        return moved
    }

    /// The text of `range`, of the text read or of the side bytes.
    func string(_ range: MermaidTextRange, in bytes: FlowchartBytes) -> String {
        guard range.start < 0 else { return bytes.string(from: range.lowerBound, to: range.upperBound) }
        let start = Int(~range.start)
        return String(decoding: (rareIfAny?.sideBytes ?? [])[start..<start + range.count], as: UTF8.self)
    }

    /// The label a reference stands for, decoded now.
    func label(_ reference: FlowchartLabelReference, in bytes: FlowchartBytes) -> DiagramLabel? {
        switch reference.kind {
        case .none: nil
        case .line: DiagramLabel(lines: [string(reference.range, in: bytes)])
        case .plain: DiagramLabelDecoder.label(from: string(reference.range, in: bytes), form: .plain)
        case .markdown: DiagramLabelDecoder.label(from: string(reference.range, in: bytes), form: .markdown)
        case .decoded: rareIfAny?.decodedLabels[reference.range.lowerBound]
        }
    }

    /// `bytes` added to the side bytes, by their range there.
    mutating func sideRange(of bytes: [UInt8]) -> MermaidTextRange {
        let side = rare
        let start = side.sideBytes.count
        side.sideBytes.append(contentsOf: bytes)
        return MermaidTextRange(start: Int(~Int32(start)), end: Int(~Int32(start)) + bytes.count)
    }
}
