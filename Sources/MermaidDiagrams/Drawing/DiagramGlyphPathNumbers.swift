/**
 * File: DiagramGlyphPathNumbers.swift
 * -----------------------------------
 * Layer: Core
 * Description: The numbers, flags and command letters of SVG path data, read as SVG reads them, and an arc of an ellipse
 *              from its end points turned into cubic curves.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation

/// Reads SVG path data's tokens: a command letter, or a number (`-1.5`, `.5`, `2e-3`) after optional spaces, tabs, line
/// breaks and one comma. A number ends where the next cannot continue it, so `1.5.5` is two numbers and `2-1` too.
struct DiagramGlyphPathNumbers {
    private let bytes: [UInt8]
    private var position = 0
    /// How many numbers and flags were read, which a glyph bounds.
    private(set) var readCount = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { position >= bytes.count }

    mutating func skipSeparators() {
        while position < bytes.count, MermaidByte.isWhitespace(bytes[position]) || bytes[position] == MermaidByte.comma { position += 1 }
    }

    /// The command letter at the cursor, after separators, or nil when a number or the end comes first.
    mutating func readCommandLetter() -> UInt8? {
        skipSeparators()
        guard position < bytes.count, Self.commandLetters.contains(bytes[position]) else { return nil }
        position += 1
        return bytes[position - 1]
    }

    mutating func readNumber() -> CGFloat? {
        skipSeparators()
        let start = position
        if position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == MermaidByte.hyphen { position += 1 }
        let integerDigits = skipDigits()
        var fractionDigits = 0
        if position < bytes.count, bytes[position] == MermaidByte.period {
            position += 1
            fractionDigits = skipDigits()
        }
        guard integerDigits + fractionDigits > 0 else {
            position = start
            return nil
        }
        if position < bytes.count, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") {
            let exponentStart = position
            position += 1
            if position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == MermaidByte.hyphen { position += 1 }
            if skipDigits() == 0 { position = exponentStart }
        }
        guard let number = Double(String(decoding: bytes[start..<position], as: UTF8.self)), number.isFinite else { return nil }
        readCount += 1
        return CGFloat(number)
    }

    /// An arc's flag: one `0` or `1`, which needs no separator after it.
    mutating func readFlag() -> Bool? {
        skipSeparators()
        guard position < bytes.count, bytes[position] == UInt8(ascii: "0") || bytes[position] == UInt8(ascii: "1") else { return nil }
        position += 1
        readCount += 1
        return bytes[position - 1] == UInt8(ascii: "1")
    }

    private mutating func skipDigits() -> Int {
        let start = position
        while position < bytes.count, MermaidByte.isDigit(bytes[position]) { position += 1 }
        return position - start
    }

    private static let commandLetters = Set("MmLlHhVvCcSsQqTtAaZz".utf8)
}

/// An arc of an ellipse as SVG writes one, from the current point to `end`, with its radii, the turn of its axes, and
/// which of the four arcs between the points it is: the large or the small one, swept with increasing angle on a page
/// whose y runs down or against it. Radii too small to reach are scaled up until they do, and a zero radius is a line.
struct DiagramGlyphArc {
    let start: CGPoint
    let end: CGPoint
    let radii: CGSize
    let rotationDegrees: CGFloat
    let isLarge: Bool
    let sweepsPositively: Bool

    /// Adds the arc to `path`, whose current point is `start`, as cubic curves of at most a quarter turn each.
    func add(to path: CGMutablePath) {
        var radiusAcross = abs(radii.width)
        var radiusDown = abs(radii.height)
        guard radiusAcross > 0, radiusDown > 0, start != end else {
            path.addLine(to: end)
            return
        }
        let angle = rotationDegrees * .pi / 180
        let cosine = cos(angle)
        let sine = sin(angle)
        let halfAcross = (start.x - end.x) / 2
        let halfDown = (start.y - end.y) / 2
        // The start in the ellipse's own axes, centered between the points.
        let turnedAcross = cosine * halfAcross + sine * halfDown
        let turnedDown = -sine * halfAcross + cosine * halfDown
        let reach = turnedAcross * turnedAcross / (radiusAcross * radiusAcross) + turnedDown * turnedDown / (radiusDown * radiusDown)
        if reach > 1 {
            radiusAcross *= reach.squareRoot()
            radiusDown *= reach.squareRoot()
        }
        let numerator = radiusAcross * radiusAcross * radiusDown * radiusDown - radiusAcross * radiusAcross * turnedDown * turnedDown
            - radiusDown * radiusDown * turnedAcross * turnedAcross
        let denominator = radiusAcross * radiusAcross * turnedDown * turnedDown + radiusDown * radiusDown * turnedAcross * turnedAcross
        let scale = (isLarge == sweepsPositively ? -1 : 1) * (max(0, numerator) / denominator).squareRoot()
        let centerAcross = scale * radiusAcross * turnedDown / radiusDown
        let centerDown = -scale * radiusDown * turnedAcross / radiusAcross
        let center = CGPoint(x: cosine * centerAcross - sine * centerDown + (start.x + end.x) / 2,
                             y: sine * centerAcross + cosine * centerDown + (start.y + end.y) / 2)
        let startAngle = atan2((turnedDown - centerDown) / radiusDown, (turnedAcross - centerAcross) / radiusAcross)
        var sweep = atan2((-turnedDown - centerDown) / radiusDown, (-turnedAcross - centerAcross) / radiusAcross) - startAngle
        if sweepsPositively, sweep < 0 { sweep += 2 * .pi }
        if !sweepsPositively, sweep > 0 { sweep -= 2 * .pi }
        addCurves(to: path, center: center, radii: CGSize(width: radiusAcross, height: radiusDown), axisTurn: (cosine, sine),
                  startAngle: startAngle, sweep: sweep)
    }

    private func addCurves(to path: CGMutablePath, center: CGPoint, radii: CGSize, axisTurn: (cosine: CGFloat, sine: CGFloat),
                           startAngle: CGFloat, sweep: CGFloat) {
        let curveCount = max(1, Int((abs(sweep) / (.pi / 2)).rounded(.up)))
        let curveSweep = sweep / CGFloat(curveCount)
        let controlDistance = 4 / 3 * tan(curveSweep / 4)
        func turned(_ across: CGFloat, _ down: CGFloat) -> CGVector {
            CGVector(dx: axisTurn.cosine * across - axisTurn.sine * down, dy: axisTurn.sine * across + axisTurn.cosine * down)
        }
        func point(at angle: CGFloat) -> CGPoint {
            let offset = turned(radii.width * cos(angle), radii.height * sin(angle))
            return CGPoint(x: center.x + offset.dx, y: center.y + offset.dy)
        }
        func tangent(at angle: CGFloat) -> CGVector { turned(-radii.width * sin(angle), radii.height * cos(angle)) }
        var angle = startAngle
        for index in 0..<curveCount {
            let nextAngle = angle + curveSweep
            let from = point(at: angle)
            let to = index == curveCount - 1 ? end : point(at: nextAngle)
            let leaving = tangent(at: angle)
            let arriving = tangent(at: nextAngle)
            path.addCurve(to: to, control1: CGPoint(x: from.x + leaving.dx * controlDistance, y: from.y + leaving.dy * controlDistance),
                          control2: CGPoint(x: to.x - arriving.dx * controlDistance, y: to.y - arriving.dy * controlDistance))
            angle = nextAngle
        }
    }
}
