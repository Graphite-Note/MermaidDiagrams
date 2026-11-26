/**
 * File: TreemapValueFormatSpecifier.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Reads the parts of a treemap's d3-format specifier from its bytes, as the specifier's regular expression
 *              matches them, for a specifier of printable ASCII.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

/// The parts of a value format's specifier the treemap reads: sign, `$`, `,`, the precision's digits, `~` and the type.
struct TreemapValueFormatParts: Equatable {
    var sign: String?
    var currency: String?
    var groupsThousands = false
    var precisionDigits: String?
    var dropsTrailingZeros = false
    var type: Character?
}

/// `TreemapValueFormat`'s pattern, `^(?:.?[<>=^])?([-+( ])?(\$)?0?[0-9]*(,)?(?:\.([0-9]+))?(~)?([a-zA-Z%])?$`, matched on
/// the bytes of a specifier of printable ASCII without compiling or running the expression. The pattern tries a fill
/// and an alignment, then an alignment alone, then neither, and what follows is matched in one way at most (each part
/// after the alignment starts with bytes no later part does), so trying the three starts in that order gives the match
/// and the groups the expression gives.
enum TreemapValueFormatSpecifier {
    /// The parts of `bytes`, nil when the pattern does not match them; `isReadable` false (nothing read) when a byte is
    /// not printable ASCII, whose matching (a line break before the end, `.` over a character of several bytes) is left
    /// to the expression.
    static func parts(of bytes: UnsafeBufferPointer<UInt8>) -> (isReadable: Bool, parts: TreemapValueFormatParts?) {
        guard bytes.allSatisfy({ byte in byte >= 0x20 && byte < 0x7F }) else { return (false, nil) }
        if bytes.count >= 2, isAlignment(bytes[1]), let parts = remainder(bytes, from: 2) { return (true, parts) }
        if bytes.count >= 1, isAlignment(bytes[0]), let parts = remainder(bytes, from: 1) { return (true, parts) }
        return (true, remainder(bytes, from: 0))
    }

    private static func isAlignment(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "<") || byte == UInt8(ascii: ">") || byte == UInt8(ascii: "=") || byte == UInt8(ascii: "^")
    }

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }

    /// `([-+( ])?(\$)?0?[0-9]*(,)?(?:\.([0-9]+))?(~)?([a-zA-Z%])?$` from `start`.
    private static func remainder(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> TreemapValueFormatParts? {
        var parts = TreemapValueFormatParts()
        var index = start
        let count = bytes.count
        if index < count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "(")
            || bytes[index] == UInt8(ascii: " ") {
            parts.sign = String(UnicodeScalar(bytes[index]))
            index += 1
        }
        if index < count, bytes[index] == UInt8(ascii: "$") {
            parts.currency = "$"
            index += 1
        }
        while index < count, isDigit(bytes[index]) { index += 1 }
        if index < count, bytes[index] == UInt8(ascii: ",") {
            parts.groupsThousands = true
            index += 1
        }
        if index + 1 < count, bytes[index] == UInt8(ascii: "."), isDigit(bytes[index + 1]) {
            let digitsStart = index + 1
            index = digitsStart
            while index < count, isDigit(bytes[index]) { index += 1 }
            parts.precisionDigits = String(decoding: UnsafeBufferPointer(rebasing: bytes[digitsStart..<index]), as: UTF8.self)
        }
        if index < count, bytes[index] == UInt8(ascii: "~") {
            parts.dropsTrailingZeros = true
            index += 1
        }
        if index < count, isType(bytes[index]) {
            parts.type = Character(UnicodeScalar(bytes[index]))
            index += 1
        }
        return index == count ? parts : nil
    }

    private static func isType(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z")) || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")) || byte == UInt8(ascii: "%")
    }
}
