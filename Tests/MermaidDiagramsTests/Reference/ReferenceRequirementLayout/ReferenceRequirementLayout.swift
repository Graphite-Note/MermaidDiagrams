/**
 * File: ReferenceRequirementLayout.swift
 * --------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 shape of a requirement diagram's layout, its boxes, relations and title as blocks, which the
 *              frozen reference engine gives, and the views of a layout the equivalence tests compare.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// A requirement diagram laid out as 0.7.0's `RequirementLayout` kept it: every text a block.
struct ReferenceRequirementLayout: Equatable {
    let size: CGSize
    let font: DiagramFont
    let boxes: [RequirementLayoutBox]
    let relations: [RequirementLayoutRelation]
    let title: DiagramTextBlock?
}

/// What a requirement layout shows a host: 0.8.0's `RequirementLayout` and the reference's alike.
protocol RequirementLayoutViews {
    var size: CGSize { get }
    var font: DiagramFont { get }
    var boxes: [RequirementLayoutBox] { get }
    var relations: [RequirementLayoutRelation] { get }
    var title: DiagramTextBlock? { get }
}

extension RequirementLayout: RequirementLayoutViews {}
extension ReferenceRequirementLayout: RequirementLayoutViews {}
