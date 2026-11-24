/**
 * File: DiagramSeriesInk.swift
 * ----------------------------
 * Layer: Core
 * Description: The label color Pele picks for text on a series color a diagram's theme variables set: its dark text on
 *              a light color, white on a dark one, where the color's contrast is known (Pele's src/svg/ink.ts); a
 *              hexadecimal color read on its bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import Foundation

/// Pele's `ink` of a fill of one color (`ink(";fill:" + color)` in its palette.ts), ported as it reads the color: a
/// hexadecimal color, one of CSS's names (whose contrast is fixed by a list of dark names and a list of light ones), or
/// `rgb()`, `rgba()`, `hsl()` and `hsla()` in Pele's own reading of their arguments. Any other color, a `var()` or a
/// `color-mix()` among them, has no known contrast and so no ink, and neither has a color under half opacity.
enum DiagramSeriesInk {
    /// `--pele-fg-on-light`'s fallback, #1f1f1f, and `--pele-fg-on-dark`'s, white.
    static let onLight = DiagramColor(red: 31.0 / 255, green: 31.0 / 255, blue: 31.0 / 255)
    static let onDark = DiagramColor(red: 1, green: 1, blue: 1)

    /// The ink for text on `color`, or nil where Pele picks none.
    static func ink(on color: String) -> DiagramColor? {
        guard let (luminance, alpha) = luminanceAndAlpha(color), alpha >= 0.5 else { return nil }
        return luminance > evenLuminance ? onLight : onDark
    }

    /// The luminance where #1f1f1f and white contrast equally.
    private static let evenLuminance = (1.05 * (luminance(31.0 / 255, 31.0 / 255, 31.0 / 255) + 0.05)).squareRoot() - 0.05

    /// Luminance and opacity, as Pele's `color` gives them: named colors 0 or 1, so that only their side counts.
    static func luminanceAndAlpha(_ raw: String) -> (Double, Double)? {
        if let (_, color) = DiagramThemeColor.hexadecimalColor(raw) {
            return (luminance(color.red, color.green, color.blue), color.alpha)
        }
        return luminanceAndAlphaOfText(raw)
    }

    /// `luminanceAndAlpha` read through the value's characters, as it reads every value but an ASCII hexadecimal one.
    static func luminanceAndAlphaOfText(_ raw: String) -> (Double, Double)? {
        let value = String(JavaScriptWhitespace.trimmed(Substring(raw))).lowercased()
        let name = value.replacingFirst("grey", with: "gray")
        if darkNames.contains(name) { return (0, 1) }
        if lightNames.contains(name) { return (1, 1) }
        if let hexadecimal = hexadecimalLuminanceAndAlpha(value) { return hexadecimal }
        guard let (isHueSaturationLightness, arguments) = functionArguments(value),
              let list = argumentList(arguments, isHueSaturationLightness: isHueSaturationLightness) else { return nil }
        let alpha = list.count == 4 ? amount(list[3], full: 1) : 1
        let channels: [Double]
        if isHueSaturationLightness {
            let hueSector = (hue(list[0]).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 30
            // JavaScript's Math.min and Math.max give NaN for a hue that is no number (a percentage); Swift's min and max
            // would drop it and pick a channel, so such a hue has no ink here as in Pele.
            guard !hueSector.isNaN else { return nil }
            let saturation = amount(list[1], full: 100)
            let lightness = amount(list[2], full: 100)
            let chroma = saturation * min(lightness, 1 - lightness)
            channels = [0.0, 8, 4].map { offset in
                let turn = (offset + hueSector).truncatingRemainder(dividingBy: 12)
                return lightness - chroma * max(-1, min(turn - 3, 9 - turn, 1))
            }
        } else {
            channels = list.prefix(3).map { channel in amount(channel, full: 255) }
        }
        let found = luminance(channels[0], channels[1], channels[2])
        return (found + alpha).isNaN ? nil : (found, alpha)
    }

    /// `#rgb`, `#rgba`, `#rrggbb` or `#rrggbbaa`.
    private static func hexadecimalLuminanceAndAlpha(_ value: String) -> (Double, Double)? {
        let digits = value.dropFirst()
        guard value.hasPrefix("#"), [3, 4, 6, 8].contains(digits.count), digits.allSatisfy({ digit in digit.isASCII && digit.isHexDigit }) else { return nil }
        let expanded = value.count < 6 ? digits.map { digit in "\(digit)\(digit)" }.joined() : String(digits)
        let bytes = stride(from: 0, to: expanded.count, by: 2).map { start -> Double in
            let pair = expanded.dropFirst(start).prefix(2)
            return Double(UInt8(pair, radix: 16) ?? 0) / 255
        }
        return (luminance(bytes[0], bytes[1], bytes[2]), bytes.count == 4 ? bytes[3] : 1)
    }

    /// `rgb(…)`, `rgba(…)`, `hsl(…)` or `hsla(…)` with no parenthesis inside: whether it is a hue's, and its arguments.
    private static func functionArguments(_ value: String) -> (Bool, Substring)? {
        guard let opening = value.firstIndex(of: "("), value.hasSuffix(")") else { return nil }
        let name = value[..<opening]
        let arguments = value[value.index(after: opening)..<value.index(before: value.endIndex)]
        guard ["rgb", "rgba", "hsl", "hsla"].contains(name), !arguments.contains("("), !arguments.contains(")") else { return nil }
        return (name.hasPrefix("hsl"), arguments)
    }

    /// Pele's `args`: the comma syntax takes no `none`, its `rgb()` channels all or none in %, its `hsl()` saturation and
    /// lightness in %; the space syntax takes three values and an opacity after `/`.
    private static func argumentList(_ body: Substring, isHueSaturationLightness: Bool) -> [Substring]? {
        let isLegacy = body.contains(",")
        let parts = isLegacy ? [body] : body.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let main = JavaScriptWhitespace.trimmed(parts[0])
        var list = isLegacy ? JavaScriptWhitespace.pieces(ofCommaSeparated: main) : JavaScriptWhitespace.pieces(ofWhitespaceSeparated: main)
        guard isLegacy ? (3...4).contains(list.count) : list.count == 3 else { return nil }
        if parts.count == 2 { list.append(JavaScriptWhitespace.trimmed(parts[1])) }
        guard isLegacy else { return list.map { channel in channel == "none" ? "0" : channel } }
        let percentages = list[(isHueSaturationLightness ? 1 : 0)..<3].filter { channel in channel.hasSuffix("%") }.count
        return percentages == (isHueSaturationLightness ? 2 : 3) || (!isHueSaturationLightness && percentages == 0) ? list : nil
    }

    /// A number out of `full`, or a percentage, clamped to 0…1; not a number for anything else.
    private static func amount(_ raw: Substring, full: Double) -> Double {
        guard let (number, unit) = JavaScriptCSSNumber.read(raw), unit == nil || unit == "%" else { return .nan }
        return min(max(number / (unit == nil ? full : 100), 0), 1)
    }

    /// A hue in degrees, from degrees, gradians, radians or turns; not a number for a percentage or anything else.
    private static func hue(_ raw: Substring) -> Double {
        guard let (number, unit) = JavaScriptCSSNumber.read(raw), unit != "%" else { return .nan }
        switch unit {
        case "turn": return number * 360
        case "rad": return number * 180 / .pi
        case "grad": return number * 0.9
        default: return number
        }
    }

    private static func luminance(_ red: Double, _ green: Double, _ blue: Double) -> Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The named colors white contrasts with more than #1f1f1f does, and the rest, as Pele lists them.
    private static let darkNames = Set(("black blue blueviolet brown crimson darkblue darkcyan darkgreen darkmagenta darkolivegreen darkorchid "
        + "darkred darkslateblue darkslategray darkviolet dimgray firebrick forestgreen green indigo maroon mediumblue mediumslateblue "
        + "mediumvioletred midnightblue navy olive purple rebeccapurple royalblue saddlebrown seagreen sienna slateblue steelblue teal")
        .split(separator: " ").map(String.init))
    private static let lightNames = Set(("aliceblue antiquewhite aqua aquamarine azure beige bisque blanchedalmond burlywood cadetblue chartreuse "
        + "chocolate coral cornflowerblue cornsilk cyan darkgoldenrod darkgray darkkhaki darkorange darksalmon darkseagreen darkturquoise "
        + "deeppink deepskyblue dodgerblue floralwhite fuchsia gainsboro ghostwhite gold goldenrod gray greenyellow honeydew hotpink indianred "
        + "ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen "
        + "lightpink lightsalmon lightseagreen lightskyblue lightslategray lightsteelblue lightyellow lime limegreen linen magenta "
        + "mediumaquamarine mediumorchid mediumpurple mediumseagreen mediumspringgreen mediumturquoise mintcream mistyrose moccasin navajowhite "
        + "oldlace olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum "
        + "powderblue red rosybrown salmon sandybrown seashell silver skyblue slategray snow springgreen tan thistle tomato turquoise violet "
        + "wheat white whitesmoke yellow yellowgreen").split(separator: " ").map(String.init))

    /// Whether `value`, lower case, is one of the names either list holds, `grey` read as `gray`.
    static func isNamedColor(_ value: String) -> Bool {
        let name = value.replacingFirst("grey", with: "gray")
        return darkNames.contains(name) || lightNames.contains(name)
    }
}

/// A number as Pele's pattern `^[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:e[+-]?\d+)?(%|deg|grad|rad|turn)?$` (case-insensitive)
/// reads it, with its unit lower case.
enum JavaScriptCSSNumber {
    static func read(_ raw: Substring) -> (Double, String?)? {
        let units = ["%", "deg", "grad", "rad", "turn"]
        let lowered = raw.lowercased()
        let unit = units.first { unit in lowered.hasSuffix(unit) }
        let digits = Array(lowered.dropLast(unit?.count ?? 0).utf8)
        guard isNumber(digits), let number = Double(String(decoding: digits, as: UTF8.self)) else { return nil }
        return (number, unit)
    }

    /// `[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:e[+-]?\d+)?` over lower-case bytes.
    private static func isNumber(_ bytes: [UInt8]) -> Bool {
        var index = 0
        func digitRun() -> Int {
            let start = index
            while index < bytes.count, MermaidByte.isDigit(bytes[index]) { index += 1 }
            return index - start
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
        let whole = digitRun()
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            guard digitRun() > 0 else { return false }
        } else if whole == 0 {
            return false
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") {
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard digitRun() > 0 else { return false }
        }
        return index == bytes.count
    }
}

extension String {
    /// The string with its first `target` replaced, as JavaScript's `replace` with a string replaces.
    func replacingFirst(_ target: String, with replacement: String) -> String {
        guard let range = range(of: target) else { return self }
        return replacingCharacters(in: range, with: replacement)
    }
}
