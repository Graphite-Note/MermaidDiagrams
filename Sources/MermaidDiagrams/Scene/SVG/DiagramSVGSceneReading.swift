/**
 * File: DiagramSVGSceneReading.swift
 * ----------------------------------
 * Layer: Core
 * Description: How the SVG writer reads a scene as it is stored today, items of Core Graphics paths: whether it has
 *              gradient fills, the gradients' definitions, and each item's element, a path's data read from its
 *              CGPath; the one place that changes when the scene's storage does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramSVGBody {
    /// Whether any shape of `items` is filled with a gradient, which needs `<defs>`.
    static func hasGradientFills(_ items: [DiagramSceneItem]) -> Bool {
        for item in items {
            if case .shape(let shape) = item, case .gradientFill = shape.painting { return true }
        }
        return false
    }

    /// `<defs>` with a definition of each gradient fill of `items`, numbered in their order as `add(_:)` numbers their
    /// uses, or nothing when no item has one: written before the items, where the document has them, so that nothing is
    /// put in before the body afterwards.
    mutating func appendDefinitions(of items: [DiagramSceneItem]) {
        var definitionCount = 0
        for item in items {
            guard case .shape(let shape) = item, case .gradientFill(let gradient) = shape.painting else { continue }
            if definitionCount == 0 { appendDefinitionsOpening() }
            definitionCount += 1
            appendGradientDefinition(gradient, number: definitionCount)
        }
        if definitionCount > 0 { appendDefinitionsClosing() }
    }

    mutating func add(_ item: DiagramSceneItem) {
        switch item {
        case .shape(let shape):
            appendShapeOpening(part: shape.part)
            content.appendPathData(shape.path)
            appendShapeClosing(painting: shape.painting)
        case .text(let text):
            add(text)
        }
    }

    /// Every item, back to front.
    mutating func addItems(of items: [DiagramSceneItem]) {
        for item in items { add(item) }
    }
}
