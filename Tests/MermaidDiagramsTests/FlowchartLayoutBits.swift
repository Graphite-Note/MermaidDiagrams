/**
 * File: FlowchartLayoutBits.swift
 * -------------------------------
 * Layer: Tests
 * Description: Every number, text and choice of a flowchart's layout as bit patterns, so that two layouts compare to
 *              the bit (-0 and 0 differ, NaN equals NaN) and an error compares by what it says.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A flowchart's layout, or the error laying it out threw, as bit patterns and descriptions.
struct FlowchartLayoutBits: Equatable {
    var bits: [UInt64] = []
    var descriptions: [String] = []
    var error: String?

    init(laying: () throws -> FlowchartLayout) {
        do {
            add(try laying())
        } catch {
            self.error = String(describing: error)
        }
    }

    private mutating func add(_ layout: FlowchartLayout) {
        add(layout.size.width)
        add(layout.size.height)
        descriptions.append(String(describing: layout.font))
        bits.append(UInt64(layout.nodes.count))
        for node in layout.nodes {
            descriptions.append(String(describing: node.shape))
            add(node.frame)
            add(node.text)
            descriptions.append(String(describing: node.style))
            descriptions.append(String(describing: node.asset))
        }
        bits.append(UInt64(layout.edges.count))
        for edge in layout.edges {
            descriptions.append(String(describing: edge.stroke))
            add(edge.path)
            add(edge.sourceMark)
            add(edge.targetMark)
            add(edge.text)
            descriptions.append(String(describing: edge.style))
        }
        add(layout.title)
        bits.append(UInt64(layout.clusters.count))
        for cluster in layout.clusters {
            add(cluster.frame)
            add(cluster.title)
            bits += [UInt64(cluster.depth), cluster.isTitleCrossed ? 1 : 0]
        }
    }

    mutating func add(_ value: CGFloat) { bits.append(Double(value).bitPattern) }

    mutating func add(_ point: CGPoint) {
        add(point.x)
        add(point.y)
    }

    mutating func add(_ rect: CGRect) {
        add(rect.origin)
        add(rect.size.width)
        add(rect.size.height)
    }

    mutating func add(_ path: DiagramPath) {
        add(path.start)
        bits.append(UInt64(path.segments.count))
        for segment in path.segments {
            switch segment {
            case .line(let end):
                bits.append(0)
                add(end)
            case .curve(let end, let firstControl, let secondControl):
                bits.append(1)
                add(end)
                add(firstControl)
                add(secondControl)
            }
        }
    }

    mutating func add(_ mark: DiagramEdgeMark?) {
        guard let mark else { return bits.append(UInt64.max) }
        descriptions.append(String(describing: mark.arrowhead))
        add(mark.tip)
        add(mark.direction.dx)
        add(mark.direction.dy)
    }

    /// A text's size, line height, center, and each line's width and bytes.
    mutating func add(_ text: DiagramTextBlock?) {
        guard let text else { return bits.append(UInt64.max) }
        add(text.fontSize)
        add(text.lineHeight)
        add(text.center)
        add(text.size.width)
        add(text.size.height)
        bits.append(UInt64(text.lineCount))
        for line in 0..<text.lineCount {
            add(text.lineWidth(at: line))
            descriptions.append(text.withUTF8(ofLine: line) { bytes in String(decoding: bytes, as: UTF8.self) })
        }
        descriptions.append(String(describing: text.lineRuns))
    }
}
