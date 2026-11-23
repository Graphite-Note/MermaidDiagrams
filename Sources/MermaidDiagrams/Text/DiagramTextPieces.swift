/**
 * File: DiagramTextPieces.swift
 * -----------------------------
 * Layer: Core
 * Description: A line's text cut into the pieces Pele wraps it between: words with the spaces around them, each Chinese
 *              or Japanese character with its punctuation, and the places a zero-width space or a soft hyphen allows.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// Pele's `RE_PIECE` (text/label.ts): `\s*(?:[OPEN]*[CJK][CLOSE]*|[^\s CJK HINT]+[HINT]*[CLOSE]*|[HINT]+)\s*|\s+`, all
/// its matches from the start. A line breaks only between two pieces. CJK is U+2E80 to U+9FFF, U+F900 to U+FAFF and
/// U+FF00 to U+FF60 (Hangul is left out, Korean puts spaces between words); the hints are the zero-width space and the
/// soft hyphen.
enum DiagramTextPieces {
    static func pieces(of text: String) -> [String] {
        let scalars = Array(text.unicodeScalars)
        var pieces: [String] = []
        var start = 0
        while start < scalars.count {
            let end = pieceEnd(in: scalars, from: start)
            pieces.append(UnicodeScalarText.string(scalars[start..<end]))
            start = end
        }
        return pieces
    }

    /// Where the piece that starts at `start` ends.
    private static func pieceEnd(in scalars: [Unicode.Scalar], from start: Int) -> Int {
        let core = endOfWhitespace(in: scalars, from: start)
        guard core < scalars.count, let coreEnd = coreEnd(in: scalars, from: core) else { return core }
        return endOfWhitespace(in: scalars, from: coreEnd)
    }

    /// The end of the piece's middle at `start`: a CJK character after opening punctuation and before closing
    /// punctuation, a run of other characters with its hints and closing punctuation, or a run of hints.
    private static func coreEnd(in scalars: [Unicode.Scalar], from start: Int) -> Int? {
        var openingEnd = start
        while openingEnd < scalars.count, opening.contains(scalars[openingEnd]) { openingEnd += 1 }
        // The opening run is greedy, then gives back characters until one that is CJK follows it.
        if let character = (start...min(openingEnd, scalars.count - 1)).reversed().first(where: { index in isCJK(scalars[index]) }) {
            return endOfRun(in: scalars, from: character + 1) { scalar in closing.contains(scalar) }
        }
        if isPlain(scalars[start]) {
            let wordEnd = endOfRun(in: scalars, from: start, where: isPlain)
            let hintEnd = endOfRun(in: scalars, from: wordEnd, where: isHint)
            return endOfRun(in: scalars, from: hintEnd) { scalar in closing.contains(scalar) }
        }
        if isHint(scalars[start]) { return endOfRun(in: scalars, from: start, where: isHint) }
        return nil
    }

    private static func endOfWhitespace(in scalars: [Unicode.Scalar], from start: Int) -> Int {
        endOfRun(in: scalars, from: start, where: JavaScriptStringTrimming.isWhitespace)
    }

    private static func endOfRun(in scalars: [Unicode.Scalar], from start: Int, where belongs: (Unicode.Scalar) -> Bool) -> Int {
        var end = start
        while end < scalars.count, belongs(scalars[end]) { end += 1 }
        return end
    }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFF60: true
        default: false
        }
    }

    static func isHint(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\u{200B}" || scalar == softHyphen
    }

    private static func isPlain(_ scalar: Unicode.Scalar) -> Bool {
        !JavaScriptStringTrimming.isWhitespace(scalar) && !isCJK(scalar) && !isHint(scalar)
    }

    static let softHyphen: Unicode.Scalar = "\u{AD}"

    private static let closing = Set("、。，．：；！？）］｝」』】〕〉》〙〗ー…‥・ゝゞぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ,.:;!?)]}".unicodeScalars)
    private static let opening = Set("（［｛「『【〔〈《〘〖([{".unicodeScalars)
}
