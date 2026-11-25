/**
 * File: GraphTextMutations.swift
 * ------------------------------
 * Layer: Tests
 * Description: Changes made at random to written diagrams, the same for the same seed: pieces a graph diagram's
 *              reader treats apart inserted, deleted or put in place of others, and texts kept to ASCII, for the
 *              equivalence tests of the state, class, entity relationship and requirement readers.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

struct GraphTextMutations {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// SplitMix64.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    mutating func below(_ bound: Int) -> Int {
        bound <= 1 ? 0 : Int(next() % UInt64(bound))
    }

    /// Pieces every graph reader treats apart, with spellings Swift holds equal and bytes beyond ASCII.
    static let commonPieces = ["\n", " ", "  ", "\t", "\r\n", "\r", ";", ":", "::", ":::", "{", "}", "\"", "%%", "#", "\\n", "*", "_", "<br>", "<b>",
                               "&amp;", "#9829;", "-", "--", "<", ">", "|", "[", "]", "(", ")", "~", ",", "=", "a", "B", "x_y", "e\u{301}", "\u{E9}",
                               "\u{212A}", "K", "中", "\u{00A0}", "\u{3000}", "\u{FEFF}", "1", "end", "as", "style", "classDef", "class", "click",
                               "accTitle: t", "accDescr: d", "accDescr {", "direction LR", "direction"]

    /// `text` with one to four pieces of `pieces` inserted, put in place of a character, or a character deleted.
    mutating func mutated(_ text: String, pieces: [String]) -> String {
        var scalars = Array(text.unicodeScalars)
        for _ in 0..<(1 + below(4)) {
            let offset = below(scalars.count + 1)
            let piece = Array(pieces[below(pieces.count)].unicodeScalars)
            switch below(3) {
            case 0: scalars.insert(contentsOf: piece, at: offset)
            case 1 where offset < scalars.count: scalars.replaceSubrange(offset...offset, with: piece)
            default: if offset < scalars.count { scalars.remove(at: offset) }
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// `text` with every character beyond ASCII taken out, so that its reading takes the readers' paths on bytes.
    static func ascii(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter(\.isASCII)))
    }
}
