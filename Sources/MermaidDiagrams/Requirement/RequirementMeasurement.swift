/**
 * File: RequirementMeasurement.swift
 * ----------------------------------
 * Layer: Core
 * Description: A requirement diagram's boxes and relations measured as Pele's requirement renderer measures them: the
 *              stereotype, the bold name and the rows of fields of each box, and each relation's text, every text
 *              measured on the flat path into the measurement's one list of lines and kept as a measured text.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
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
/// `firstRow`), the widest field name, the height of its head and its size, the room its loops take kept apart.
struct RequirementMeasuredBox {
    let isRequirement: Bool
    let stereotype: DiagramMeasuredText
    let name: DiagramMeasuredText
    let firstRow: Int
    let rowCount: Int
    let keyWidth: CGFloat
    let headHeight: CGFloat
    let size: CGSize
    let style: DiagramElementStyle?

    var rowIndices: Range<Int> { firstRow..<(firstRow + rowCount) }
}

/// A row of a box: a field's name and its value, and the taller one's height.
struct RequirementMeasuredRow {
    let key: DiagramMeasuredText
    let value: DiagramMeasuredText
    let height: CGFloat
}

/// A relation that joins two boxes drawn: the relation it draws, its ends by box, and its text, `«kind»`.
struct RequirementMeasuredEdge {
    let relationIndex: Int
    let kind: RequirementRelationKind
    let source: Int
    let target: Int
    let text: DiagramMeasuredText

    var isSelfLoop: Bool { source == target }
    var isContainment: Bool { kind == .contains }
}

/// A requirement diagram measured, its boxes the requirements then the elements, as Mermaid orders them, and its edges the
/// relations whose two names are declared, in the order written: what the layout needs before it places anything. Every
/// text is a measured text of `lines`, measured as `DiagramTextBlock` measures the same label (`DiagramFlatTextMeasuring`).
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
    private(set) var boxes: [RequirementMeasuredBox] = []
    private(set) var rows: [RequirementMeasuredRow] = []
    private(set) var edges: [RequirementMeasuredEdge] = []
    /// For each box, the indexes of its edges to itself, in their written order.
    private(set) var selfLoopEdgeIndices: [[Int]] = []
    /// `RequirementDiagram.unappliedStatementCount`, counted as the boxes' styles are resolved.
    private(set) var unappliedStatementCount = 0

    init<Measurer: DiagramTextMeasuring>(diagram: RequirementDiagram, measurers: RequirementTextMeasurers<Measurer>) {
        var styles = RequirementStyleResolution()
        var texts = RequirementConstantTexts(measurers: measurers)
        let names = DiagramFlatMeasurer(measurers.names)
        let body = texts.body
        boxes.reserveCapacity(diagram.requirements.count + diagram.elements.count)
        rows.reserveCapacity(4 * diagram.requirements.count + 2 * diagram.elements.count)
        reserveLines(for: diagram)
        var boxIndices: [String: Int] = [:]
        boxIndices.reserveCapacity(diagram.requirements.count + diagram.elements.count)
        for requirement in diagram.requirements {
            if boxIndices[requirement.name] == nil { boxIndices[requirement.name] = boxes.count }
            var box = startBox(name: requirement.name, stereotype: texts.stereotype(of: requirement.kind, into: &lines), names: names)
            appendRow(.identifier, requirement.identifier, to: &box, texts: &texts, body: body)
            appendRow(.text, requirement.text, to: &box, texts: &texts, body: body)
            appendRow(.risk, requirement.risk?.rawValue ?? "", to: &box, texts: &texts, body: body)
            appendRow(.verification, requirement.verificationMethod?.rawValue ?? "", to: &box, texts: &texts, body: body)
            finishBox(box, isRequirement: true, style: styles.style(of: requirement.styleDeclarations))
        }
        // A requirement and an element may share a name; relations then go to the requirement.
        for element in diagram.elements {
            if boxIndices[element.name] == nil { boxIndices[element.name] = boxes.count }
            var box = startBox(name: element.name, stereotype: texts.elementStereotype(into: &lines), names: names)
            appendRow(.type, element.type, to: &box, texts: &texts, body: body)
            appendRow(.documentReference, element.documentReference, to: &box, texts: &texts, body: body)
            finishBox(box, isRequirement: false, style: styles.style(of: element.styleDeclarations))
        }
        unappliedStatementCount = styles.unappliedCount
        edges.reserveCapacity(diagram.relations.count)
        selfLoopEdgeIndices = [[Int]](repeating: [], count: boxes.count)
        for (relationIndex, relation) in diagram.relations.enumerated() {
            guard let source = boxIndices[relation.source], let target = boxIndices[relation.target] else { continue }
            if source == target { selfLoopEdgeIndices[source].append(edges.count) }
            edges.append(RequirementMeasuredEdge(relationIndex: relationIndex, kind: relation.kind, source: source, target: target,
                                                 text: texts.relationText(of: relation.kind, into: &lines)))
        }
    }

    /// Room for about every line and byte the diagram's texts take: a line or two for each text, and the bytes of its
    /// names and fields, which are copied into the derived bytes, with the constant texts'.
    private mutating func reserveLines(for diagram: RequirementDiagram) {
        var byteCount = 256
        for requirement in diagram.requirements { byteCount += requirement.name.utf8.count + requirement.identifier.utf8.count + requirement.text.utf8.count }
        for element in diagram.elements { byteCount += element.name.utf8.count + element.type.utf8.count + element.documentReference.utf8.count }
        lines.reserveCapacity(lines: 16 + 8 * diagram.requirements.count + 5 * diagram.elements.count, derivedBytes: byteCount + 32 * diagram.requirements.count)
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

    private mutating func startBox<Measurer>(name: String, stereotype: DiagramMeasuredText, names: DiagramFlatMeasurer<Measurer>) -> BoxInProgress {
        let nameText = DiagramFlatTextMeasuring.measure(markdownWritten: name, measurer: names, maximumWidth: Self.nameWrappingWidth, into: &lines)
        return BoxInProgress(stereotype: stereotype, name: nameText, firstRow: rows.count)
    }

    /// The row of a field, its value Markdown; a field of empty text is left out.
    private mutating func appendRow<Measurer>(_ key: RequirementFieldKey, _ value: String, to box: inout BoxInProgress,
                                              texts: inout RequirementConstantTexts<Measurer>, body: DiagramFlatMeasurer<Measurer>) {
        guard !value.isEmpty else { return }
        let keyText = texts.key(key, into: &lines)
        let valueText = DiagramFlatTextMeasuring.measure(markdownWritten: value, measurer: body, maximumWidth: Self.valueWrappingWidth, into: &lines)
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
        boxes.append(RequirementMeasuredBox(isRequirement: isRequirement, stereotype: box.stereotype, name: box.name, firstRow: box.firstRow,
                                            rowCount: rowCount, keyWidth: box.keyWidth, headHeight: headHeight,
                                            size: CGSize(width: width, height: headHeight + bodyHeight), style: style))
    }

    /// Each box's size in its rank: its own, grown on both sides across the flow by each of its loops, as Pele grows the
    /// node it lays out (`RequirementSelfLoops.room`).
    func layoutSizes(flowIsVertical: Bool) -> [CGSize] {
        boxes.indices.map { box in
            var size = boxes[box].size
            for edgeIndex in selfLoopEdgeIndices[box] {
                let room = RequirementSelfLoops.room(textSize: edges[edgeIndex].text.size, flowIsVertical: flowIsVertical)
                if flowIsVertical { size.width += 2 * room } else { size.height += 2 * room }
            }
            return size
        }
    }
}

extension RequirementDiagram {
    /// How many style declarations the requirements and elements hold, each time it is given, that their look has no place
    /// for (`font-weight`, `font-style`, `font-size`) or does not read; the colors and strokes are applied.
    public var unappliedStatementCount: Int {
        var styles = RequirementStyleResolution()
        for requirement in requirements { _ = styles.style(of: requirement.styleDeclarations) }
        for element in elements { _ = styles.style(of: element.styleDeclarations) }
        return styles.unappliedCount
    }
}

/// The look each box's declarations give it, as Pele's `resolveStyle` gives it (each property's last value wins), each
/// distinct declaration read once.
struct RequirementStyleResolution {
    private var read: [String: (style: DiagramElementStyle, isUnapplied: Bool)] = [:]
    private(set) var unappliedCount = 0

    mutating func style(of declarations: [String]) -> DiagramElementStyle? {
        guard !declarations.isEmpty else { return nil }
        var style = DiagramElementStyle()
        for declaration in declarations {
            // A declaration read before is looked up once; one read for the first time is kept.
            let reading: (style: DiagramElementStyle, isUnapplied: Bool)
            if let known = read[declaration] {
                reading = known
            } else {
                let parsed = DiagramElementStyle.reading(declaration)
                reading = (parsed.style, parsed.hasUnappliedDeclaration)
                read[declaration] = reading
            }
            style = style.overridden(by: reading.style)
            if reading.isUnapplied { unappliedCount += 1 }
        }
        return style.isEmpty ? nil : style
    }
}
