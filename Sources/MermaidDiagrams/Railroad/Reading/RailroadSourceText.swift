/**
 * File: RailroadSourceText.swift
 * ------------------------------
 * Layer: Core
 * Description: A railroad diagram's text as Pele hands it to the railroad parsers: each line break `\n`, and the comment
 *              lines Mermaid removes before parsing gone, even inside strings and descriptions; with the lines they were
 *              on, for errors.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// The text a railroad diagram is read from, as Pele's preprocessing leaves it: every `\r\n` and `\r` made `\n`, and,
/// after the keyword, every match of Mermaid's comment pattern (`^\s*%%(?!{)[^\n]+\n?`, a line of `%%` and some text,
/// with the blank lines before it) removed, so a comment line inside a string or a description in braces is not part of
/// it. `sourceLine(of:)` gives the line of the text as written for a line of the text read.
struct RailroadSourceText {
    let bytes: [UInt8]
    /// Where the diagram's keyword ends.
    let start: Int
    /// For each removed piece, the line of the text read where it was cut out and the line breaks it held.
    private var removedPieces: [(line: Int, lineBreaks: Int)] = []
    private static let commentStart = Array("%%".utf8)

    init(bytes written: [UInt8], keywordEnd: Int) {
        let (lineFed, start) = Self.withLineFeeds(written, position: keywordEnd)
        self.start = start
        guard lineFed[start...].contains(MermaidByte.percent) else {
            bytes = lineFed
            return
        }
        var kept = Array(lineFed[..<start])
        kept.reserveCapacity(lineFed.count)
        var keptLineBreaks = lineFed[..<start].reduce(0) { count, byte in byte == MermaidByte.newline ? count + 1 : count }
        var index = start
        // Every line start inside one run of whitespace reaches the same end of it: once no comment follows that end,
        // none of them starts one, and the run is not read again.
        var endOfRunWithoutComment = -1
        while index < lineFed.count {
            if lineFed[index - 1] == MermaidByte.newline, index > endOfRunWithoutComment {
                let marks = JavaScriptWhitespace.endOfRun(in: lineFed, from: index)
                if let end = Self.endOfCommentLine(lineFed, marks: marks) {
                    let lineBreaks = lineFed[index..<end].reduce(0) { count, byte in byte == MermaidByte.newline ? count + 1 : count }
                    removedPieces.append((keptLineBreaks + 1, lineBreaks))
                    index = end
                    continue
                }
                endOfRunWithoutComment = marks
            }
            if lineFed[index] == MermaidByte.newline { keptLineBreaks += 1 }
            kept.append(lineFed[index])
            index += 1
        }
        bytes = kept
    }

    /// The line of the text as written that holds `line` of the text read.
    func sourceLine(of line: Int) -> Int {
        removedPieces.reduce(line) { sourceLine, piece in piece.line <= line ? sourceLine + piece.lineBreaks : sourceLine }
    }

    /// The error with its line in the text as written.
    func inSource(_ error: MermaidDiagramReadError) -> MermaidDiagramReadError {
        guard case .invalidSyntax(let line, let problem) = error else { return error }
        return .invalidSyntax(line: sourceLine(of: line), problem: problem)
    }

    /// The end of a match of `^\s*%%(?!{)[^\n]+\n?` whose whitespace (line breaks too) ends at `marks`: `%%` there, not
    /// followed by `{`, at least one more character on its line, and the line break after it; nil when there is none.
    private static func endOfCommentLine(_ bytes: [UInt8], marks: Int) -> Int? {
        guard FirstMatchTokenPatterns.starts(bytes, at: marks, with: commentStart) else { return nil }
        let text = marks + commentStart.count
        guard text < bytes.count, bytes[text] != MermaidByte.newline, bytes[text] != MermaidByte.openingBrace else { return nil }
        guard let lineBreak = bytes[text...].firstIndex(of: MermaidByte.newline) else { return bytes.count }
        return lineBreak + 1
    }

    /// The text with each `\r\n` and `\r` made `\n`, as Pele makes them before a diagram is read (so a string written
    /// over two lines holds `\n`), and where `position` is in it.
    static func withLineFeeds(_ bytes: [UInt8], position: Int) -> (bytes: [UInt8], position: Int) {
        guard bytes.contains(MermaidByte.carriageReturn) else { return (bytes, position) }
        var lineFed: [UInt8] = []
        lineFed.reserveCapacity(bytes.count)
        var movedPosition = position
        var index = 0
        while index < bytes.count {
            guard bytes[index] == MermaidByte.carriageReturn else {
                lineFed.append(bytes[index])
                index += 1
                continue
            }
            lineFed.append(MermaidByte.newline)
            let isPair = index + 1 < bytes.count && bytes[index + 1] == MermaidByte.newline
            if isPair, index + 1 < position { movedPosition -= 1 }
            index += isPair ? 2 : 1
        }
        return (lineFed, movedPosition)
    }
}
