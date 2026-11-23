/**
 * File: DiagramColorFunction.swift
 * --------------------------------
 * Layer: Core
 * Description: CSS's color functions whose channels are written out, read as CSS Color 4 reads them: rgb(), hsl(),
 *              hwb(), lab(), lch(), oklab(), oklch() and color(), in the comma syntax where CSS has one.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// One channel of a color function as written: a number, a percentage, an angle in degrees, or `none`.
enum CSSColorComponent: Equatable {
    case number(Double)
    case percentage(Double)
    case angle(Double)
    case none

    init?(_ text: Substring) {
        if text.lowercased() == "none" {
            self = .none
            return
        }
        guard let (number, unit) = JavaScriptCSSNumber.read(text) else { return nil }
        switch unit {
        case nil: self = .number(number)
        case "%": self = .percentage(number)
        case "turn": self = .angle(number * 360)
        case "rad": self = .angle(number * 180 / .pi)
        case "grad": self = .angle(number * 0.9)
        default: self = .angle(number)
        }
    }

    /// A channel whose `100%` is `full`, as a number; nil for an angle.
    func value(percentageOf full: Double) -> Double? {
        switch self {
        case .number(let number): number
        case .percentage(let percentage): percentage / 100 * full
        case .none: 0
        case .angle: nil
        }
    }

    /// A hue in degrees; nil for a percentage.
    var hue: Double? {
        switch self {
        case .number(let degrees), .angle(let degrees): degrees
        case .none: 0
        case .percentage: nil
        }
    }

    var isPercentage: Bool {
        if case .percentage = self { true } else { false }
    }
}

/// A color function with its channels written out, read to a linear sRGB color.
enum DiagramColorFunction {
    static func read(name: String, arguments: Substring) -> DiagramLinearColor? {
        guard let (channels, alpha, isLegacy) = channelsAndAlpha(arguments, leadingWords: name == "color" ? 1 : 0) else { return nil }
        var opacity = 1.0
        if let alpha {
            guard let value = alpha.value(percentageOf: 1) else { return nil }
            opacity = min(max(value, 0), 1)
        }
        switch name {
        case "rgb", "rgba": return rgb(channels.components, isLegacy: isLegacy, alpha: opacity)
        case "hsl", "hsla": return hueSaturationLightness(channels.components, isLegacy: isLegacy, alpha: opacity)
        case "hwb" where !isLegacy: return hueWhitenessBlackness(channels.components, alpha: opacity)
        case "lab" where !isLegacy, "lch" where !isLegacy, "oklab" where !isLegacy, "oklch" where !isLegacy:
            return DiagramColorSpaces.labFamily(name, channels.components, alpha: opacity)
        case "color" where !isLegacy: return DiagramColorSpaces.predefined(channels.space, channels.components, alpha: opacity)
        default: return nil
        }
    }

    /// The three channels (after the space's name for `color()`) and the opacity: comma-separated with an optional
    /// fourth opacity, or space-separated with an optional opacity after `/`.
    private static func channelsAndAlpha(_ arguments: Substring,
                                         leadingWords: Int) -> (channels: (space: String, components: [CSSColorComponent]), alpha: CSSColorComponent?, isLegacy: Bool)? {
        if CSSColorSyntax.firstTopLevelComma(in: arguments) != nil {
            let pieces = CSSColorSyntax.topLevelPieces(of: arguments, separatedBy: ",")
            guard leadingWords == 0, (3...4).contains(pieces.count) else { return nil }
            let components = pieces.compactMap { piece in CSSColorComponent(piece) }
            guard components.count == pieces.count, !components.contains(.none) else { return nil }
            return (("", Array(components.prefix(3))), components.count == 4 ? components[3] : nil, true)
        }
        let halves = CSSColorSyntax.topLevelPieces(of: arguments, separatedBy: "/")
        guard (1...2).contains(halves.count) else { return nil }
        let words = CSSColorSyntax.topLevelWords(of: halves[0])
        guard words.count == 3 + leadingWords else { return nil }
        let components = words.dropFirst(leadingWords).compactMap { word in CSSColorComponent(word) }
        guard components.count == 3 else { return nil }
        let alpha = halves.count == 2 ? CSSColorComponent(halves[1]) : nil
        if halves.count == 2, alpha == nil { return nil }
        return ((words.first.map { word in word.lowercased() } ?? "", components), alpha, false)
    }

    /// `rgb()`: channels out of 255 or percentages, all of one kind in the comma syntax, clamped.
    private static func rgb(_ channels: [CSSColorComponent], isLegacy: Bool, alpha: Double) -> DiagramLinearColor? {
        if isLegacy, Set(channels.map(\.isPercentage)).count != 1 { return nil }
        let values = channels.compactMap { channel in channel.value(percentageOf: 255).map { value in min(max(value / 255, 0), 1) } }
        guard values.count == 3 else { return nil }
        return DiagramLinearColor(encodedRed: values[0], green: values[1], blue: values[2], alpha: alpha)
    }

    /// `hsl()`: a hue, then saturation and lightness, percentages in the comma syntax.
    private static func hueSaturationLightness(_ channels: [CSSColorComponent], isLegacy: Bool, alpha: Double) -> DiagramLinearColor? {
        if isLegacy, !channels[1].isPercentage || !channels[2].isPercentage { return nil }
        guard let hue = channels[0].hue, let saturation = channels[1].value(percentageOf: 100),
              let lightness = channels[2].value(percentageOf: 100) else { return nil }
        let encoded = DiagramColorSpaces.encodedRGB(hue: hue, saturation: min(max(saturation / 100, 0), 1), lightness: min(max(lightness / 100, 0), 1))
        return DiagramLinearColor(encodedRed: encoded[0], green: encoded[1], blue: encoded[2], alpha: alpha)
    }

    /// `hwb()`: a hue, then whiteness and blackness, scaled down together when they add up past 100%.
    private static func hueWhitenessBlackness(_ channels: [CSSColorComponent], alpha: Double) -> DiagramLinearColor? {
        guard let hue = channels[0].hue, let whiteness = channels[1].value(percentageOf: 100),
              let blackness = channels[2].value(percentageOf: 100) else { return nil }
        let encoded = DiagramColorSpaces.encodedRGB(hue: hue, whiteness: min(max(whiteness / 100, 0), 1), blackness: min(max(blackness / 100, 0), 1))
        return DiagramLinearColor(encodedRed: encoded[0], green: encoded[1], blue: encoded[2], alpha: alpha)
    }
}
