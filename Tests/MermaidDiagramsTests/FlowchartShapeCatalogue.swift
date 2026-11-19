/**
 * File: FlowchartShapeCatalogue.swift
 * -----------------------------------
 * Layer: Tests
 * Description: The flowchart node shapes grouped as the tests take them: Mermaid's classic ones and the others.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

@testable import MermaidDiagrams

/// The flowchart node shapes as the tests group them.
enum FlowchartShapeCatalogue {
    /// Mermaid's classic shapes, written in brackets: the cases before the ellipse.
    static let classicShapes = Array(FlowchartNodeShape.allCases.prefix { shape in shape != .ellipse })
    /// The shapes beyond them, from Pele's catalogue.
    static let extendedShapes = Array(FlowchartNodeShape.allCases.drop { shape in shape != .ellipse })
}
