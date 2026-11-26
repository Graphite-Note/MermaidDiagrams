/**
 * File: RequirementMeasurement.swift
 * ----------------------------------
 * Layer: Core
 * Description: A requirement diagram's boxes and relations measured as Pele's requirement renderer measures them: the
 *              stereotype, the bold name and the rows of fields of each box, and each relation's text, every text
 *              measured on the flat path from the records' ranges of the diagram's text into the measurement's one list
 *              of lines and kept as a measured text, the boxes, rows and edges in lists of the thread's arena.
 *
 * Authors: Bahey Shalash
 * Version: 0.5
 * Date: 26/11/2026
 */

import CoreGraphics

/// The measurers of a requirement diagram's text: the names in the nodes' font in bold, and the stereotypes, fields,
/// values and relations' texts at seven eighths of it, as Pele's renderer measures them.
struct RequirementTextMeasurers<Measurer: DiagramTextMeasuring> {
    let names: Measurer
    let body: Measurer
}

/// One box measured: its stereotype, its name and its rows of fields (`rowCount` rows of the measurement's `rows` from
/// `firstRow`), the widest field name, the height of its head and its size, the room its loops take kept apart, and its
/// look: `styleIndex` in the measurement's `styles`, -1 for the usual look.
struct RequirementMeasuredBox {
    let isRequirement: Bool
    let stereotype: DiagramMeasuredText
    let name: DiagramMeasuredText
    let firstRow: Int32
    let rowCount: Int32
    let keyWidth: CGFloat
    let headHeight: CGFloat
    let size: CGSize
    let styleIndex: Int32

    var rowIndices: Range<Int> { Int(firstRow)..<Int(firstRow + rowCount) }
}

/// A row of a box: a field's name and its value, and the taller one's height.
struct RequirementMeasuredRow {
    let key: DiagramMeasuredText
    let value: DiagramMeasuredText
    let height: CGFloat
}

/// A relation that joins two boxes drawn: the relation it draws, its ends by box, its text, `«kind»`, and for a relation
/// from a box to itself the number of the box's loops before it, -1 for any other.
struct RequirementMeasuredEdge {
    let relationIndex: Int32
    let kind: RequirementRelationKind
    let source: Int32
    let target: Int32
    let text: DiagramMeasuredText
    let loopIndex: Int32

    var isSelfLoop: Bool { source == target }
    var isContainment: Bool { kind == .contains }
}

/// A requirement diagram measured, its boxes the requirements then the elements, as Mermaid orders them, and its edges the
/// relations whose two names are declared, in the order written: what the layout needs before it places anything. Every
/// text is a measured text of `lines`, measured as `DiagramTextBlock` measures the same label (`DiagramFlatTextMeasuring`),
/// from the diagram's text where it is written there. The boxes, rows and edges are lists of the calling thread's arena,
/// valid while the layout runs.
struct RequirementMeasurement {
    /// Pele's measurements: 14 points of padding across a box and 10 along it, 2 between rows, 12 between a row's name and
    /// value, boxes at least 120 points wide, names wrapped at 280 points and values at 240.
    static let paddingAcross: CGFloat = 14
    static let paddingAlong: CGFloat = 10
    static let rowGap: CGFloat = 2
    static let columnGap: CGFloat = 12
    static let minimumWidth: CGFloat = 120
    static let nameWrappingWidth: CGFloat = 280
    static let valueWrappingWidth: CGFloat = 240
    /// A text that is not wrapped: the stereotype, a field's name, a relation's text.
    static let unwrapped: CGFloat = 4000
    /// The room a relation's text takes beyond its lines.
    static let edgeTextRoom = CGSize(width: 12, height: 4)

    /// The lines of every text measured, the title's too once the layout measures it.
    var lines = DiagramMeasuredLines()
    private(set) var boxes: ScratchList<RequirementMeasuredBox>
    private(set) var rows: ScratchList<RequirementMeasuredRow>
    private(set) var edges: ScratchList<RequirementMeasuredEdge>
    /// The looks the diagram's styles give the boxes that have one, each box's at its `styleIndex`.
    private(set) var styles: [DiagramElementStyle] = []
    /// `RequirementDiagram.unappliedStatementCount`, counted as the boxes' styles are resolved.
    private(set) var unappliedStatementCount = 0

