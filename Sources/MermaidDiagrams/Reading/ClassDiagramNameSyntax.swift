/**
 * File: ClassDiagramNameSyntax.swift
 * ----------------------------------
 * Layer: Core
 * Description: Reads a class diagram's class names and the generic types after them on the text's borrowed bytes, as
 *              byte ranges: plain names, backticked names, `~T~`.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

/// A class's name as a class diagram writes it, and the generic type after it, by their bytes.
struct ClassDiagramName: Equatable {
    let identifier: MermaidTextRange
    /// The text between the tildes after the name (`T` in `Square~T~`), or nil when there is none or it is empty.
    let genericType: MermaidTextRange?
}

/// Reads class names: identifier characters (letters, digits, `_`, any character beyond ASCII), with a `-` or a `.`
/// kept where another identifier character follows it (`Ca-r`, `Company.Engine`, while `A--B` and `A..B` stop before
/// the line); or any text but a backtick between backticks (`` `Animal Class!` ``). A generic type between tildes may
/// follow either (`Square~Shape~`).
enum ClassDiagramNameSyntax {
    /// Reads a name at the position and moves past it, or returns nil, without moving, when no name starts there.
    static func read(_ bytes: inout GraphDiagramBytes) throws(MermaidDiagramReadError) -> ClassDiagramName? {
        let identifier: MermaidTextRange
        if bytes.peek() == MermaidByte.graveAccent {
            identifier = try readBacktickedName(&bytes)
        } else if let plain = readPlainName(&bytes) {
            identifier = plain
        } else {
            return nil
        }
        return ClassDiagramName(identifier: identifier, genericType: try readGenericType(&bytes))
    }

    private static func readPlainName(_ bytes: inout GraphDiagramBytes) -> MermaidTextRange? {
        let start = bytes.position
        while let byte = bytes.peek() {
            if MermaidByte.isIdentifierByte(byte) {
                bytes.advance()
            } else if byte == MermaidByte.hyphen || byte == MermaidByte.period, bytes.position > start, let next = bytes.peek(1),
                      MermaidByte.isIdentifierByte(next) {
                bytes.advance()
            } else {
                break
            }
        }
        return bytes.position > start ? MermaidTextRange(start: start, end: bytes.position) : nil
    }

    /// `` `any text` `` on one line.
    private static func readBacktickedName(_ bytes: inout GraphDiagramBytes) throws(MermaidDiagramReadError) -> MermaidTextRange {
        let opening = bytes.position
        bytes.advance()
        let start = bytes.position
        while let byte = bytes.peek(), byte != MermaidByte.graveAccent, byte != MermaidByte.newline { bytes.advance() }
        guard bytes.peek() == MermaidByte.graveAccent else { throw .invalidSyntax(line: bytes.line(at: opening), problem: .unclosedQuotation) }
        let name = MermaidTextRange(start: start, end: bytes.position)
        bytes.advance()
        return name
    }

    /// `~T~` right after a name, on one line; nil when there is none or it is empty.
    private static func readGenericType(_ bytes: inout GraphDiagramBytes) throws(MermaidDiagramReadError) -> MermaidTextRange? {
        guard bytes.peek() == MermaidByte.tilde else { return nil }
        let opening = bytes.position
        bytes.advance()
        let start = bytes.position
        while let byte = bytes.peek(), byte != MermaidByte.tilde, byte != MermaidByte.newline { bytes.advance() }
        guard bytes.peek() == MermaidByte.tilde else { throw .invalidSyntax(line: bytes.line(at: opening), problem: .unclosedGenericType) }
        let genericType = MermaidTextRange(start: start, end: bytes.position)
        bytes.advance()
        return genericType.isEmpty ? nil : genericType
    }
}
