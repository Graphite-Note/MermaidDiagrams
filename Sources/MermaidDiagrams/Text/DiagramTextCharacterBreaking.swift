/**
 * File: DiagramTextCharacterBreaking.swift
 * ----------------------------------------
 * Layer: Core
 * Description: A wrapped block's lines that are still too wide broken between characters, as Pele's fitLabel and
 *              breakLabel break a span: each character's width added as the width of the text it joins less the text's
 *              width before, measured on the bytes, printable ASCII continued over its advances.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramTextMeasuringScratch {
    /// `wrapped`'s lines, each wider than `maximumWidth` broken between characters, the others kept as they are.
    mutating func breakLines<Measurer: DiagramTextMeasuring>(of wrapped: DiagramTextBlock, measurer: Measurer, maximumWidth: CGFloat)
        -> DiagramTextBlock {
        var measuring = DiagramStyledByteMeasuring(measurer)
        let source = wrapped.storage.bytePointer
        for index in 0..<wrapped.lineCount {
            lineSpans.removeAll()
            if wrapped.record.hasEmphasis {
                let (first, count) = wrapped.runRecords(ofLine: index)
                for runIndex in 0..<count { lineSpans.append(wrapped.storage.record(at: first, index: runIndex, as: DiagramTextRunRecord.self)) }
            } else {
                let range = wrapped.lineRange(at: index)
                if range.start != range.end {
                    lineSpans.append(DiagramTextRunRecord(start: range.start, end: range.end, width: wrapped.lineWidth(at: index), style: []))
                }
            }
            guard wrapped.lineWidth(at: index) > maximumWidth else {
                addLine(runs: lineSpans.buffer, width: wrapped.lineWidth(at: index))
                continue
            }
            breakBetweenCharacters(source: source, measuring: &measuring, maximumWidth: maximumWidth)
        }
        return finishedBlock(source: wrapped.storage, keepsRuns: wrapped.record.hasEmphasis, fontSize: measurer.fontSize, lineHeight: wrapped.lineHeight)
    }

    /// The spans of `lineSpans` broken between characters where the line passes `maximumWidth`, each piece of a span
    /// measured in its emphasis.
    private mutating func breakBetweenCharacters<Measurer>(source: UnsafePointer<UInt8>, measuring: inout DiagramStyledByteMeasuring<Measurer>,
                                                           maximumWidth: CGFloat) {
        var broken: [DiagramBrokenSpan] = []
        var width: CGFloat = 0
        for spanIndex in 0..<lineSpans.count {
            let span = lineSpans[spanIndex]
            let advances = measuring.advances(of: span.style)
            var characterStart = span.start
            for characterEnd in Self.characterEnds(of: bytes(span.start, span.end, source: source)).map({ end in Int32(end) + span.start }) {
                let characterBytes = bytes(characterStart, characterEnd, source: source)
                let isPrintable = characterBytes.allSatisfy(DiagramFontAdvances.isPrintable)
                var joinsLast = broken.last.map { last in last.style == span.style } ?? false
                var measured = joinsLast ? joinedWidth(broken[broken.count - 1], characterStart, characterEnd, isPrintable: isPrintable, advances: advances,
                                                       source: source, measuring: &measuring) : 0
                var added = joinsLast ? measured - broken[broken.count - 1].width : 0
                if !joinsLast { (added, measured) = Self.ownWidth(characterBytes, style: span.style, isPrintable: isPrintable, advances: advances, measuring: &measuring) }
                if !broken.isEmpty, width + added > maximumWidth {
                    addBrokenLine(broken, width: width)
                    broken.removeAll(keepingCapacity: true)
                    width = 0
                    joinsLast = false
                    (added, measured) = Self.ownWidth(characterBytes, style: span.style, isPrintable: isPrintable, advances: advances, measuring: &measuring)
                }
                if joinsLast {
                    join(&broken[broken.count - 1], characterStart, characterEnd, source: source)
                    broken[broken.count - 1].width += added
                    broken[broken.count - 1].measuredWidth = measured
                    broken[broken.count - 1].isPrintableASCII = broken[broken.count - 1].isPrintableASCII && isPrintable
                } else {
                    broken.append(DiagramBrokenSpan(start: characterStart, end: characterEnd, style: span.style, width: added, measuredWidth: measured,
                                                    isPrintableASCII: isPrintable))
                }
                width += added
                characterStart = characterEnd
            }
        }
        addBrokenLine(broken, width: width)
    }

    /// A character's width alone, as the text it starts: what it adds, and its text's measured width.
    private static func ownWidth<Measurer>(_ bytes: UnsafeBufferPointer<UInt8>, style: DiagramTextStyle, isPrintable: Bool, advances: DiagramFontAdvances?,
                                           measuring: inout DiagramStyledByteMeasuring<Measurer>) -> (added: CGFloat, measured: CGFloat) {
        let width = isPrintable && advances != nil ? advances!.width(continuing: 0, over: bytes) : measuring.width(of: bytes, style: style)
        return (width - 0, width)
    }

    /// The measured width of `span`'s text with the character from `start` to `end` joined to it.
    private mutating func joinedWidth<Measurer>(_ span: DiagramBrokenSpan, _ start: Int32, _ end: Int32, isPrintable: Bool, advances: DiagramFontAdvances?,
                                                source: UnsafePointer<UInt8>, measuring: inout DiagramStyledByteMeasuring<Measurer>) -> CGFloat {
        if span.isPrintableASCII, isPrintable, let advances { return advances.width(continuing: span.measuredWidth, over: bytes(start, end, source: source)) }
        if span.end == start { return measuring.width(of: bytes(span.start, end, source: source), style: span.style) }
        probe.removeAll()
        probe.append(contentsOf: bytes(span.start, span.end, source: source))
        probe.append(contentsOf: bytes(start, end, source: source))
        return measuring.width(of: probe.buffer, style: span.style)
    }

    /// `span` with the character from `start` to `end` joined: its end moved where the character follows it, else its
    /// text and the character copied one after the other into the synthetic text.
    private mutating func join(_ span: inout DiagramBrokenSpan, _ start: Int32, _ end: Int32, source: UnsafePointer<UInt8>) {
        guard span.end != start else {
            span.end = end
            return
        }
        synthetic.reserveCapacity(synthetic.count + Int(span.end - span.start) + Int(end - start))
        let joinedStart = Self.syntheticOffset + Int32(synthetic.count)
        synthetic.append(contentsOf: bytes(span.start, span.end, source: source))
        synthetic.append(contentsOf: bytes(start, end, source: source))
        span.start = joinedStart
        span.end = Self.syntheticOffset + Int32(synthetic.count)
    }

    private mutating func addBrokenLine(_ spans: [DiagramBrokenSpan], width: CGFloat) {
        lines.append(Line(firstRun: Int32(runs.count), runCount: Int32(spans.count), width: width))
        for span in spans {
            runs.append(DiagramTextRunRecord(start: span.start, end: span.end, width: span.width, style: span.style))
            if !span.style.isEmpty { hasEmphasis = true }
        }
    }

    /// Where each character of `bytes` ends: a byte of ASCII, but a carriage return and a line feed together; text
    /// beyond ASCII cut as its String cuts its characters, read once.
    static func characterEnds(of bytes: UnsafeBufferPointer<UInt8>) -> [Int] {
        guard bytes.contains(where: { byte in byte >= 0x80 }) else {
            var ends: [Int] = []
            ends.reserveCapacity(bytes.count)
            var position = 0
            while position < bytes.count {
                position += bytes[position] == 0x0D && position + 1 < bytes.count && bytes[position + 1] == 0x0A ? 2 : 1
                ends.append(position)
            }
            return ends
        }
        var ends: [Int] = []
        var offset = 0
        for character in String(decoding: bytes, as: UTF8.self) {
            offset += character.utf8.count
            ends.append(offset)
        }
        return ends
    }
}