    init<Measurer: DiagramTextMeasuring>(diagram: RequirementDiagram, measurers: RequirementTextMeasurers<Measurer>, arena: DiagramScratchArena) {
        let model = diagram.model
        boxes = arena.list(capacity: model.boxCount, of: RequirementMeasuredBox.self)
        rows = arena.list(capacity: 4 * model.requirementCount + 2 * model.elementCount, of: RequirementMeasuredRow.self)
        edges = arena.list(capacity: model.relations.count, of: RequirementMeasuredEdge.self)
        var styleResolution = RequirementStyleResolution(model: model)
        var texts = RequirementConstantTexts(measurers: measurers, arena: arena)
        let names = DiagramFlatMeasurer(measurers.names)
        lines.reserveCapacity(lines: 16 + 8 * model.requirementCount + 5 * model.elementCount, derivedBytes: 256)
        model.text.withUnsafeBufferPointer { bytes in
            for record in model.requirements {
                var box = startBox(name: record.name, of: bytes, stereotype: texts.stereotype(of: record.kind, into: &lines), names: names)
                appendRow(.identifier, record.firstField, of: bytes, to: &box, texts: &texts)
                appendRow(.text, record.secondField, of: bytes, to: &box, texts: &texts)
                if let risk = record.risk { appendRow(.risk, texts.value(of: risk, into: &lines), to: &box, texts: &texts) }
                if let method = record.verificationMethod { appendRow(.verification, texts.value(of: method, into: &lines), to: &box, texts: &texts) }
                finishBox(box, isRequirement: true, style: styleResolution.style(of: record))
            }
            for record in model.elements {
                var box = startBox(name: record.name, of: bytes, stereotype: texts.elementStereotype(into: &lines), names: names)
                appendRow(.type, record.firstField, of: bytes, to: &box, texts: &texts)
                appendRow(.documentReference, record.secondField, of: bytes, to: &box, texts: &texts)
                finishBox(box, isRequirement: false, style: styleResolution.style(of: record))
            }
        }
        unappliedStatementCount = styleResolution.unappliedCount
        measureEdges(of: model, texts: &texts, arena: arena)
    }

    /// The relations whose two names are declared, each with its text; a requirement and an element may share a name, and
    /// relations then go to the requirement (`RequirementRelationRecord`). A loop's index counts the box's loops before it.
    private mutating func measureEdges<Measurer>(of model: RequirementModel, texts: inout RequirementConstantTexts<Measurer>, arena: DiagramScratchArena) {
        let loopCounts = arena.span(count: boxes.count, repeating: Int32(0))
        for (relationIndex, relation) in model.relations.enumerated() {
            guard relation.sourceBox >= 0, relation.targetBox >= 0 else { continue }
            var loopIndex: Int32 = -1
            if relation.sourceBox == relation.targetBox {
                loopIndex = loopCounts[Int(relation.sourceBox)]
                loopCounts[Int(relation.sourceBox)] += 1
            }
            edges.append(RequirementMeasuredEdge(relationIndex: Int32(relationIndex), kind: relation.kind, source: relation.sourceBox, target: relation.targetBox,
                                                 text: texts.relationText(of: relation.kind, into: &lines), loopIndex: loopIndex))
        }
    }

    /// A box being measured, as Pele's `draw` measures a node: its stereotype and name, then its rows as they are added.
    private struct BoxInProgress {
        let stereotype: DiagramMeasuredText
        let name: DiagramMeasuredText
        let firstRow: Int
        var keyWidth: CGFloat = 0
        var valueWidth: CGFloat = 0
        var bodyHeight: CGFloat = 0
    }

    /// The box's name, `bytes[name]`, read as Markdown, and its stereotype.
    private mutating func startBox<Measurer>(name: MermaidTextRange, of bytes: UnsafeBufferPointer<UInt8>, stereotype: DiagramMeasuredText,
                                             names: DiagramFlatMeasurer<Measurer>) -> BoxInProgress {
        let nameText = DiagramFlatTextMeasuring.measure(markdown: bytes, name, measurer: names, maximumWidth: Self.nameWrappingWidth, into: &lines)
        return BoxInProgress(stereotype: stereotype, name: nameText, firstRow: rows.count)
    }

    /// The row of a field whose value, `bytes[value]`, is Markdown; a field of empty text is left out.
    private mutating func appendRow<Measurer>(_ key: RequirementFieldKey, _ value: MermaidTextRange, of bytes: UnsafeBufferPointer<UInt8>,
                                              to box: inout BoxInProgress, texts: inout RequirementConstantTexts<Measurer>) {
        guard !value.isEmpty else { return }
        let valueText = DiagramFlatTextMeasuring.measure(markdown: bytes, value, measurer: texts.body, maximumWidth: Self.valueWrappingWidth, into: &lines)
        appendRow(key, valueText, to: &box, texts: &texts)
    }

