/**
 * File: DiagramColorMixture.swift
 * -------------------------------
 * Layer: Core
 * Description: CSS's color-mix() of two colors: read, and mixed as CSS Color 5 mixes them, in a rectangular space with
 *              premultiplied opacity or in a polar one along its hue.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation

/// A space `color-mix()` mixes in.
enum DiagramMixingSpace: String, Hashable, Sendable {
    case sRGB = "srgb"
    case linearSRGB = "srgb-linear"
    case displayP3 = "display-p3"
    case lab, oklab, hsl, hwb, lch, oklch
    case xyz
    case xyzD65 = "xyz-d65"
    case xyzD50 = "xyz-d50"

    /// Where its hue lies among its coordinates, for a polar space.
    var hueIndex: Int? {
        switch self {
        case .hsl, .hwb: 0
        case .lch, .oklch: 2
        default: nil
        }
    }
}

/// How a polar space's hue runs from one color's to the other's.
enum DiagramHueInterpolation: String, Hashable, Sendable {
    case shorter, longer, increasing, decreasing
}

/// `color-mix(in <space> [<hue> hue], <color> [<percentage>], <color> [<percentage>])`.
struct DiagramColorMixture: Hashable, Sendable {
    let space: DiagramMixingSpace
    let hueInterpolation: DiagramHueInterpolation
    let first: DiagramThemeColorExpression
    let firstPercentage: Double?
    let second: DiagramThemeColorExpression
    let secondPercentage: Double?

    static func read(_ arguments: Substring, depth: Int) -> DiagramColorMixture? {
        let pieces = CSSColorSyntax.topLevelPieces(of: arguments, separatedBy: ",")
        guard pieces.count == 3 else { return nil }
        let method = CSSColorSyntax.topLevelWords(of: pieces[0]).map { word in word.lowercased() }
        guard method.count >= 2, method[0] == "in", let space = DiagramMixingSpace(rawValue: method[1]) else { return nil }
        var hueInterpolation = DiagramHueInterpolation.shorter
        if method.count == 4, space.hueIndex != nil, method[3] == "hue", let named = DiagramHueInterpolation(rawValue: method[2]) {
            hueInterpolation = named
        } else if method.count != 2 {
            return nil
        }
        guard let (first, firstPercentage) = colorAndPercentage(pieces[1], depth: depth),
              let (second, secondPercentage) = colorAndPercentage(pieces[2], depth: depth) else { return nil }
        return DiagramColorMixture(space: space, hueInterpolation: hueInterpolation, first: first, firstPercentage: firstPercentage, second: second,
                                   secondPercentage: secondPercentage)
    }

    /// A color with an optional percentage from 0% to 100% before or after it.
    private static func colorAndPercentage(_ piece: Substring, depth: Int) -> (DiagramThemeColorExpression, Double?)? {
        let words = CSSColorSyntax.topLevelWords(of: piece)
        guard let firstWord = words.first, let lastWord = words.last else { return nil }
        func percentage(_ word: Substring) -> Double? {
            guard words.count > 1, let (number, unit) = JavaScriptCSSNumber.read(word), unit == "%" else { return nil }
            return number
        }
        let leading = percentage(firstWord)
        let trailing = leading == nil ? percentage(lastWord) : nil
        let given = leading ?? trailing
        if let given, !(0...100).contains(given) { return nil }
        let colorStart = leading == nil ? firstWord.startIndex : words[1].startIndex
        let colorEnd = trailing == nil ? lastWord.endIndex : words[words.count - 2].endIndex
        return (DiagramThemeColorExpression.read(piece[colorStart..<colorEnd], depth: depth + 1), given)
    }

    /// The two colors mixed: percentages that do not add up to 100% scaled to, and below it lowering the opacity; nil
    /// when both are 0%, which CSS refuses.
    func mixed(_ firstColor: DiagramLinearColor, _ secondColor: DiagramLinearColor) -> DiagramLinearColor? {
        let firstShare = firstPercentage ?? secondPercentage.map { percentage in 100 - percentage } ?? 50
        let secondShare = secondPercentage ?? 100 - firstShare
        let total = firstShare + secondShare
        guard total > 0 else { return nil }
        let share = secondShare / total
        var start = DiagramMixingCoordinates(firstColor, in: space)
        var end = DiagramMixingCoordinates(secondColor, in: space)
        if let hueIndex = space.hueIndex { DiagramMixingCoordinates.alignHues(&start, &end, at: hueIndex, by: hueInterpolation) }
        let alpha = start.alpha + (end.alpha - start.alpha) * share
        let values = start.values.indices.map { index -> Double in
            guard index != space.hueIndex else { return start.values[index] + (end.values[index] - start.values[index]) * share }
            let mixedValue = start.values[index] * start.alpha + (end.values[index] * end.alpha - start.values[index] * start.alpha) * share
            return alpha == 0 ? mixedValue : mixedValue / alpha
        }
        var color = DiagramMixingCoordinates(values: values, alpha: alpha * min(total, 100) / 100).linearColor(in: space)
        color.alpha = min(max(color.alpha, 0), 1)
        return color
    }
}

/// A color's coordinates in a mixing space, a polar space's hue NaN where it has none (a gray's).
struct DiagramMixingCoordinates {
    var values: [Double]
    var alpha: Double

    init(values: [Double], alpha: Double) {
        self.values = values
        self.alpha = alpha
    }

    init(_ color: DiagramLinearColor, in space: DiagramMixingSpace) {
        let linear = color.channels
        let xyz = DiagramColorSpaces.xyz(fromLinearRGB: linear)
        switch space {
        case .sRGB: values = linear.map(DiagramColorSpaces.encoded)
        case .linearSRGB: values = linear
        case .displayP3: values = DiagramColorSpaces.multiply(DiagramColorSpaces.xyzToDisplayP3, xyz).map(DiagramColorSpaces.encoded)
        case .lab: values = DiagramColorSpaces.lab(fromXYZD50: DiagramColorSpaces.multiply(DiagramColorSpaces.d65ToD50, xyz))
        case .lch: values = Self.withoutPowerlessHue(DiagramColorSpaces.polar(DiagramColorSpaces.lab(fromXYZD50: DiagramColorSpaces.multiply(DiagramColorSpaces.d65ToD50, xyz))))
        case .oklab: values = DiagramColorSpaces.oklab(fromLinearRGB: linear)
        case .oklch: values = Self.withoutPowerlessHue(DiagramColorSpaces.polar(DiagramColorSpaces.oklab(fromLinearRGB: linear)))
        case .xyz, .xyzD65: values = xyz
        case .xyzD50: values = DiagramColorSpaces.multiply(DiagramColorSpaces.d65ToD50, xyz)
        case .hsl, .hwb: values = Self.cylindrical(linear.map(DiagramColorSpaces.encoded), isWhitenessBlackness: space == .hwb)
        }
        alpha = color.alpha
    }

    func linearColor(in space: DiagramMixingSpace) -> DiagramLinearColor {
        let linear: [Double]
        switch space {
        case .sRGB: linear = values.map(DiagramColorSpaces.linear)
        case .linearSRGB: linear = values
        case .displayP3: linear = DiagramColorSpaces.linearRGB(fromXYZ: DiagramColorSpaces.multiply(DiagramColorSpaces.displayP3ToXYZ, values.map(DiagramColorSpaces.linear)))
        case .lab: linear = DiagramColorSpaces.linearRGB(fromXYZ: DiagramColorSpaces.multiply(DiagramColorSpaces.d50ToD65, DiagramColorSpaces.xyzD50(fromLab: values)))
        case .lch:
            let lab = DiagramColorSpaces.rectangular(lightness: values[0], chroma: values[1], hue: values[2])
            linear = DiagramColorSpaces.linearRGB(fromXYZ: DiagramColorSpaces.multiply(DiagramColorSpaces.d50ToD65, DiagramColorSpaces.xyzD50(fromLab: lab)))
        case .oklab: linear = DiagramColorSpaces.linearRGB(fromOklab: values)
        case .oklch: linear = DiagramColorSpaces.linearRGB(fromOklab: DiagramColorSpaces.rectangular(lightness: values[0], chroma: values[1], hue: values[2]))
        case .xyz, .xyzD65: linear = DiagramColorSpaces.linearRGB(fromXYZ: values)
        case .xyzD50: linear = DiagramColorSpaces.linearRGB(fromXYZ: DiagramColorSpaces.multiply(DiagramColorSpaces.d50ToD65, values))
        case .hsl: linear = DiagramColorSpaces.encodedRGB(hue: values[0], saturation: values[1], lightness: values[2]).map(DiagramColorSpaces.linear)
        case .hwb: linear = DiagramColorSpaces.encodedRGB(hue: values[0], whiteness: values[1], blackness: values[2]).map(DiagramColorSpaces.linear)
        }
        return DiagramLinearColor(red: linear[0], green: linear[1], blue: linear[2], alpha: alpha)
    }

    /// A gray's hue, which has no say in its color, as missing: the other color's hue is taken in its place.
    private static func withoutPowerlessHue(_ polar: [Double]) -> [Double] {
        polar[1] < 1e-6 ? [polar[0], polar[1], .nan] : polar
    }

    /// HSL's hue, saturation and lightness, or HWB's hue, whiteness and blackness, from encoded sRGB.
    private static func cylindrical(_ encoded: [Double], isWhitenessBlackness: Bool) -> [Double] {
        let largest = encoded.max() ?? 0
        let smallest = encoded.min() ?? 0
        let range = largest - smallest
        var hue = Double.nan
        if range > 1e-9 {
            if largest == encoded[0] {
                hue = (encoded[1] - encoded[2]) / range + (encoded[1] < encoded[2] ? 6 : 0)
            } else if largest == encoded[1] {
                hue = (encoded[2] - encoded[0]) / range + 2
            } else {
                hue = (encoded[0] - encoded[1]) / range + 4
            }
            hue *= 60
        }
        if isWhitenessBlackness { return [hue, smallest, 1 - largest] }
        let lightness = (largest + smallest) / 2
        let saturation = lightness <= 0 || lightness >= 1 ? 0 : (largest - lightness) / min(lightness, 1 - lightness)
        return [saturation == 0 ? .nan : hue, saturation, lightness]
    }

    /// The two hues set to run as `interpolation` says, a missing hue taking the other's (0 when both are missing).
    static func alignHues(_ start: inout DiagramMixingCoordinates, _ end: inout DiagramMixingCoordinates, at index: Int,
                          by interpolation: DiagramHueInterpolation) {
        if start.values[index].isNaN { start.values[index] = end.values[index].isNaN ? 0 : end.values[index] }
        if end.values[index].isNaN { end.values[index] = start.values[index] }
        let difference = end.values[index] - start.values[index]
        switch interpolation {
        case .shorter:
            if difference > 180 { start.values[index] += 360 } else if difference < -180 { end.values[index] += 360 }
        case .longer:
            if difference > 0, difference < 180 { start.values[index] += 360 } else if difference > -180, difference <= 0 { end.values[index] += 360 }
        case .increasing:
            if difference < 0 { end.values[index] += 360 }
        case .decreasing:
            if difference > 0 { start.values[index] += 360 }
        }
    }
}
