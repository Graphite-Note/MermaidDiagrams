/**
 * File: DiagramPath.swift
 * -----------------------
 * Layer: Core
 * Description: A line through a diagram, straight and cubic segments from a start point, moved as a whole
 *              or where it stands.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 26/11/2026
 */

import CoreGraphics

/// A line through a diagram, made of straight and cubic segments from a start point.
public struct DiagramPath: Equatable, Sendable {
    public internal(set) var start: CGPoint
    public internal(set) var segments: [DiagramPathSegment]
}

public enum DiagramPathSegment: Equatable, Sendable, BitwiseCopyable {
    case line(to: CGPoint)
    case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
}

extension DiagramPath {
    func translated(by offset: CGVector) -> DiagramPath {
        DiagramPath(start: start.translated(by: offset), segments: segments.map { segment in
            switch segment {
            case .line(let end): .line(to: end.translated(by: offset))
            case .curve(let end, let firstControl, let secondControl):
                .curve(to: end.translated(by: offset), control1: firstControl.translated(by: offset), control2: secondControl.translated(by: offset))
            }
        })
    }
}

extension DiagramPath {
    /// Moved by `offset` where it stands, each point as `translated(by:)` moves it, in the path's own list.
    mutating func translate(by offset: CGVector) {
        start = start.translated(by: offset)
        for index in segments.indices {
            switch segments[index] {
            case .line(let end): segments[index] = .line(to: end.translated(by: offset))
            case .curve(let end, let firstControl, let secondControl):
                segments[index] = .curve(to: end.translated(by: offset), control1: firstControl.translated(by: offset),
                                         control2: secondControl.translated(by: offset))
            }
        }
    }
}

extension CGPoint {
    func translated(by offset: CGVector) -> CGPoint {
        CGPoint(x: x + offset.dx, y: y + offset.dy)
    }
}
