/**
 * File: FlatMermaidReader.swift
 * -----------------------------
 * Layer: Core (design prototype, not for merging as is)
 * Description: The shared front end on the String's own UTF-8 bytes, with no copy when preprocessing would change
 *              nothing (one scan finds what each pass looks for), then the flowchart read flat; any other type, and
 *              any text the prototype does not read, goes through the present reader.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum FlatMermaidReadingPrototype {
    /// What a reading gave: a flat flowchart, or the present reader's diagram for what the prototype does not read.
    enum Outcome {
        case flowchart(FlatFlowchartDocument)
        case presentReader(MermaidDiagram)
    }

    /// How many readings bailed out to the present reader since the last `resetCounts()`, for the benchmark.
    nonisolated(unsafe) static var bailOutCount = 0
    nonisolated(unsafe) static var otherTypeCount = 0

    static func read(_ source: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> Outcome {
        guard source.utf8.count <= limits.maximumSourceBytes else { throw .sourceTooLarge(limitBytes: limits.maximumSourceBytes) }
        var text = source
        var needsPreprocessing = false
        let read = text.withUTF8 { buffer in readFast(buffer, limits: limits, needsPreprocessing: &needsPreprocessing) }
        if var document = read {
            document.text = text
            return .flowchart(document)
        }
        if needsPreprocessing { return try readPreprocessed(source, limits: limits) }
        return .presentReader(try MermaidDiagramReader.read(source, limits: limits))
    }

    /// The flowchart of a text that needs no preprocessing, or nil (another type, preprocessing needed, a bail-out).
    private static func readFast(_ buffer: UnsafeBufferPointer<UInt8>, limits: MermaidDiagramLimits,
                                 needsPreprocessing: inout Bool) -> FlatFlowchartDocument? {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return nil }
        needsPreprocessing = true
        let count = buffer.count
        if count >= 3, base[0] == 0xEF, base[1] == 0xBB, base[2] == 0xBF { return nil }
        var lineCount = 1
        let found = bytesFound(buffer, lineCount: &lineCount)
        if found.contains(.zero) || found.contains(.carriageReturn) { return nil }
        if found.contains(.lessThan), found.contains(.greaterThan), contains("=\"", in: buffer) { return nil }
        if found.contains(.percent), contains("%%{", in: buffer) { return nil }
        if found.contains(.hash), wouldDropColorSemicolon(buffer, after: "style") || wouldDropColorSemicolon(buffer, after: "classDef") { return nil }
        // Front matter, or a first line that is `---` alone.
        var start = 0
        while start < count, base[start] == MermaidByte.space || base[start] == MermaidByte.tab { start += 1 }
        if start + 3 <= count, base[start] == MermaidByte.hyphen, base[start + 1] == MermaidByte.hyphen, base[start + 2] == MermaidByte.hyphen { return nil }
        if start < count, base[start] >= 0x80 { return nil }
        needsPreprocessing = false
        return readBody(buffer, from: 0, limits: limits, title: nil, foundAt: found.contains(.atSign), lineCount: lineCount)
    }

    /// The present front end (preprocessing, front matter) copies the text, then the flowchart is read flat from it.
    private static func readPreprocessed(_ source: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> Outcome {
        let (title, cursor) = try MermaidDiagramReader.preprocessed(source)
        var text = String(decoding: cursor.bytes, as: UTF8.self)
        let start = cursor.position
        let read = text.withUTF8 { buffer in
            readBody(buffer, from: start, limits: limits, title: title, foundAt: buffer.contains(MermaidByte.atSign),
                     lineCount: buffer.reduce(1) { count, byte in byte == MermaidByte.newline ? count + 1 : count })
        }
        if var document = read {
            document.text = text
            return .flowchart(document)
        }
        return .presentReader(try MermaidDiagramReader.read(source, limits: limits))
    }

    private static func readBody(_ buffer: UnsafeBufferPointer<UInt8>, from start: Int, limits: MermaidDiagramLimits, title: String?,
                                 foundAt: Bool, lineCount: Int) -> FlatFlowchartDocument? {
        guard let base = buffer.baseAddress else { return nil }
        var position = start
        while true {
            while position < buffer.count, MermaidByte.isWhitespace(base[position]) { position += 1 }
            guard position + 1 < buffer.count, base[position] == MermaidByte.percent, base[position + 1] == MermaidByte.percent else { break }
            while position < buffer.count, base[position] != MermaidByte.newline { position += 1 }
        }
        let keywordStart = position
        guard position < buffer.count, MermaidByte.isLetter(base[position]) else { return nil }
        while position < buffer.count, MermaidByte.isLetter(base[position]) || MermaidByte.isDigit(base[position]) || base[position] == MermaidByte.hyphen {
            position += 1
        }
        let keyword = UnsafeBufferPointer(rebasing: buffer[keywordStart..<position])
        guard keyword.elementsEqual("flowchart".utf8) || keyword.elementsEqual("graph".utf8) || keyword.elementsEqual("flowchart-elk".utf8) else {
            otherTypeCount += 1
            return nil
        }
        let scratch = FlatReadingScratch.current
        var lists = FlatReadingLists(slots: [])
        swap(&lists, &scratch.lists)
        defer { swap(&lists, &scratch.lists) }
        lists.reset()
        if mayContainDirection(buffer) { findDirectionStatements(buffer, into: &lists.directionStatementStarts) }
        if foundAt {
            for index in 0..<buffer.count where base[index] == MermaidByte.atSign {
                let next = index + 1 < buffer.count ? base[index + 1] : 0
                if next != MermaidByte.openingBrace, next != MermaidByte.quotationMark { lists.linkIdentifierEnds.append(index) }
            }
        }
        let directionStarts = lists.directionStatementStarts
        let linkEnds = lists.linkIdentifierEnds
        let document = directionStarts.withUnsafeBufferPointer { directionStarts in
            linkEnds.withUnsafeBufferPointer { linkEnds in
                readFlowchart(FlatBytes(base: base, count: buffer.count, directionStatementStarts: directionStarts, linkIdentifierEnds: linkEnds),
                              from: position, limits: limits, lists: &lists, lineCount: lineCount)
            }
        }
        guard var document else {
            bailOutCount += 1
            return nil
        }
        if let title { document.rare.title = title }
        return document
    }

    private static func readFlowchart(_ bytes: FlatBytes, from position: Int, limits: MermaidDiagramLimits, lists: inout FlatReadingLists,
                                      lineCount: Int) -> FlatFlowchartDocument? {
        var document = FlatFlowchartDocument(text: "")
        let lineCount = min(lineCount, 1_024)
        document.nodes.reserveCapacity(lineCount * 2)
        var reader = FlatFlowchartReader(bytes: bytes, position: position, limits: limits, slots: [], names: [], sideBytes: [], groupBuffer: [],
                                         openSubgraphs: [], openMembers: [], endedSubgraphs: [], document: document)
        reader.lineCount = lineCount
        swap(&reader.slots, &lists.slots)
        swap(&reader.names, &lists.names)
        swap(&reader.sideBytes, &lists.sideBytes)
        swap(&reader.groupBuffer, &lists.groupIndices)
        swap(&reader.openSubgraphs, &lists.openSubgraphs)
        swap(&reader.openMembers, &lists.openMembers)
        swap(&reader.endedSubgraphs, &lists.endedSubgraphs)
        swap(&reader.endedMembers, &lists.endedMembers)
        defer {
            swap(&reader.endedMembers, &lists.endedMembers)
            swap(&reader.slots, &lists.slots)
            swap(&reader.names, &lists.names)
            swap(&reader.sideBytes, &lists.sideBytes)
            swap(&reader.groupBuffer, &lists.groupIndices)
            swap(&reader.openSubgraphs, &lists.openSubgraphs)
            swap(&reader.openMembers, &lists.openMembers)
            swap(&reader.endedSubgraphs, &lists.endedSubgraphs)
        }
        do {
            try reader.readDirection()
            try reader.readStatements()
        } catch {
            return nil
        }
        reader.nestSubgraphs()
        reader.applyStyles()
        swap(&document, &reader.document)
        return document
    }

    private static func findDirectionStatements(_ buffer: UnsafeBufferPointer<UInt8>, into starts: inout [Int]) {
        let bytes = FlatBytes(base: buffer.baseAddress!, count: buffer.count, directionStatementStarts: UnsafeBufferPointer(start: nil, count: 0),
                              linkIdentifierEnds: UnsafeBufferPointer(start: nil, count: 0))
        for position in 0..<buffer.count where buffer[position] == UInt8(ascii: "d") && bytes.hasText("direction", at: position) {
            let afterSpaces = bytes.endOfSpaces(from: position + 9)
            guard afterSpaces > position + 9, afterSpaces + 2 <= buffer.count else { continue }
            let pair = (buffer[afterSpaces], buffer[afterSpaces + 1])
            switch pair {
            case (0x54, 0x42), (0x42, 0x54), (0x52, 0x4C), (0x4C, 0x52), (0x54, 0x44): starts.append(position)
            default: break
            }
        }
    }

    // MARK: One scan

    struct FoundBytes: OptionSet {
        let rawValue: UInt8
        static let carriageReturn = FoundBytes(rawValue: 1)
        static let lessThan = FoundBytes(rawValue: 2)
        static let greaterThan = FoundBytes(rawValue: 4)
        static let percent = FoundBytes(rawValue: 8)
        static let hash = FoundBytes(rawValue: 16)
        static let zero = FoundBytes(rawValue: 32)
        static let atSign = FoundBytes(rawValue: 64)
    }

    /// Which of a carriage return, `<`, `>`, `%`, `#`, a 0 and `@` the bytes hold, sixteen bytes at a time.
    static func bytesFound(_ buffer: UnsafeBufferPointer<UInt8>, lineCount: inout Int) -> FoundBytes {
        var lineBreaks = SIMD16<UInt8>(repeating: 0)
        var masks = (SIMDMask<SIMD16<Int8>>(repeating: false), SIMDMask<SIMD16<Int8>>(repeating: false), SIMDMask<SIMD16<Int8>>(repeating: false),
                     SIMDMask<SIMD16<Int8>>(repeating: false), SIMDMask<SIMD16<Int8>>(repeating: false), SIMDMask<SIMD16<Int8>>(repeating: false),
                     SIMDMask<SIMD16<Int8>>(repeating: false))
        var index = 0
        let raw = UnsafeRawPointer(buffer.baseAddress!)
        while index + 16 <= buffer.count {
            let chunk = raw.loadUnaligned(fromByteOffset: index, as: SIMD16<UInt8>.self)
            masks.0 .|= chunk .== SIMD16(repeating: MermaidByte.carriageReturn)
            masks.1 .|= chunk .== SIMD16(repeating: MermaidByte.lessThan)
            masks.2 .|= chunk .== SIMD16(repeating: MermaidByte.greaterThan)
            masks.3 .|= chunk .== SIMD16(repeating: MermaidByte.percent)
            masks.4 .|= chunk .== SIMD16(repeating: UInt8(ascii: "#"))
            masks.5 .|= chunk .== SIMD16(repeating: 0)
            masks.6 .|= chunk .== SIMD16(repeating: MermaidByte.atSign)
            lineBreaks &+= SIMD16<UInt8>(repeating: 0).replacing(with: 1, where: chunk .== SIMD16(repeating: MermaidByte.newline))
            index += 16
            if index & 0x7F0 == 0 {
                lineCount += lineBreaks.indices.reduce(0) { total, lane in total + Int(lineBreaks[lane]) }
                lineBreaks = SIMD16(repeating: 0)
            }
        }
        lineCount += lineBreaks.indices.reduce(0) { total, lane in total + Int(lineBreaks[lane]) }
        var found: FoundBytes = []
        if any(masks.0) { found.insert(.carriageReturn) }
        if any(masks.1) { found.insert(.lessThan) }
        if any(masks.2) { found.insert(.greaterThan) }
        if any(masks.3) { found.insert(.percent) }
        if any(masks.4) { found.insert(.hash) }
        if any(masks.5) { found.insert(.zero) }
        if any(masks.6) { found.insert(.atSign) }
        while index < buffer.count {
            switch buffer[index] {
            case MermaidByte.carriageReturn: found.insert(.carriageReturn)
            case MermaidByte.lessThan: found.insert(.lessThan)
            case MermaidByte.greaterThan: found.insert(.greaterThan)
            case MermaidByte.percent: found.insert(.percent)
            case UInt8(ascii: "#"): found.insert(.hash)
            case 0: found.insert(.zero)
            case MermaidByte.atSign: found.insert(.atSign)
            case MermaidByte.newline: lineCount += 1
            default: break
            }
            index += 1
        }
        return found
    }

    /// Whether MermaidPreprocessing.droppingColorSemicolons would drop a semicolon after `keyword`: a line where the keyword
    /// is followed by a colon, a `#` right after it and later a semicolon. Most styles end without one, and the text is
    /// then read as it is, uncopied.
    static func wouldDropColorSemicolon(_ buffer: UnsafeBufferPointer<UInt8>, after keyword: StaticString) -> Bool {
        let bytes = FlatBytes(base: buffer.baseAddress!, count: buffer.count, directionStatementStarts: UnsafeBufferPointer(start: nil, count: 0),
                              linkIdentifierEnds: UnsafeBufferPointer(start: nil, count: 0))
        var searchFrom = 0
        while searchFrom < buffer.count,
              let found = memmem(buffer.baseAddress! + searchFrom, buffer.count - searchFrom, keyword.utf8Start, keyword.utf8CodeUnitCount) {
            let keywordStart = buffer.baseAddress!.distance(to: found.assumingMemoryBound(to: UInt8.self))
            var lineEnd = keywordStart
            while lineEnd < buffer.count, !bytes.isLineTerminator(at: lineEnd) { lineEnd += 1 }
            var isAfterColon = false
            var hashIndex: Int?
            var index = keywordStart + keyword.utf8CodeUnitCount
            while index < lineEnd {
                let byte = buffer[index]
                if byte == MermaidByte.colon {
                    isAfterColon = true
                } else if byte == UInt8(ascii: "#") {
                    if isAfterColon {
                        hashIndex = index
                        break
                    }
                } else if bytes.whitespaceLength(at: index) > 0 {
                    isAfterColon = false
                }
                index += 1
            }
            if let hashIndex, (hashIndex + 1..<lineEnd).contains(where: { position in buffer[position] == MermaidByte.semicolon }) { return true }
            searchFrom = lineEnd + 1
        }
        return false
    }

    /// Whether `direction` may stand in the text: a `d` with an `n` eight bytes after it, sixteen places at a time.
    static func mayContainDirection(_ buffer: UnsafeBufferPointer<UInt8>) -> Bool {
        guard buffer.count >= 9 else { return false }
        let raw = UnsafeRawPointer(buffer.baseAddress!)
        var index = 0
        while index + 24 <= buffer.count {
            let starts = raw.loadUnaligned(fromByteOffset: index, as: SIMD16<UInt8>.self)
            let seconds = raw.loadUnaligned(fromByteOffset: index + 1, as: SIMD16<UInt8>.self)
            let ends = raw.loadUnaligned(fromByteOffset: index + 8, as: SIMD16<UInt8>.self)
            if any((starts .== SIMD16(repeating: UInt8(ascii: "d"))) .& (seconds .== SIMD16(repeating: UInt8(ascii: "i")))
                .& (ends .== SIMD16(repeating: UInt8(ascii: "n")))) { return true }
            index += 16
        }
        while index + 9 <= buffer.count {
            if buffer[index] == UInt8(ascii: "d"), buffer[index + 1] == UInt8(ascii: "i"), buffer[index + 8] == UInt8(ascii: "n") { return true }
            index += 1
        }
        return false
    }

    private static func contains(_ literal: StaticString, in buffer: UnsafeBufferPointer<UInt8>) -> Bool {
        memmem(buffer.baseAddress, buffer.count, literal.utf8Start, literal.utf8CodeUnitCount) != nil
    }
}
