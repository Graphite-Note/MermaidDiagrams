/**
 * File: QuadrantChartPointSyntax.swift
 * ------------------------------------
 * Layer: Core
 * Description: A quadrant chart point's `: [x, y]` as Mermaid's quadrant grammar reads it, its coordinates kept as
 *              the ranges of the bytes they are written in; the lexer reads it on the bytes, with the white space this
 *              syntax takes.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

/// A quadrant chart point's `: [x, y]`, as Mermaid's quadrant grammar reads it: a colon and an opening bracket, with
/// any spaces and line breaks before, between and after them, then two coordinates separated by a comma and the
/// closing bracket, and the spaces after it. A coordinate is `1`, or `0` alone or followed by any character and digits
/// (`0.75`; Mermaid's pattern takes `0x5` and `0,5` too, which are no number from 0 to 1). `QuadrantChartLexer`
/// reads it on the bytes; a point whose brackets do not hold two coordinates is an error.
enum QuadrantChartPointSyntax {
    /// Spaces, tabs, line breaks, carriage returns, vertical tabs and form feeds: what Mermaid's `\s` takes here.
    static func isWhitespace(_ byte: UInt8) -> Bool {
        MermaidByte.isWhitespace(byte) || byte == 0x0B || byte == 0x0C
    }
}
