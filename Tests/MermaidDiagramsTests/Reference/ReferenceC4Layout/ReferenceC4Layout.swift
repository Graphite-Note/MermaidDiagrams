/**
 * File: ReferenceC4Layout.swift
 * -----------------------------
 * Layer: Tests
 * Description: The 0.7.0 (de81532) C4 layout kept as the reference the flat C4 layout is checked against. A C4 diagram
 *              laid out on a page whose y runs down: its boundaries with their headings, its shapes with their texts,
 *              its relations' lines, arrowheads and labels, and the colors its styles set.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A C4 diagram laid out on a page whose origin is the top left corner and whose y runs down, in points, as Pele lays
/// it out on Mermaid's grid.
struct ReferenceC4Layout: Equatable {
    let size: CGSize
    /// The font names, headings and the title were measured in (bold); the rest is at thirteen sixteenths of its size, a
    /// shape's kind a point smaller.
    let font: DiagramFont
    let title: DiagramTextBlock?
    /// The boundaries drawn, parents before children; the unnamed top level is not one of them.
    let boundaries: [C4LayoutBoundary]
    /// The shapes, boundary by boundary in that order.
    let shapes: [C4LayoutShape]
    /// The relations in the order written.
    let relations: [C4LayoutRelation]
}
