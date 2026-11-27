/**
 * File: EntityRelationshipCellMeasuring.swift
 * -------------------------------------------
 * Layer: Core
 * Description: The texts of an entity relationship diagram measured from their ranges of its text into the layout's
 *              list of lines: entities' names and relationships' labels as their labels, attributes' types and names as
 *              the one line each is, comments as the lines of their Markdown; any text the flat path does not take
 *              (pairs of `~`, a line break, a byte past printable ASCII, emphasis) made as 0.7.0 made it and its block's
 *              lines copied.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics

/// Measures an entity relationship diagram's texts as `DiagramTextBlock` measured the labels 0.7.0 made of them, to the
/// bit: from the model's text where its bytes are what is drawn, through the label otherwise.
struct EntityRelationshipCellMeasuring<Measurer: DiagramTextMeasuring> {
    /// The model's text, borrowed, and the model, its records read where they stand.
    let bytes: UnsafeBufferPointer<UInt8>
    let model: UnsafePointer<EntityRelationshipModel>

    /// A label of the model (an entity's name or alias, a relationship's label) wrapped at `maximumWidth`.
    func label(_ text: EntityRelationshipText, measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
               into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        switch text.kind {
        case .plain: DiagramFlatTextMeasuring.measure(bytes, text.range, form: .plain, measurer: measurer, maximumWidth: maximumWidth, into: &lines)
        case .markdown: DiagramFlatTextMeasuring.measure(markdown: bytes, text.range, measurer: measurer, maximumWidth: maximumWidth, into: &lines)
        case .decoded: DiagramFlatTextMeasuring.measure(model.pointee.labels[text.decodedIndex], measurer: measurer, maximumWidth: maximumWidth, into: &lines)
        }
    }

    /// An attribute's type or name cell: the label of its lines (`DiagramLabel(lines:)`, one line unless it holds a line
    /// break), never wrapped. A written word of printable ASCII without `~` is that one line, its width its bytes' advances,
    /// as a block measures a line of one label line; any other is made into its text and measured as 0.7.0 measured it.
    func typeOrName(_ range: MermaidTextRange, of attribute: EntityRelationshipAttributeRecord, isType: Bool, measurer: DiagramFlatMeasurer<Measurer>,
                    into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        precondition(range.start >= 0 && range.start <= range.end && range.upperBound <= bytes.count, "attribute text outside the diagram's text")
        let isWrittenAsIs = !attribute.isWritten || !(isType && attribute.appendsQuestionMark)
        if isWrittenAsIs, let advances = measurer.advances, let base = bytes.baseAddress, !range.isEmpty, isPrintableWithoutTilde(range, isWritten: attribute.isWritten) {
            let (width, kinds) = DiagramFlatLineScanning.measured(base, from: range.lowerBound, to: range.upperBound, advances: advances)
            if !kinds.contains(.unprintable) {
                let firstLine = lines.count
                lines.appendLine(start: range.lowerBound, end: range.upperBound, width: width)
                return DiagramMeasuredText(firstLine: Int32(firstLine), lineCount: 1, width: width, height: measurer.singleLineHeight,
                                           lineHeight: measurer.singleLineHeight, fontSize: measurer.fontSize)
            }
        }
        let text: String
        if attribute.isWritten {
            text = isType ? model.pointee.writtenType(of: attribute) : EntityRelationshipGenericType.angleBracketed(model.pointee.string(range))
        } else {
            text = model.pointee.string(range)
        }
        return DiagramFlatTextMeasuring.measure(EntityRelationshipBoxMeasurement.lines(of: text), measurer: measurer, maximumWidth: .greatestFiniteMagnitude,
                                                into: &lines)
    }

    /// Whether `bytes[range]` are printable ASCII, and, for a written word, without `~`, which its text reads as angle
    /// brackets in pairs.
    private func isPrintableWithoutTilde(_ range: MermaidTextRange, isWritten: Bool) -> Bool {
        for index in range.lowerBound..<range.upperBound {
            let byte = bytes[index]
            guard byte > 0x20, byte < 0x7F, !(isWritten && byte == UInt8(ascii: "~")) else { return false }
        }
        return true
    }

    /// An attribute's comment, wrapped at `maximumWidth`: the lines of its Markdown as a label of lines without emphasis
    /// (`EntityRelationshipAttributeSyntax.commentLabel`). A written comment without `~` and without markup is its plain
    /// lines, measured on the flat path's fast path; any other is made into its label and measured as 0.7.0 measured it.
    func comment(of attribute: EntityRelationshipAttributeRecord, measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                 into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        guard attribute.comment.kind != .decoded else {
            return DiagramFlatTextMeasuring.measure(model.pointee.labels[attribute.comment.decodedIndex], measurer: measurer, maximumWidth: maximumWidth, into: &lines)
        }
        let range = attribute.comment.range
        precondition(range.start >= 0 && range.start <= range.end && range.upperBound <= bytes.count, "comment outside the diagram's text")
        let text = UnsafeBufferPointer(rebasing: bytes[range.lowerBound..<range.upperBound])
        if !text.contains(UInt8(ascii: "~")), DiagramLabelLineBreaks.isUnmarked(text, isLiteral: false),
           let measured = DiagramFlatTextMeasuring.measuredOnFastPath(bytes, range, form: .plain, measurer: measurer, maximumWidth: maximumWidth, into: &lines) {
            return measured
        }
        let label = EntityRelationshipAttributeSyntax.commentLabel(model.pointee.string(range))
        return DiagramFlatTextMeasuring.measure(label, measurer: measurer, maximumWidth: maximumWidth, into: &lines)
    }
}
