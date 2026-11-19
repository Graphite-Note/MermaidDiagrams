/**
 * File: SequenceBoxSyntax.swift
 * -----------------------------
 * Layer: Core
 * Description: Reads a sequence `box` line into its color and its title, as Mermaid splits it: the first word, or an
 *              `rgb()`/`hsl()` call, when it is a CSS color, and the rest as the title.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import Foundation

/// `box Aqua Front end`, `box rgb(33, 66, 99) Back end`, `box Group`, `box`: Mermaid asks the browser whether the line's
/// first word (or its leading `rgb(…)`, `rgba(…)`, `hsl(…)`, `hsla(…)`) is a CSS color; Pele, without a browser, knows
/// CSS's color keywords and checks the notation of the four functions. A color takes the first word off the title;
/// otherwise the whole line is the title, as is any `wrap:` after the color.
enum SequenceBoxSyntax {
    /// The box a line describes, its text as read after `box`.
    static func box(from line: String) -> SequenceBox {
        let parts = split(line)
        var color = parts.flatMap { written, _ in written.isEmpty ? nil : written.trimmingCharacters(in: .whitespaces) } ?? "transparent"
        var title = parts.flatMap { _, rest in rest.isEmpty ? nil : rest.trimmingCharacters(in: .whitespaces) }
        if !isCSSColor(color) {
            color = "transparent"
            title = line.trimmingCharacters(in: .whitespaces)
        }
        let shade = color.lowercased() == "transparent" ? nil : SequenceHighlightColorSyntax.color(from: color)
        guard let title else { return SequenceBox(title: nil, wrapsTitle: false, color: shade) }
        let written = SequenceTextSyntax.withoutWrapPrefix(title)
        return SequenceBox(title: written.text.isEmpty ? nil : written.label, wrapsTitle: written.wraps, color: shade)
    }

    /// Mermaid's `/^((?:rgba?|hsla?)\s*\(.*\)|\w*)(.*)$/`: a function call up to the line's last `)`, or the leading
    /// letters, digits and underscores, then the rest. Nil when a line terminator (`\r`, U+2028, U+2029) stops `.` from
    /// matching.
    private static func split(_ line: String) -> (String, String)? {
        let scalars = Array(line.unicodeScalars)
        func text(_ range: Range<Int>) -> String { SequenceAttributesFlowSyntax.string(Array(scalars[range])) }
        if let functionLength = functionPrefixLength(scalars), let close = scalars.lastIndex(of: ")"), close >= functionLength {
            if scalars[functionLength...].contains(where: isLineTerminator) { return nil }
            return (text(0..<(close + 1)), text((close + 1)..<scalars.count))
        }
        if scalars.contains(where: isLineTerminator) { return nil }
        let wordLength = scalars.prefix { scalar in scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == "_") }.count
        return (text(0..<wordLength), text(wordLength..<scalars.count))
    }

    /// The length of `rgb(`, `rgba(`, `hsl(` or `hsla(`, with any white space before the parenthesis, at the start.
    private static func functionPrefixLength(_ scalars: [Unicode.Scalar]) -> Int? {
        for name in ["rgba", "rgb", "hsla", "hsl"] where scalars.starts(with: name.unicodeScalars) {
            var index = name.unicodeScalars.count
            while index < scalars.count, scalars[index].properties.isWhitespace { index += 1 }
            return index < scalars.count && scalars[index] == "(" ? index + 1 : nil
        }
        return nil
    }

    private static func isLineTerminator(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\r" || scalar == "\u{2028}" || scalar == "\u{2029}"
    }

    /// Whether `color` is a CSS color as Pele recognizes one: a color keyword in any case, or a well-formed `rgb()`,
    /// `rgba()`, `hsl()` or `hsla()` of at most 120 characters.
    static func isCSSColor(_ color: String) -> Bool {
        if color.contains("(") { return SequenceBoxColorFunctionSyntax.isColorFunction(color) }
        return keywords.contains(color.lowercased())
    }

    private static let keywords: Set<String> = Set("""
        aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown burlywood
        cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray
        darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen
        darkslateblue darkslategray darkslategrey darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue
        firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray green greenyellow grey honeydew
        hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan
        lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon lightseagreen lightskyblue lightslategray
        lightslategrey lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue
        mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred
        midnightblue mintcream mistyrose moccasin navajowhite navy oldlace olive olivedrab orange orangered orchid
        palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue purple
        rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue
        slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato turquoise violet wheat white
        whitesmoke yellow yellowgreen transparent currentcolor inherit initial unset revert
        accentcolor accentcolortext activetext buttonborder buttonface buttontext canvas canvastext field fieldtext
        graytext highlight highlighttext linktext mark marktext selecteditem selecteditemtext visitedtext
        activeborder activecaption appworkspace background buttonhighlight buttonshadow captiontext inactiveborder
        inactivecaption inactivecaptiontext infobackground infotext menu menutext scrollbar threeddarkshadow threedface
        threedhighlight threedlightshadow threedshadow window windowframe windowtext
        """.split(whereSeparator: { character in character == " " || character == "\n" }).map(String.init))
}
