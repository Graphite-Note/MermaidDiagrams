/**
 * File: MermaidFrontEnd.swift
 * ---------------------------
 * Layer: Core
 * Description: What every diagram's reading starts with: the text preprocessed as Pele does, without a copy when no
 *              pass would change a byte (front matter and all), its front matter's title, the comments before the
 *              type's keyword, and the keyword itself.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

/// The text a diagram is read from, preprocessed, and where its type's keyword stands in it.
struct MermaidFrontEndResult {
    /// The text preprocessed as Pele does (`MermaidPreprocessing`), from its start: the front matter is kept, and its
    /// lines count in the lines errors name.
    let text: MermaidSourceText
    /// The text as written, line breaks made line feeds and tags' attributes single-quoted, with its front matter and
    /// directives, which a type's options are read from; nil when it is `text`.
    let sourceBytes: [UInt8]?
    /// The front matter found and read, nil when the text was read without looking for one (it has none).
    let readFrontMatter: MermaidReadFrontMatter?
    /// The front matter's `title`, or nil.
    let frontMatterTitle: String?
    /// The keyword that names the diagram's type (`flowchart`, `stateDiagram-v2`).
    let keyword: MermaidTextRange
    /// The keyword's type, told from its bytes.
    let typeKeyword: MermaidTypeKeyword

    /// The keyword as text.
    var keywordText: String { text.string(keyword) }
}

/// Reads a text up to its type's keyword, as Pele's `preprocess` and its type detection read it. One scan of the
/// String's own bytes finds what each pass looks for, and each pass's own test says whether it would change a byte;
/// only then are the bytes copied and the passes run, as `MermaidDiagramReader.preprocessed` runs them.
enum MermaidFrontEnd {
    static func read(_ source: String) throws(MermaidDiagramReadError) -> MermaidFrontEndResult {
        try refuseUnindexable(byteCount: source.utf8.count)
        var string = source
        string.makeContiguousUTF8()
        let unchanged = string.utf8.withContiguousStorageIfAvailable { bytes in unchangedReading(bytes) } ?? nil
        guard let unchanged else {
            let (title, cursor) = try MermaidDiagramReader.preprocessed(source)
            try refuseUnindexable(byteCount: cursor.bytes.count)
            let text = MermaidSourceText(bytes: cursor.bytes)
            let (keyword, type) = try keywordRange(in: text, from: cursor.position)
            return MermaidFrontEndResult(text: text, sourceBytes: cursor.sourceBytes, readFrontMatter: cursor.readFrontMatter,
                                         frontMatterTitle: title, keyword: keyword, typeKeyword: type)
        }
        let text = MermaidSourceText(contiguousString: string)
        guard let read = unchanged.frontMatter, let frontMatter = read.frontMatter else {
            let (keyword, type) = try keywordRange(in: text, from: 0)
            return MermaidFrontEndResult(text: text, sourceBytes: nil, readFrontMatter: nil, frontMatterTitle: nil, keyword: keyword, typeKeyword: type)
        }
        let title = try MermaidDiagramReader.frontMatterTitle(read, of: frontMatter)
        let (keyword, type) = try keywordRange(in: text, from: frontMatter.end)
        return MermaidFrontEndResult(text: text, sourceBytes: nil, readFrontMatter: read, frontMatterTitle: title, keyword: keyword, typeKeyword: type)
    }

    /// Refuses a text too long for `MermaidTextRange`'s 32-bit offsets: limits that allow more than 2 GB
    /// (`MermaidDiagramLimits.maximumSourceBytes`), or preprocessing's added quotation marks, would else make ranges whose
    /// offsets wrap.
    static func refuseUnindexable(byteCount: Int) throws(MermaidDiagramReadError) {
        guard byteCount <= MermaidTextRange.maximumOffset else { throw .sourceTooLarge(limitBytes: MermaidTextRange.maximumOffset) }
    }

    /// A text preprocessing leaves as it is, and its front matter when it has one.
    private struct UnchangedReading {
        /// The front matter found on the text's own bytes and read, nil when the text starts with none.
        let frontMatter: MermaidReadFrontMatter?
    }

    /// The reading of `bytes` when preprocessing leaves them as they are: no byte order mark, no carriage return, no
    /// tag attribute to quote, and after the front matter, which is found and read where it stands, no directive and
    /// no colour's semicolon to drop; nil otherwise, and for a first line of `---` that opens no front matter (refused
    /// as unclosed, or no front matter as Pele finds it), which the copying preprocessing reads.
    private static func unchangedReading(_ bytes: UnsafeBufferPointer<UInt8>) -> UnchangedReading? {
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { return nil }
        let found = MermaidPreprocessing.bytesFound(in: bytes)
        if found.contains(.carriageReturn) { return nil }
        if found.contains([.lessThan, .greaterThan]), MermaidPreprocessing.hasTagAttributesToQuote(in: bytes) { return nil }
        var start = 0
        var read: MermaidReadFrontMatter?
        if mayStartWithFrontMatter(bytes) {
            guard let frontMatter = MermaidFrontMatter.find(in: bytes) else { return nil }
            start = frontMatter.end
            read = MermaidReadFrontMatter(frontMatter: frontMatter)
        }
        if found.contains(.percent), MermaidPreprocessing.containsDirectiveStart(bytes, from: start) { return nil }
        if found.contains(.hash), MermaidPreprocessing.hasColorSemicolonsToDrop(in: bytes, from: start) { return nil }
        return UnchangedReading(frontMatter: read)
    }

    /// Whether the first line, after white space that is no line break, starts with `---`: front matter, or the fence
    /// of front matter left unclosed. `MermaidFrontMatter.find` finds none in any other text.
    private static func mayStartWithFrontMatter(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        var start = 0
        while start < bytes.count, bytes[start] != MermaidByte.newline, bytes[start] != MermaidByte.carriageReturn,
              case let length = JavaScriptWhitespace.length(in: bytes, at: start), length > 0 { start += length }
        return start + 3 <= bytes.count && bytes[start] == MermaidByte.hyphen && bytes[start + 1] == MermaidByte.hyphen
            && bytes[start + 2] == MermaidByte.hyphen
    }

    /// The type's keyword after `start`, past blank space and comments, each to the end of its line: a letter, then
    /// letters, digits and `-`. Refused as no diagram at the text's end, else as text that names no type.
    private static func keywordRange(in text: MermaidSourceText,
                                     from start: Int) throws(MermaidDiagramReadError) -> (MermaidTextRange, MermaidTypeKeyword) {
        let found: Result<(MermaidTextRange, MermaidTypeKeyword), MermaidDiagramReadError> = text.withBytes { bytes in
            var position = start
            while true {
                while position < bytes.count, MermaidByte.isWhitespace(bytes[position]) { position += 1 }
                guard position + 1 < bytes.count, bytes[position] == MermaidByte.percent, bytes[position + 1] == MermaidByte.percent else { break }
                while position < bytes.count, bytes[position] != MermaidByte.newline { position += 1 }
            }
            guard position < bytes.count, MermaidByte.isLetter(bytes[position]) else {
                if position >= bytes.count { return .failure(.noDiagram) }
                return .failure(.invalidSyntax(line: MermaidSourceText.line(at: position, in: bytes),
                                               problem: .unexpectedText(MermaidSourceText.excerpt(at: position, in: bytes))))
            }
            let keywordStart = position
            while position < bytes.count, case let byte = bytes[position], MermaidByte.isLetter(byte) || MermaidByte.isDigit(byte) || byte == MermaidByte.hyphen {
                position += 1
            }
            return .success((MermaidTextRange(start: keywordStart, end: position),
                             MermaidTypeKeyword(UnsafeBufferPointer(rebasing: bytes[keywordStart..<position]))))
        }
        return try found.get()
    }
}
