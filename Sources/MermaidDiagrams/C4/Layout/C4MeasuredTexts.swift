/**
 * File: C4MeasuredTexts.swift
 * ---------------------------
 * Layer: Core
 * Description: Measures a C4 diagram's texts from the ranges of its text into one list of lines, as C4TextLabel
 *              measures them as blocks: a field's text, `[type]` and `[technology]` in brackets, a dynamic diagram's
 *              numbered labels, the kinds' names from widths kept per face; a text of nothing but breaks keeps the
 *              empty lines Pele lays out.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// The C4 kinds' names (`«system db»`), whose widths are kept per face for the whole process.
enum C4KindNames {
    static let texts = DiagramConstantTexts(C4ShapeKind.allCases.map(\.guillemetedName))

    /// The kind's place among the texts.
    static func index(of kind: C4ShapeKind) -> Int {
        C4ShapeKind.allCases.firstIndex(of: kind) ?? 0
    }
}

/// The measurers of a C4 diagram's texts as the flat measuring reads them, made once a layout, with the measurers
/// themselves for a text that takes the full path.
struct C4TextMeasuring<Measurer: DiagramTextMeasuring> {
    let measurers: C4Measurers<Measurer>
    let name: DiagramFlatMeasurer<Measurer>
    let small: DiagramFlatMeasurer<Measurer>
    let smallest: DiagramFlatMeasurer<Measurer>
    let italicSmall: DiagramFlatMeasurer<Measurer>
    let kindNameWidths: DiagramConstantTextWidths

    init(_ measurers: C4Measurers<Measurer>) {
        self.measurers = measurers
        name = DiagramFlatMeasurer(measurers.name)
        small = DiagramFlatMeasurer(measurers.small)
        smallest = DiagramFlatMeasurer(measurers.smallest)
        italicSmall = DiagramFlatMeasurer(measurers.italicSmall)
        kindNameWidths = C4KindNames.texts.widths(for: measurers.smallest)
    }

    /// `text` of `diagram` measured as `C4TextLabel.block(_:in:measurer:maximumWidth:)` measures it, nil for a text not
    /// written or empty. A text of the diagram's own derived bytes has its lines copied into the derived bytes of `lines`,
    /// so that every line is of the diagram's source or of `lines` itself.
    func measure(_ text: C4Text, in diagram: C4Diagram, with measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                 into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText? {
        guard !text.isNoneOrEmpty else { return nil }
        guard text.isDerived else {
            return diagram.source.withUnsafeBufferPointer { source in
                measured(source, MermaidTextRange(start: Int(text.start), end: Int(text.end)), with: measurer, maximumWidth: maximumWidth, into: &lines)
            }
        }
        return diagram.derived.withUnsafeBufferPointer { derived in
            let start = Int(text.start - C4Text.derivedOffset)
            let measured = measured(derived, MermaidTextRange(start: start, end: start + text.count), with: measurer, maximumWidth: maximumWidth,
                                    into: &lines)
            lines.deriveLines(of: measured, source: derived)
            return measured
        }
    }

    /// `[text]`, as a type or a technology is drawn, measured as `C4TextLabel.bracketedBlock` measures it.
    func measureBracketed(_ text: C4Text, in diagram: C4Diagram, with measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                          into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText? {
        guard !text.isNoneOrEmpty else { return nil }
        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: text.count + 2) { room in
            room[0] = UInt8(ascii: "[")
            var written = Self.copy(text, of: diagram, into: room, at: 1)
            room[written] = UInt8(ascii: "]")
            written += 1
            return measuredAndDerived(UnsafeBufferPointer(rebasing: room[0..<written]), with: measurer, maximumWidth: maximumWidth, into: &lines)
        }
    }

    /// A relation's label as a dynamic diagram numbers it, `number: label`, or the label alone for number 0, measured as
    /// `C4TextLabel.numberedBlock` measures it.
    func measureNumbered(_ text: C4Text, number: Int, in diagram: C4Diagram, maximumWidth: CGFloat, into lines: inout DiagramMeasuredLines)
        -> DiagramMeasuredText? {
        guard number > 0 else { return measure(text, in: diagram, with: small, maximumWidth: maximumWidth, into: &lines) }
        var digitCount = 1
        var rest = number / 10
        while rest > 0 {
            digitCount += 1
            rest /= 10
        }
        return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: digitCount + 2 + max(text.count, 0)) { room in
            var value = number
            for place in stride(from: digitCount - 1, through: 0, by: -1) {
                room[place] = UInt8(ascii: "0") + UInt8(value % 10)
                value /= 10
            }
            room[digitCount] = UInt8(ascii: ":")
            room[digitCount + 1] = UInt8(ascii: " ")
            let written = Self.copy(text, of: diagram, into: room, at: digitCount + 2)
            return measuredAndDerived(UnsafeBufferPointer(rebasing: room[0..<written]), with: small, maximumWidth: maximumWidth, into: &lines)
        }
    }

    /// A kind's name in `maximumWidth`, as `C4TextLabel.block(kind.guillemetedName, measurer: smallest, ...)` measures it.
    func measureKindName(_ kind: C4ShapeKind, maximumWidth: CGFloat, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        #if DEBUG
        if DiagramLabelDecodingObservation.observer != nil { _ = DiagramLabelDecoder.label(from: kind.guillemetedName, form: .plain) }
        #endif
        return kindNameWidths.measure(C4KindNames.index(of: kind), measurer: smallest, maximumWidth: maximumWidth, into: &lines)
    }

    /// The text of `bytes[range]` measured, or, for a text that measures to no line (white space or breaks alone), the
    /// lines Pele lays out for it: one empty line for each part between breaks, as `C4TextLabel` makes them.
    private func measured(_ bytes: UnsafeBufferPointer<UInt8>, _ range: MermaidTextRange, with measurer: DiagramFlatMeasurer<Measurer>,
                          maximumWidth: CGFloat, into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        #if DEBUG
        // The tests that check every text the corpora measure watch the decoder, which the fast path does not call.
        if DiagramLabelDecodingObservation.observer != nil {
            _ = DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: bytes[Int(range.start)..<Int(range.end)]), form: .plain)
        }
        #endif
        let measured = DiagramFlatTextMeasuring.measure(bytes, range, form: .plain, measurer: measurer, maximumWidth: maximumWidth, into: &lines)
        guard measured.lineCount == 0 else { return measured }
        let label = DiagramLabelDecoder.label(fromUTF8: UnsafeBufferPointer(rebasing: bytes[Int(range.start)..<Int(range.end)]), form: .plain)
        return DiagramFlatTextMeasuring.copied(C4TextLabel.emptyLines(of: label, measurer: measurer.measurer), into: &lines)
    }

    /// Bytes made for the measuring, measured, their lines copied into the derived bytes of `lines`.
    private func measuredAndDerived(_ bytes: UnsafeBufferPointer<UInt8>, with measurer: DiagramFlatMeasurer<Measurer>, maximumWidth: CGFloat,
                                    into lines: inout DiagramMeasuredLines) -> DiagramMeasuredText {
        let measured = measured(bytes, MermaidTextRange(start: 0, end: bytes.count), with: measurer, maximumWidth: maximumWidth, into: &lines)
        lines.deriveLines(of: measured, source: bytes)
        return measured
    }

    /// Copies the bytes of `text` into `room` from `offset`, and returns the offset past them.
    private static func copy(_ text: C4Text, of diagram: C4Diagram, into room: UnsafeMutableBufferPointer<UInt8>, at offset: Int) -> Int {
        diagram.withBytes(of: text) { bytes in
            precondition(offset + bytes.count <= room.count, "text longer than its room")
            var written = offset
            for byte in bytes {
                room[written] = byte
                written += 1
            }
            return written
        }
    }
}

extension DiagramMeasuredText? {
    /// The text's width and height, zero for none.
    var measuredWidth: CGFloat { self?.width ?? 0 }
    var measuredHeight: CGFloat { self?.height ?? 0 }
}
