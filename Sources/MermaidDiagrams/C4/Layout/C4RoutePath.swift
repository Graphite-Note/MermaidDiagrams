/**
 * File: C4RoutePath.swift
 * -----------------------
 * Layer: Core
 * Description: A C4 relation's line as the router makes it, kept in place rather than in a list: its start and up to
 *              five segments (a straight line, a loop's curve, or two corners each rounded between three stretches).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics

/// A route's line: its start and its segments in the order drawn, at most `capacity`, with no allocation.
struct C4RoutePath {
    static let capacity = 5

    var start: CGPoint
    private(set) var count = 0
    private var storage: (DiagramPathSegment, DiagramPathSegment, DiagramPathSegment, DiagramPathSegment, DiagramPathSegment)

    init(start: CGPoint) {
        self.start = start
        let none = DiagramPathSegment.line(to: .zero)
        storage = (none, none, none, none, none)
    }

    init(start: CGPoint, _ segment: DiagramPathSegment) {
        self.init(start: start)
        append(segment)
    }

    subscript(index: Int) -> DiagramPathSegment {
        precondition(index >= 0 && index < count, "Index out of range of the route's segments")
        return withUnsafeBytes(of: storage) { bytes in
            bytes.baseAddress!.assumingMemoryBound(to: DiagramPathSegment.self)[index]
        }
    }

    mutating func append(_ segment: DiagramPathSegment) {
        precondition(count < Self.capacity, "A route has five segments at most")
        let index = count
        withUnsafeMutableBytes(of: &storage) { bytes in bytes.baseAddress!.assumingMemoryBound(to: DiagramPathSegment.self)[index] = segment }
        count += 1
    }

    /// Segment `index` moved by `offset`, each point as `DiagramPath.translated(by:)` moves it.
    func segment(at index: Int, translatedBy offset: CGVector) -> DiagramPathSegment {
        switch self[index] {
        case .line(let end): .line(to: end.translated(by: offset))
        case .curve(let end, let firstControl, let secondControl):
            .curve(to: end.translated(by: offset), control1: firstControl.translated(by: offset), control2: secondControl.translated(by: offset))
        }
    }

    /// The line as a path, made when asked.
    var diagramPath: DiagramPath {
        DiagramPath(start: start, segments: (0..<count).map { index in self[index] })
    }
}
