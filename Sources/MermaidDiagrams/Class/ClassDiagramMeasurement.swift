/**
 * File: ClassDiagramMeasurement.swift
 * -----------------------------------
 * Layer: Core
 * Description: A class diagram's text measured and its nodes sized, before the layout places anything.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.8
 * Date: 26/11/2026
 */

import CoreGraphics

/// The fonts a class diagram's text is measured in, as Pele sizes them: class names and the title in bold at the
/// note's size; members, notes, interfaces and relation text at seven eighths of it; annotations and cardinalities at
/// four fifths; namespaces' titles in the regular weight at the note's size.
struct ClassDiagramTextMeasurers<Measurer: DiagramTextMeasuring> {
    let names: Measurer
    let members: Measurer
    let marks: Measurer
    let namespaceTitles: Measurer

    /// Namespaces' titles in `namespaceTitles`, or in the names' measurer when none is given.
    init(names: Measurer, members: Measurer, marks: Measurer, namespaceTitles: Measurer? = nil) {
        self.names = names
        self.members = members
        self.marks = marks
        self.namespaceTitles = namespaceTitles ?? names
    }

    /// The height of a row of annotations or cardinalities: 1.4 times their size, rounded, as in Pele.
    var markRowHeight: CGFloat { (marks.fontSize * ClassDiagramBox.markRowHeightRatio).rounded() }
}

/// A class diagram's text measured and its nodes sized: what the layout needs before it places anything. Its nodes
/// are the classes, then the notes, then the interfaces of lollipop ends, in Pele's order; its edges are the lines
/// from notes to their classes, then the relations.
struct ClassDiagramMeasurement {
    /// A node's kind, with the index of what it draws.
    enum Node {
        case classBox(Int)
        case note(Int)
        case interface(Int)
    }

    /// An edge between two nodes, with its text measured.
    struct Edge {
        let source: Int
        let target: Int
        let sourceEnd: ClassDiagramRelationEnd
        let targetEnd: ClassDiagramRelationEnd
        let line: ClassDiagramLineStyle
        /// The relation's index, or nil for a note's line.
        let relationIndex: Int?
        let text: DiagramMeasuredText?
        let sourceCardinality: DiagramMeasuredText?
        let targetCardinality: DiagramMeasuredText?

        var isSelfLoop: Bool { source == target }
    }

    static let noteWrappingWidth: CGFloat = 260
    static let textWrappingWidth: CGFloat = 200
    static let notePadding = CGSize(width: 12, height: 8)
    static let noteMinimumWidth: CGFloat = 40
    /// An interface's name takes 2 points more on each side, and is 12 points across at least.
    static let interfaceMargin: CGFloat = 2
    static let interfaceMinimumExtent: CGFloat = 12
    /// When several relations leave or reach a class, the gap each needs along its side: 14 points, or the widest
    /// cardinality there and 24 more; the box is widened to that, up to 480 points, in a flow that runs down.
    static let crowdedEndGap: CGFloat = 14
    static let crowdedCardinalityGap: CGFloat = 24
    static let crowdedSideClearance: CGFloat = 24
    static let crowdedMaximumWidth: CGFloat = 480

    private(set) var nodes: [Node] = []
    private(set) var sizes: [CGSize] = []
    private(set) var boxes: [ClassDiagramBox] = []
    /// The lines of every text measured here, and the boxes' annotations and members.
    var texts = ClassDiagramMeasuredTexts()
    /// The diagram's text, which the lines read as written point into.
    let source: MermaidSourceText
    private(set) var noteTexts: [DiagramMeasuredText] = []
    private(set) var interfaceTexts: [DiagramMeasuredText] = []
    private(set) var edges: [Edge] = []

    init<Measurer: DiagramTextMeasuring>(diagram: ClassDiagram, measurers: ClassDiagramTextMeasurers<Measurer>) {
        let model = diagram.model
        source = model.text
        // Each relation may name an interface of its own.
        let nodeCapacity = model.classes.count + model.notes.count + model.relations.count
        nodes.reserveCapacity(nodeCapacity)
        sizes.reserveCapacity(nodeCapacity)
        boxes.reserveCapacity(model.classes.count)
        noteTexts.reserveCapacity(model.notes.count)
        edges.reserveCapacity(model.notes.count + model.relations.count)
        // A line a name, member and annotation, two a note, and four a relation with its cardinalities; the members' and
        // cardinalities' bytes are copied into the lines' own.
        texts.lines.reserveCapacity(lines: model.classes.count + model.members.count + model.annotations.count + 2 * model.notes.count
                                        + 4 * model.relations.count + 2, derivedBytes: model.memberBytes.count + 8 * model.relations.count)
        texts.members.reserveCapacity(model.members.count)
        texts.annotations.reserveCapacity(model.annotations.count)
        interfaceTexts.reserveCapacity(model.interfaces.count)
        model.text.withBytes { source in
            let measuring = ClassDiagramTextMeasuring(measurers, source: source)
            for classIndex in model.classes.indices {
                let box = ClassDiagramBox(classAt: classIndex, of: model, measuring: measuring, hidesEmptySections: diagram.hidesEmptyMemberBoxes, into: &texts)
                nodes.append(.classBox(boxes.count))
                boxes.append(box)
                sizes.append(box.size)
            }
            measureNotes(of: model, measuring: measuring)
            for (relationIndex, relation) in model.relations.enumerated() {
                let text = relation.label.isNone ? nil
                    : measuring.measure(relation.label, of: model, measurer: measuring.members, maximumWidth: Self.textWrappingWidth, into: &texts.lines)
                edges.append(Edge(source: node(for: relation.source, of: model, measuring: measuring), target: node(for: relation.target, of: model, measuring: measuring),
                                  sourceEnd: relation.sourceEnd, targetEnd: relation.targetEnd, line: relation.line, relationIndex: relationIndex,
                                  text: text.flatMap { text in text.lineCount == 0 ? nil : text },
                                  sourceCardinality: cardinality(relation.sourceCardinality, measuring: measuring),
                                  targetCardinality: cardinality(relation.targetCardinality, measuring: measuring)))
            }
        }
    }

