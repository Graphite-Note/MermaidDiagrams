/**
 * File: DiagramGlyphPath.swift
 * ----------------------------
 * Layer: Core
 * Description: Reads the SVG path data of a glyph drawn on a square grid, Pele's 24 by 24 icons, into a Core Graphics
 *              path, and places it in a frame.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

import CoreGraphics

/// A glyph's outline, read from SVG path data on a square grid (Pele's icons are drawn on 24 by 24), as SVG reads it:
/// every command (`M`, `L`, `H`, `V`, `C`, `S`, `Q`, `T`, `A`, `Z`), absolute in capitals and relative in lower case, a
/// command's arguments repeated without the letter, numbers written without separators where SVG allows (`1.5.5`, `2-1`)
/// and an arc's flags as single digits. Data SVG would refuse is refused (nil), so that a glyph is drawn whole or not at all.
struct DiagramGlyphPath {
    /// The outline in the grid's units, its origin at the grid's top left and its y running down.
    let gridPath: DiagramScenePath
    /// The side of the square the data is drawn on.
    let gridSide: CGFloat

    /// Pele's icons are drawn on a 24 by 24 grid (`viewBox="0 0 24 24"`).
    static let standardGridSide: CGFloat = 24
    /// The most numbers one glyph's data may hold: a glyph is a few dozen commands, and data longer than this is not one.
    static let maximumNumberCount = 4_096

    init?(pathData: String, gridSide: CGFloat = standardGridSide) {
        var reader = DiagramGlyphPathReader(bytes: Array(pathData.utf8))
        guard let path = reader.read(), gridSide > 0 else { return nil }
        gridPath = path
        self.gridSide = gridSide
    }

    /// The outline scaled from its grid to `frame`'s square, whose side is the frame's smaller side, centered in it.
    func path(in frame: CGRect) -> DiagramScenePath {
        let side = min(frame.width, frame.height)
        let scale = side / gridSide
        let transform = CGAffineTransform(translationX: frame.midX - side / 2, y: frame.midY - side / 2).scaledBy(x: scale, y: scale)
        return gridPath.applying(transform)
    }
}

/// Reads path data command by command, keeping the current point, the subpath's start and the last control point that a
/// smooth curve (`S`, `T`) reflects.
private struct DiagramGlyphPathReader {
    private var numbers: DiagramGlyphPathNumbers
    private var path = DiagramScenePath()
    private var current = CGPoint.zero
    private var subpathStart = CGPoint.zero
    /// The second control point of the last cubic curve, or the control point of the last quadratic one, with which
    /// command it came, for the reflection of the next smooth curve.
    private var lastControl: (point: CGPoint, wasCubic: Bool)?

    init(bytes: [UInt8]) {
        numbers = DiagramGlyphPathNumbers(bytes: bytes)
    }

    mutating func read() -> DiagramScenePath? {
        var command: UInt8?
        while true {
            numbers.skipSeparators()
            if let letter = numbers.readCommandLetter() {
                command = letter
            } else if numbers.isAtEnd {
                return path.isEmpty ? nil : path
            } else if command == nil || command == UInt8(ascii: "z") || command == UInt8(ascii: "Z") {
                return nil
            }
            guard let written = command, numbers.readCount <= DiagramGlyphPath.maximumNumberCount, apply(written) else { return nil }
            // After a move, further pairs of the same command are lines.
            if written == UInt8(ascii: "M") { command = UInt8(ascii: "L") }
            if written == UInt8(ascii: "m") { command = UInt8(ascii: "l") }
        }
    }

    /// Applies one command with its arguments; false when they are missing or the path has not started.
    private mutating func apply(_ command: UInt8) -> Bool {
        let isRelative = command >= UInt8(ascii: "a")
        let origin = isRelative ? current : .zero
        switch MermaidByte.lowercased(command) {
        case UInt8(ascii: "m"):
            guard let point = readPoint(from: origin) else { return false }
            path.move(to: point)
            current = point
            subpathStart = point
            lastControl = nil
            return true
        case UInt8(ascii: "z"):
            guard !path.isEmpty else { return false }
            path.closeSubpath()
            current = subpathStart
            lastControl = nil
            return true
        default:
            guard !path.isEmpty else { return false }
            return applyDrawing(MermaidByte.lowercased(command), origin: origin, isRelative: isRelative)
        }
    }

    private mutating func applyDrawing(_ command: UInt8, origin: CGPoint, isRelative: Bool) -> Bool {
        switch command {
        case UInt8(ascii: "l"):
            guard let point = readPoint(from: origin) else { return false }
            line(to: point)
        case UInt8(ascii: "h"):
            guard let across = numbers.readNumber() else { return false }
            line(to: CGPoint(x: (isRelative ? current.x : 0) + across, y: current.y))
        case UInt8(ascii: "v"):
            guard let down = numbers.readNumber() else { return false }
            line(to: CGPoint(x: current.x, y: (isRelative ? current.y : 0) + down))
        case UInt8(ascii: "c"), UInt8(ascii: "s"):
            let reflected = lastControl?.wasCubic == true ? reflection(of: lastControl?.point) : current
            let first = command == UInt8(ascii: "c") ? readPoint(from: origin) : reflected
            guard let first, let second = readPoint(from: origin), let end = readPoint(from: origin) else { return false }
            path.addCurve(to: end, control1: first, control2: second)
            current = end
            lastControl = (second, true)
        case UInt8(ascii: "q"), UInt8(ascii: "t"):
            let reflected = lastControl?.wasCubic == false ? reflection(of: lastControl?.point) : current
            let control = command == UInt8(ascii: "q") ? readPoint(from: origin) : reflected
            guard let control, let end = readPoint(from: origin) else { return false }
            path.addQuadCurve(to: end, control: control)
            current = end
            lastControl = (control, false)
        case UInt8(ascii: "a"):
            guard let radiusAcross = numbers.readNumber(), let radiusDown = numbers.readNumber(), let rotation = numbers.readNumber(),
                  let isLarge = numbers.readFlag(), let sweepsPositively = numbers.readFlag(), let end = readPoint(from: origin) else { return false }
            DiagramGlyphArc(start: current, end: end, radii: CGSize(width: radiusAcross, height: radiusDown), rotationDegrees: rotation,
                            isLarge: isLarge, sweepsPositively: sweepsPositively).add(to: &path)
            current = end
            lastControl = nil
        default:
            return false
        }
        return true
    }

    private mutating func line(to point: CGPoint) {
        path.addLine(to: point)
        current = point
        lastControl = nil
    }

    private mutating func readPoint(from origin: CGPoint) -> CGPoint? {
        guard let across = numbers.readNumber(), let down = numbers.readNumber() else { return nil }
        return CGPoint(x: origin.x + across, y: origin.y + down)
    }

    /// `point` reflected through the current point, or the current point when there is none.
    private func reflection(of point: CGPoint?) -> CGPoint {
        guard let point else { return current }
        return CGPoint(x: 2 * current.x - point.x, y: 2 * current.y - point.y)
    }
}
