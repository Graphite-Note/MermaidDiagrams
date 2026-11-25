/**
 * File: C4RouteBox.swift
 * ----------------------
 * Layer: Core
 * Description: A laid-out C4 shape or boundary as the relations' routing sees it, and where a line from outside first
 *              meets its outline: a box, a person's head over its body, a cylinder's caps, a queue's ends.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

import CoreGraphics

/// The shape a C4 shape is drawn as: Pele's shared `rect`, `person`, `cyl` and `h-cyl`.
public enum C4ShapeForm: String, Sendable {
    case rectangle = "rect"
    case person
    case cylinder = "cyl"
    case horizontalCylinder = "h-cyl"

    /// The words Mermaid takes in `$shape`, `$sprite` or `$tags` for a form, in any case.
    static let namedForms: [String: C4ShapeForm] = [
        "person": .person, "box": .rectangle, "rounded": .rectangle, "component": .rectangle, "cylinder": .cylinder, "database": .cylinder,
        "db": .cylinder, "queue": .horizontalCylinder, "pipe": .horizontalCylinder,
    ]

    /// The form of a shape: its `$shape`, else its `$sprite`, else the first of its tags that names one, else its kind's.
    /// A field is made a String only when it is written.
    static func form(of shape: C4ShapeRecord, in diagram: C4Diagram) -> C4ShapeForm {
        let element = shape.element
        if !element.shape.isNoneOrEmpty, let named = namedForms[diagram.text(element.shape).lowercased()] { return named }
        if !element.sprite.isNoneOrEmpty, let named = namedForms[diagram.text(element.sprite).lowercased()] { return named }
        if !element.tags.isNoneOrEmpty {
            for tag in diagram.text(element.tags).split(separator: ",", omittingEmptySubsequences: false) {
                if let named = namedForms[C4Characters.trimmed(String(tag)).lowercased()] { return named }
            }
        }
        let kind = shape.kind.rawValue
        return kind.hasSuffix("person") ? .person : kind.hasSuffix("_db") ? .cylinder : kind.hasSuffix("_queue") ? .horizontalCylinder : .rectangle
    }
}

/// A laid-out shape or boundary: its top left corner, its size, and the form it is drawn as (a boundary's a rectangle).
struct C4RouteBox: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var form: C4ShapeForm

    var centerX: CGFloat { x + width / 2 }
    var centerY: CGFloat { y + height / 2 }
    var right: CGFloat { x + width }
    var bottom: CGFloat { y + height }

    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// Whether `inner` lies within it, edges included.
    func contains(_ inner: C4RouteBox) -> Bool {
        x <= inner.x && y <= inner.y && right >= inner.right && bottom >= inner.bottom
    }

    /// How far along the segment from (startX, startY) to (endX, endY) it first meets the outline, as a fraction of the
    /// segment; infinite when it misses.
    func hit(fromX startX: CGFloat, y startY: CGFloat, toX endX: CGFloat, y endY: CGFloat) -> CGFloat {
        let deltaX = endX - startX
        let deltaY = endY - startY
        func rectangle(_ left: CGFloat, _ top: CGFloat, _ right: CGFloat, _ bottom: CGFloat) -> CGFloat {
            C4RouteGeometry.hitRectangle(left: left, top: top, right: right, bottom: bottom, x: startX, y: startY, deltaX: deltaX, deltaY: deltaY)
        }
        func ellipse(_ centerX: CGFloat, _ centerY: CGFloat, _ radiusX: CGFloat, _ radiusY: CGFloat) -> CGFloat {
            C4RouteGeometry.hitEllipse(centerX: centerX, centerY: centerY, radiusX: radiusX, radiusY: radiusY, x: startX, y: startY,
                                       deltaX: deltaX, deltaY: deltaY)
        }
        switch form {
        case .person:
            return min(rectangle(x, y + C4Metrics.personHead, right, bottom), ellipse(centerX, y + 14, 13, 13))
        case .cylinder:
            let capDepth = C4Metrics.cylinderCapDepth(width: width)
            return min(rectangle(x, y + capDepth, right, bottom - capDepth), ellipse(centerX, y + capDepth, width / 2, capDepth),
                       ellipse(centerX, bottom - capDepth, width / 2, capDepth))
        case .horizontalCylinder:
            let capDepth = C4Metrics.queueCapDepth(height: height)
            return min(rectangle(x + capDepth, y, right - capDepth, bottom), ellipse(x + capDepth, centerY, capDepth, height / 2),
                       ellipse(right - capDepth, centerY, capDepth, height / 2))
        case .rectangle:
            return rectangle(x, y, right, bottom)
        }
    }
}

/// The segment and outline tests of Pele's `route.ts`.
enum C4RouteGeometry {
    /// How far along the segment from (x, y) by (deltaX, deltaY) it first meets the rectangle; infinite when it misses.
    static func hitRectangle(left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat, x: CGFloat, y: CGFloat, deltaX: CGFloat,
                             deltaY: CGFloat) -> CGFloat {
        var enter: CGFloat = 0
        var leave: CGFloat = 1
        if deltaX == 0 {
            if x < left || x > right { return .infinity }
        } else {
            let first = (left - x) / deltaX
            let second = (right - x) / deltaX
            enter = max(enter, min(first, second))
            leave = min(leave, max(first, second))
        }
        if deltaY == 0 {
            if y < top || y > bottom { return .infinity }
        } else {
            let first = (top - y) / deltaY
            let second = (bottom - y) / deltaY
            enter = max(enter, min(first, second))
            leave = min(leave, max(first, second))
        }
        return enter <= leave ? enter : .infinity
    }

    static func hitEllipse(centerX: CGFloat, centerY: CGFloat, radiusX: CGFloat, radiusY: CGFloat, x: CGFloat, y: CGFloat, deltaX: CGFloat,
                           deltaY: CGFloat) -> CGFloat {
        let directionX = deltaX / radiusX
        let directionY = deltaY / radiusY
        let offsetX = (x - centerX) / radiusX
        let offsetY = (y - centerY) / radiusY
        let quadratic = directionX * directionX + directionY * directionY
        let linear = 2 * (directionX * offsetX + directionY * offsetY)
        let constant = offsetX * offsetX + offsetY * offsetY - 1
        let discriminant = linear * linear - 4 * quadratic * constant
        if quadratic == 0 || discriminant < 0 { return .infinity }
        let entry = (-linear - discriminant.squareRoot()) / (2 * quadratic)
        return entry >= 0 && entry <= 1 ? entry : constant <= 0 ? 0 : .infinity
    }

    /// Whether the line through `points` (x, y pairs) crosses the rectangle.
    static func crosses<Points: RandomAccessCollection<CGFloat>>(_ points: Points, left: CGFloat, top: CGFloat, right: CGFloat,
                                                                 bottom: CGFloat) -> Bool where Points.Index == Int {
        var index = 2
        while index < points.count {
            let startX = points[index - 2]
            let startY = points[index - 1]
            if hitRectangle(left: left, top: top, right: right, bottom: bottom, x: startX, y: startY, deltaX: points[index] - startX,
                            deltaY: points[index + 1] - startY) <= 1 { return true }
            index += 2
        }
        return false
    }
}