    /// The notes' sheets, then the dotted lines from notes to the classes they are for.
    private mutating func measureNotes<Measurer>(of model: ClassDiagramModel, measuring: ClassDiagramTextMeasuring<Measurer>) {
        let firstNoteNode = nodes.count
        for note in model.notes {
            let text = measuring.measure(note.text, of: model, measurer: measuring.members, maximumWidth: Self.noteWrappingWidth, into: &texts.lines)
            nodes.append(.note(noteTexts.count))
            noteTexts.append(text)
            sizes.append(CGSize(width: max(text.width + 2 * Self.notePadding.width, Self.noteMinimumWidth), height: text.height + 2 * Self.notePadding.height))
        }
        for (noteIndex, note) in model.notes.enumerated() where note.classIndex >= 0 {
            edges.append(Edge(source: firstNoteNode + noteIndex, target: Int(note.classIndex), sourceEnd: .none, targetEnd: .none, line: .dotted,
                              relationIndex: nil, text: nil, sourceCardinality: nil, targetCardinality: nil))
        }
    }

    /// The node an end names: its class's, or a new node for an interface of its own.
    private mutating func node<Measurer>(for end: Int32, of model: ClassDiagramModel, measuring: ClassDiagramTextMeasuring<Measurer>) -> Int {
        guard let interface = ClassDiagramRelationRecord.interfaceIndex(of: end) else { return Int(end) }
        let text = measuring.measureInterface(at: interface, of: model, maximumWidth: Self.textWrappingWidth, into: &texts.lines)
        nodes.append(.interface(interfaceTexts.count))
        interfaceTexts.append(text)
        sizes.append(CGSize(width: max(text.width, Self.interfaceMinimumExtent) + 2 * Self.interfaceMargin, height: max(text.height, Self.interfaceMinimumExtent)))
        return nodes.count - 1
    }

    /// A cardinality, as `DiagramLabel(text)` measures in the marks' font, unwrapped.
    private mutating func cardinality<Measurer>(_ text: String?, measuring: ClassDiagramTextMeasuring<Measurer>) -> DiagramMeasuredText? {
        text.map { text in
            DiagramFlatTextMeasuring.measure(writtenLine: text, measurer: measuring.marks, maximumWidth: .greatestFiniteMagnitude, into: &texts.lines)
        }
    }

    mutating func widenCrowdedClasses() {
        // Each node's leaving side, then its reaching side, in one list of a struct (a list of tuples looks its element's
        // metadata up each time it is made).
        let nodeCount = nodes.count
        var sides = [CrowdedSide](repeating: CrowdedSide(count: 0, room: 0), count: 2 * nodeCount)
        for edge in edges where !edge.isSelfLoop {
            sides[edge.source].count += 1
            sides[edge.source].room = max(sides[edge.source].room, edge.sourceCardinality?.width ?? 0)
            sides[nodeCount + edge.target].count += 1
            sides[nodeCount + edge.target].room = max(sides[nodeCount + edge.target].room, edge.targetCardinality?.width ?? 0)
        }
        for (node, kind) in nodes.enumerated() {
            guard case .classBox(let boxIndex) = kind else { continue }
            let needed = min(Self.crowdedMaximumWidth, max(Self.crowdedWidth(sides[node]), Self.crowdedWidth(sides[nodeCount + node])))
            guard needed > sizes[node].width else { continue }
            sizes[node].width = needed
            boxes[boxIndex].size.width = needed
        }
    }

    /// How many relations leave or reach a class, and the widest cardinality among them.
    private struct CrowdedSide {
        var count: Int
        var room: CGFloat
    }

    private static func crowdedWidth(_ side: CrowdedSide) -> CGFloat {
        guard side.count > 1 else { return 0 }
        let gap = side.room > 0 ? side.room + crowdedCardinalityGap : crowdedEndGap
        return CGFloat(side.count - 1) * gap + crowdedSideClearance
    }

    /// For each node, the indexes of its edges to itself, in their order; empty when no node has one.
    var selfLoopEdgeIndices: [[Int]] {
        guard edges.contains(where: \.isSelfLoop) else { return [] }
        var loops = [[Int]](repeating: [], count: nodes.count)
        for (edgeIndex, edge) in edges.enumerated() where edge.isSelfLoop { loops[edge.source].append(edgeIndex) }
        return loops
    }

    /// Each node's size in its rank: its drawn size, widened on both sides by the room its loops take beside it.
    /// `selfLoops` is empty for a diagram without loops.
    func layoutSizes(selfLoops: [[Int]]) -> [CGSize] {
        guard !selfLoops.isEmpty else { return sizes }
        return sizes.enumerated().map { node, size in
            let room = selfLoops[node].reduce(0) { room, edgeIndex in room + ClassDiagramSelfLoops.room(textWidth: edges[edgeIndex].text?.size.width) }
            return CGSize(width: size.width + 2 * room, height: size.height)
        }
    }
}
