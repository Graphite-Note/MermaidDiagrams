/**
 * File: DiagramColorSpaces.swift
 * ------------------------------
 * Layer: Core
 * Description: CSS Color 4's color spaces to and from linear sRGB: sRGB, HSL, HWB, CIE Lab and LCH, Oklab and Oklch,
 *              XYZ and Display P3, with CSS's own matrices.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation

/// A color in linear-light sRGB, its channels unbounded so that a wider gamut's colors keep their place, and its opacity.
struct DiagramLinearColor: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// From sRGB's encoded channels.
    init(encodedRed red: Double, green: Double, blue: Double, alpha: Double) {
        self.init(red: DiagramColorSpaces.linear(red), green: DiagramColorSpaces.linear(green), blue: DiagramColorSpaces.linear(blue), alpha: alpha)
    }

    init(encoded color: DiagramColor) {
        self.init(encodedRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    /// A Core Graphics color's, read in extended sRGB; nil for one with no such form.
    init?(_ color: CGColor) {
        guard let space = CGColorSpace(name: CGColorSpace.extendedSRGB),
              let components = color.converted(to: space, intent: .defaultIntent, options: nil)?.components, components.count == 4 else { return nil }
        self.init(encodedRed: Double(components[0]), green: Double(components[1]), blue: Double(components[2]), alpha: Double(components[3]))
    }

    /// In sRGB, or extended sRGB for a channel past 0…1, as a wide-gamut display shows it.
    var cgColor: CGColor {
        let encoded = [red, green, blue].map(DiagramColorSpaces.encoded)
        let opacity = min(max(alpha, 0), 1)
        guard encoded.contains(where: { channel in channel < 0 || channel > 1 }),
              let space = CGColorSpace(name: CGColorSpace.extendedSRGB),
              let wide = CGColor(colorSpace: space, components: encoded.map { channel in CGFloat(channel) } + [CGFloat(opacity)]) else {
            return CGColor(srgbRed: encoded[0], green: encoded[1], blue: encoded[2], alpha: opacity)
        }
        return wide
    }

    var channels: [Double] { [red, green, blue] }
}

/// Conversions between linear sRGB and the spaces CSS writes colors in and mixes them in.
enum DiagramColorSpaces {
    /// sRGB's transfer function and its inverse, extended to negative values by symmetry, as CSS extends them.
    static func linear(_ encoded: Double) -> Double {
        let magnitude = abs(encoded)
        let value = magnitude <= 0.04045 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4)
        return encoded < 0 ? -value : value
    }

    static func encoded(_ linear: Double) -> Double {
        let magnitude = abs(linear)
        let value = magnitude <= 0.0031308 ? magnitude * 12.92 : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
        return linear < 0 ? -value : value
    }

    /// HSL's encoded sRGB channels, saturation and lightness from 0 to 1.
    static func encodedRGB(hue: Double, saturation: Double, lightness: Double) -> [Double] {
        let sector = ((hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) / 30
        let chroma = saturation * min(lightness, 1 - lightness)
        return [0.0, 8, 4].map { offset in
            let turn = (offset + sector).truncatingRemainder(dividingBy: 12)
            return lightness - chroma * max(-1, min(turn - 3, 9 - turn, 1))
        }
    }

    /// HWB's encoded sRGB channels: a gray when whiteness and blackness add up to 1 or more.
    static func encodedRGB(hue: Double, whiteness: Double, blackness: Double) -> [Double] {
        guard whiteness + blackness < 1 else { return Array(repeating: whiteness / (whiteness + blackness), count: 3) }
        return encodedRGB(hue: hue, saturation: 1, lightness: 0.5).map { channel in channel * (1 - whiteness - blackness) + whiteness }
    }

    /// `lab()`, `lch()`, `oklab()` or `oklch()` from its channels as written.
    static func labFamily(_ name: String, _ channels: [CSSColorComponent], alpha: Double) -> DiagramLinearColor? {
        let isOklab = name.hasPrefix("ok")
        guard let lightness = channels[0].value(percentageOf: isOklab ? 1 : 100) else { return nil }
        let clampedLightness = min(max(lightness, 0), isOklab ? 1 : 100)
        let chromaScale = isOklab ? 0.4 : (name == "lab" ? 125 : 150)
        let coordinates: [Double]
        if name.hasSuffix("lch") {
            guard let chroma = channels[1].value(percentageOf: chromaScale), let hue = channels[2].hue else { return nil }
            coordinates = rectangular(lightness: clampedLightness, chroma: max(chroma, 0), hue: hue)
        } else {
            guard let greenToRed = channels[1].value(percentageOf: chromaScale),
                  let blueToYellow = channels[2].value(percentageOf: chromaScale) else { return nil }
            coordinates = [clampedLightness, greenToRed, blueToYellow]
        }
        let linear = isOklab ? linearRGB(fromOklab: coordinates) : linearRGB(fromXYZ: multiply(d50ToD65, xyzD50(fromLab: coordinates)))
        return DiagramLinearColor(red: linear[0], green: linear[1], blue: linear[2], alpha: alpha)
    }

    /// `color()` in one of the predefined spaces read here: `srgb`, `srgb-linear`, `display-p3`, `xyz`, `xyz-d65`, `xyz-d50`.
    static func predefined(_ space: String, _ channels: [CSSColorComponent], alpha: Double) -> DiagramLinearColor? {
        let values = channels.compactMap { channel in channel.value(percentageOf: 1) }
        guard values.count == 3 else { return nil }
        let linear: [Double]
        switch space {
        case "srgb": linear = values.map(Self.linear)
        case "srgb-linear": linear = values
        case "display-p3": linear = linearRGB(fromXYZ: multiply(displayP3ToXYZ, values.map(Self.linear)))
        case "xyz", "xyz-d65": linear = linearRGB(fromXYZ: values)
        case "xyz-d50": linear = linearRGB(fromXYZ: multiply(d50ToD65, values))
        default: return nil
        }
        return DiagramLinearColor(red: linear[0], green: linear[1], blue: linear[2], alpha: alpha)
    }

    /// Lightness, chroma and a hue in degrees to lightness and the green-to-red and blue-to-yellow axes (Lab's a and b).
    static func rectangular(lightness: Double, chroma: Double, hue: Double) -> [Double] {
        let radians = hue * .pi / 180
        return [lightness, chroma * cos(radians), chroma * sin(radians)]
    }

    /// Lightness and Lab's two axes to lightness, chroma and a hue in degrees from 0 to 360.
    static func polar(_ coordinates: [Double]) -> [Double] {
        let hue = atan2(coordinates[2], coordinates[1]) * 180 / .pi
        return [coordinates[0], (coordinates[1] * coordinates[1] + coordinates[2] * coordinates[2]).squareRoot(), hue < 0 ? hue + 360 : hue]
    }

    static func linearRGB(fromXYZ xyz: [Double]) -> [Double] { multiply(xyzToLinearRGB, xyz) }
    static func xyz(fromLinearRGB linear: [Double]) -> [Double] { multiply(linearRGBToXYZ, linear) }

    static func xyzD50(fromLab lab: [Double]) -> [Double] {
        let first = (lab[0] + 16) / 116
        let components = [lab[1] / 500 + first, first, first - lab[2] / 200]
        let xyz = [
            pow(components[0], 3) > labEpsilon ? pow(components[0], 3) : (116 * components[0] - 16) / labKappa,
            lab[0] > labKappa * labEpsilon ? pow(first, 3) : lab[0] / labKappa,
            pow(components[2], 3) > labEpsilon ? pow(components[2], 3) : (116 * components[2] - 16) / labKappa,
        ]
        return zip(xyz, d50White).map { value, white in value * white }
    }

    static func lab(fromXYZD50 xyz: [Double]) -> [Double] {
        let scaled = zip(xyz, d50White).map { value, white in value / white }
        let components = scaled.map { value in value > labEpsilon ? cbrt(value) : (labKappa * value + 16) / 116 }
        return [116 * components[1] - 16, 500 * (components[0] - components[1]), 200 * (components[1] - components[2])]
    }

    static func linearRGB(fromOklab lab: [Double]) -> [Double] {
        let cone = multiply(oklabToCone, lab).map { value in value * value * value }
        return multiply(coneToLinearRGB, cone)
    }

    static func oklab(fromLinearRGB linear: [Double]) -> [Double] {
        multiply(coneToOklab, multiply(linearRGBToCone, linear).map(cbrt))
    }

    static func multiply(_ matrix: [[Double]], _ vector: [Double]) -> [Double] {
        matrix.map { row in zip(row, vector).reduce(0) { sum, pair in sum + pair.0 * pair.1 } }
    }

    private static let labKappa = 24389.0 / 27
    private static let labEpsilon = 216.0 / 24389
    private static let d50White = [0.3457 / 0.3585, 1, (1 - 0.3457 - 0.3585) / 0.3585]

    static let d50ToD65 = [[0.955473421488075, -0.02309845494876471, 0.06325924320057072],
                           [-0.0283697093338637, 1.0099953980813041, 0.021041441191917323],
                           [0.012314014864481998, -0.020507649298898964, 1.330365926242124]]
    static let d65ToD50 = [[1.0479297925449969, 0.022946870601609652, -0.05019226628920524],
                           [0.02962780877005599, 0.9904344267538799, -0.017073799063418826],
                           [-0.009243040646204504, 0.015055191490298152, 0.7518742814281371]]
    private static let xyzToLinearRGB = [[3.2409699419045226, -1.537383177570094, -0.4986107602930034],
                                         [-0.9692436362808796, 1.8759675015077202, 0.04155505740717559],
                                         [0.05563007969699366, -0.20397695888897652, 1.0569715142428786]]
    private static let linearRGBToXYZ = [[0.41239079926595934, 0.357584339383878, 0.1804807884018343],
                                         [0.21263900587151027, 0.715168678767756, 0.07219231536073371],
                                         [0.01933081871559182, 0.11919477979462598, 0.9505321522496607]]
    static let displayP3ToXYZ = [[0.4865709486482162, 0.26566769316909306, 0.1982172852343625],
                                 [0.2289745640697488, 0.6917385218365064, 0.079286914093745],
                                 [0, 0.04511338185890264, 1.043944368900976]]
    static let xyzToDisplayP3 = [[2.493496911941425, -0.9313836179191239, -0.40271078445071684],
                                 [-0.8294889695615747, 1.7626640603183463, 0.023624685841943577],
                                 [0.03584583024378447, -0.07617238926804182, 0.9568845240076872]]
    private static let oklabToCone = [[1, 0.3963377774, 0.2158037573], [1, -0.1055613458, -0.0638541728], [1, -0.0894841775, -1.2914855480]]
    private static let coneToLinearRGB = [[4.0767416621, -3.3077115913, 0.2309699292], [-1.2684380046, 2.6097574011, -0.3413193965],
                                          [-0.0041960863, -0.7034186147, 1.7076147010]]
    private static let linearRGBToCone = [[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566],
                                          [0.0883024619, 0.2817188376, 0.6299787005]]
    private static let coneToOklab = [[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099],
                                      [0.0259040371, 0.7827717662, -0.8086757660]]
}