    /// The row of a field and its value measured.
    private mutating func appendRow<Measurer>(_ key: RequirementFieldKey, _ valueText: DiagramMeasuredText, to box: inout BoxInProgress,
                                              texts: inout RequirementConstantTexts<Measurer>) {
        let keyText = texts.key(key, into: &lines)
        let height = max(keyText.size.height, valueText.size.height)
        rows.append(RequirementMeasuredRow(key: keyText, value: valueText, height: height))
        box.keyWidth = max(box.keyWidth, keyText.size.width)
        box.valueWidth = max(box.valueWidth, valueText.size.width)
        box.bodyHeight += height + Self.rowGap
    }

    /// The box's size from its head and rows.
    private mutating func finishBox(_ box: BoxInProgress, isRequirement: Bool, style: DiagramElementStyle?) {
        let rowCount = rows.count - box.firstRow
        let bodyHeight = rowCount > 0 ? box.bodyHeight + (2 * Self.paddingAlong - Self.rowGap) : box.bodyHeight
        let headHeight = 2 * Self.paddingAlong + box.stereotype.size.height + box.name.size.height
        let width = max(Self.minimumWidth, max(box.stereotype.size.width, box.name.size.width) + 2 * Self.paddingAcross,
                        rowCount == 0 ? 0 : box.keyWidth + Self.columnGap + box.valueWidth + 2 * Self.paddingAcross)
        var styleIndex: Int32 = -1
        if let style {
            styleIndex = Int32(styles.count)
            styles.append(style)
        }
        boxes.append(RequirementMeasuredBox(isRequirement: isRequirement, stereotype: box.stereotype, name: box.name, firstRow: Int32(box.firstRow),
                                            rowCount: Int32(rowCount), keyWidth: box.keyWidth, headHeight: headHeight,
                                            size: CGSize(width: width, height: headHeight + bodyHeight), styleIndex: styleIndex))
    }

    /// The look of a box measured: its style, or nil for the usual look.
    func style(of box: RequirementMeasuredBox) -> DiagramElementStyle? {
        box.styleIndex >= 0 ? styles[Int(box.styleIndex)] : nil
    }

    /// Each box's size in its rank: its own, grown on both sides across the flow by each of its loops, as Pele grows the
    /// node it lays out (`RequirementSelfLoops.room`), in the order its loops are written.
    func layoutSizes(flowIsVertical: Bool, arena: DiagramScratchArena) -> ScratchSpan<CGSize> {
        let sizes: ScratchSpan<CGSize> = arena.uninitializedSpan(count: boxes.count)
        for box in 0..<boxes.count { sizes[box] = boxes[box].size }
        for edge in edges where edge.loopIndex >= 0 {
            let room = RequirementSelfLoops.room(textSize: edge.text.size, flowIsVertical: flowIsVertical)
            if flowIsVertical { sizes[Int(edge.source)].width += 2 * room } else { sizes[Int(edge.source)].height += 2 * room }
        }
        return sizes
    }
}

extension RequirementDiagram {
    /// How many style declarations the requirements and elements hold, each time it is given, that their look has no place
    /// for (`font-weight`, `font-style`, `font-size`) or does not read; the colors and strokes are applied.
    public var unappliedStatementCount: Int {
        var styles = RequirementStyleResolution(model: model)
        for record in model.requirements { _ = styles.style(of: record) }
        for record in model.elements { _ = styles.style(of: record) }
        return styles.unappliedCount
    }
}

/// The look each box's declarations give it, as Pele's `resolveStyle` gives it (each property's last value wins), each
/// declaration read once, on its bytes, the first time a box holds it.
struct RequirementStyleResolution {
    private let model: RequirementModel
    /// By declaration number, once read.
    private var read: [(style: DiagramElementStyle, isUnapplied: Bool)?] = []
    private(set) var unappliedCount = 0

    init(model: RequirementModel) {
        self.model = model
    }

    mutating func style(of record: RequirementNodeRecord) -> DiagramElementStyle? {
        guard record.styleDeclarationCount > 0 else { return nil }
        if read.isEmpty { read = Array(repeating: nil, count: model.ranges.count) }
        var style = DiagramElementStyle()
        for position in record.styleDeclarationIndices {
            let number = model.numbers[position]
            let reading: (style: DiagramElementStyle, isUnapplied: Bool)
            if let known = read[Int(number)] {
                reading = known
            } else {
                let parsed = model.withDeclarationBytes(number) { bytes in
                    bytes.allSatisfy { byte in byte < 0x80 } ? DiagramElementStyle.reading(bytes: bytes)
                                                              : DiagramElementStyle.reading(String(decoding: bytes, as: UTF8.self))
                }
                reading = (parsed.style, parsed.hasUnappliedDeclaration)
                read[Int(number)] = reading
            }
            style = style.overridden(by: reading.style)
            if reading.isUnapplied { unappliedCount += 1 }
        }
        return style.isEmpty ? nil : style
    }
}
