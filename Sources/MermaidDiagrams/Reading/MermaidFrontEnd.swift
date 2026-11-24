/**
 * File: MermaidFrontEnd.swift
 * ---------------------------
 * Layer: Core
 * Description: What every diagram's reading starts with: the text preprocessed as Pele does, without a copy when no
 *              pass would change a byte, its front matter's title, the comments before the type's keyword, and the
 *              keyword itself.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
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
        let isUnchanged = string.utf8.withContiguousStorageIfAvailable { bytes in isReadUnchanged(bytes) } ?? false
        guard isUnchanged else {
            let (title, cursor) = try MermaidDiagramReader.preprocessed(source)
            try refuseUnindexable(byteCount: cursor.bytes.count)
            let text = MermaidSourceText(bytes: cursor.bytes)
            let (keyword, type) = try keywordRange(in: text, from: cursor.position)
            return MermaidFrontEndResult(text: text, sourceBytes: cursor.sourceBytes, readFrontMatter: cursor.readFrontMatter,
                                         frontMatterTitle: title, keyword: keyword, typeKeyword: type)
        }
        let text = MermaidSourceText(contiguousString: string)
        let (keyword, type) = try keywordRange(in: text, from: 0)
        return MermaidFrontEndResult(text: text, sourceBytes: nil, readFrontMatter: nil, frontMatterTitle: nil, keyword: keyword, typeKeyword: type)
    }

    /// Refuses a text too long for `MermaidTextRange`'s 32-bit offsets: limits that allow more than 2 GB
    /// (`MermaidDiagramLimits.maximumSourceBytes`), or preprocessing's added quotation marks, would else make ranges whose
    /// offsets wrap.
    static func refuseUnindexable(byteCount: Int) throws(MermaidDiagramReadError) {
        guard byteCount <= MermaidTextRange.maximumOffset else { throw .sourceTooLarge(limitBytes: MermaidTextRange.maximumOffset) }
    }

    /// Whether preprocessing leaves `bytes` as they are: no byte order mark, no carriage return, no tag attribute to
    /// quote, no front matter (nor a first line of `---` that would be refused as unclosed), no directive, no colour's
    /// semicolon to drop.
    private static func isReadUnchanged(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { return false }
        // Front matter is looked for first: its text is copied anyway, and the scan is then made once, on the copy.
        if mayStartWithFrontMatter(bytes) { return false }
        let found = MermaidPreprocessing.bytesFound(in: bytes)
        if found.contains(.carriageReturn) { return false }
        if found.contains([.lessThan, .greaterThan]), MermaidPreprocessing.hasTagAttributesToQuote(in: bytes) { return false }
        if found.contains(.percent), MermaidPreprocessing.containsDirectiveStart(bytes, from: 0) { return false }
        if found.contains(.hash), MermaidPreprocessing.hasColorSemicolonsToDrop(in: bytes, from: 0) { return false }
        return true
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
