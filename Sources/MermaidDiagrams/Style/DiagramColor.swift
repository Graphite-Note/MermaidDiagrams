/**
 * File: DiagramColor.swift
 * ------------------------
 * Layer: Core
 * Description: A color a diagram's own statements give, a hexadecimal one read on its bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

import CoreGraphics

/// A color a diagram's own statements give (`fill:#f9f`, `stroke:rgb(51, 51, 51)`, `color:red`), as sRGB channels and opacity,
/// each from 0 to 1.
public struct DiagramColor: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// The color a style value writes, or nil for a value not read here: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`,
    /// `rgb(r, g, b)`, `rgba(r, g, b, a)` (channels 0 to 255 or percentages, opacity 0 to 1 or a percentage), a CSS color
    /// name, and `none` or `transparent`, which are no color at all. Case and spaces around the value do not matter.
    public init?(cssText: String) {
        if let read = Self.readOnBytes(cssText) {
            guard let color = read else { return nil }
            self = color
            return
        }
        let text = cssText.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") {
            guard let color = Self.hexadecimalColor(String(text.dropFirst())) else { return nil }
            self = color
        } else if text.hasPrefix("rgb"), let color = Self.functionalColor(text) {
            self = color
        } else if text == "none" || text == "transparent" {
            self = DiagramColor(red: 0, green: 0, blue: 0, alpha: 0)
        } else if let value = Self.cssColorNames[text] {
            self = DiagramColor(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
        } else {
            return nil
        }
    }

    /// The color an ASCII value written with `#` reads as, without the spaces and tabs around it (Foundation's
    /// `whitespaces` in ASCII) and in either case, as `init?(cssText:)` reads it through its characters: `.some(nil)`
    /// for one that is no color; nil, to be read through its characters, for any other value.
    private static func readOnBytes(_ cssText: String) -> DiagramColor?? {
        var text = cssText
        return text.withUTF8 { bytes -> DiagramColor?? in
            var start = 0
            var end = bytes.count
            while start < end, bytes[start] == MermaidByte.space || bytes[start] == MermaidByte.tab { start += 1 }
            while end > start, bytes[end - 1] == MermaidByte.space || bytes[end - 1] == MermaidByte.tab { end -= 1 }
            guard start < end, bytes[start] == UInt8(ascii: "#") else { return nil }
            let written = UnsafeBufferPointer(rebasing: bytes[start..<end])
            guard !written.contains(where: { byte in byte >= 0x80 }) else { return nil }
            return .some(hexadecimal(written))
        }
    }

    /// `#rgb`, `#rgba`, `#rrggbb` or `#rrggbbaa` of ASCII bytes that start with `#`, the digits in either case; nil for
    /// any other bytes. Each channel is the integer its digits write, divided by 255, as `hexadecimalColor` divides it.
    static func hexadecimal(_ written: UnsafeBufferPointer<UInt8>) -> DiagramColor? {
        let digitCount = written.count - 1
        guard digitCount == 3 || digitCount == 4 || digitCount == 6 || digitCount == 8 else { return nil }
        var channels: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 255)
        for channel in 0..<(digitCount <= 4 ? digitCount : digitCount / 2) {
            let value: UInt64
            if digitCount <= 4 {
                guard let digit = hexadecimalDigit(written[1 + channel]) else { return nil }
                value = digit * 17
            } else {
                guard let high = hexadecimalDigit(written[1 + 2 * channel]), let low = hexadecimalDigit(written[2 + 2 * channel]) else { return nil }
                value = high * 16 + low
            }
            switch channel {
            case 0: channels.0 = value
            case 1: channels.1 = value
            case 2: channels.2 = value
            default: channels.3 = value
            }
        }
        return DiagramColor(red: Double(channels.0) / 255, green: Double(channels.1) / 255, blue: Double(channels.2) / 255,
                            alpha: digitCount == 4 || digitCount == 8 ? Double(channels.3) / 255 : 1)
    }

    /// The value of an ASCII hexadecimal digit in either case, or nil.
    static func hexadecimalDigit(_ byte: UInt8) -> UInt64? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): UInt64(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): UInt64(byte - UInt8(ascii: "a") + 10)
        case UInt8(ascii: "A")...UInt8(ascii: "F"): UInt64(byte - UInt8(ascii: "A") + 10)
        default: nil
        }
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    private static func hexadecimalColor(_ digits: String) -> DiagramColor? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let expanded: String
        switch digits.count {
        case 3, 4: expanded = digits.map { digit in "\(digit)\(digit)" }.joined()
        case 6, 8: expanded = digits
        default: return nil
        }
        guard let value = UInt64(expanded, radix: 16) else { return nil }
        let hasOpacity = expanded.count == 8
        let shift: UInt64 = hasOpacity ? 8 : 0
        return DiagramColor(red: Double(value >> (16 + shift) & 0xFF) / 255, green: Double(value >> (8 + shift) & 0xFF) / 255,
                            blue: Double(value >> shift & 0xFF) / 255, alpha: hasOpacity ? Double(value & 0xFF) / 255 : 1)
    }

    /// `rgb(51, 51, 51)`, `rgba(51 51 51 / 50%)` and `rgb(20%, 20%, 20%)`.
    private static func functionalColor(_ text: String) -> DiagramColor? {
        guard let opening = text.firstIndex(of: "("), text.hasSuffix(")"), ["rgb", "rgba"].contains(String(text[..<opening])) else { return nil }
        let inside = text[text.index(after: opening)..<text.index(before: text.endIndex)]
        let parts = inside.split(whereSeparator: { character in character == "," || character == " " || character == "/" }).map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        var channels: [Double] = []
        for part in parts.prefix(3) {
            guard let channel = number(part, fullScale: 255) else { return nil }
            channels.append(min(1, max(0, channel)))
        }
        let alpha = parts.count == 4 ? number(parts[3], fullScale: 1).map { opacity in min(1, max(0, opacity)) } : 1
        guard let alpha else { return nil }
        return DiagramColor(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
    }

    /// A number out of `fullScale`, or a percentage.
    private static func number(_ text: String, fullScale: Double) -> Double? {
        if text.hasSuffix("%") { return Double(text.dropLast()).map { percentage in percentage / 100 } }
        return Double(text).map { value in value / fullScale }
    }
}
