/**
 * File: ReferenceC4Diagram.swift
 * ------------------------------
 * Layer: Tests
 * Description: The 0.7.0 C4Diagram kept as the reference the flat C4 reader is checked against: its shapes, boundaries
 *              and relations stored as value types with Strings, the named-argument fields' setters as 0.7.0 applied
 *              them, and the reading of a whole text as 0.7.0's reader read a C4 diagram.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

@testable import MermaidDiagrams

/// A C4 diagram as 0.7.0 held it once read.
struct ReferenceC4Diagram: Equatable {
    var level: C4DiagramLevel
    var title: String?
    var accessibilityDescription: String?
    var shapes: [C4Shape]
    var boundaries: [C4Boundary]
    var relations: [C4Relation]
    var shapesPerRow: Int
    var boundariesPerRow: Int

    init(level: C4DiagramLevel = .context) {
        self.level = level
        shapes = []
        boundaries = [C4Boundary(element: C4Element(alias: "global", label: "global", type: "global"), deploymentNode: nil)]
        relations = []
        shapesPerRow = 4
        boundariesPerRow = 2
    }

    /// Whether `diagram` holds what this one holds, field by field.
    func matches(_ diagram: C4Diagram) -> Bool {
        level == diagram.level && title == diagram.title && accessibilityDescription == diagram.accessibilityDescription && shapes == diagram.shapes
            && boundaries == diagram.boundaries && relations == diagram.relations && shapesPerRow == diagram.shapesPerRow
            && boundariesPerRow == diagram.boundariesPerRow
    }
}

extension C4Element {
    /// Sets the field a named argument names (`$descr`, `$bgColor`), or keeps it among the other arguments.
    mutating func referenceApply(_ argument: C4NamedArgument) {
        let value = argument.value
        switch argument.key {
        case "label": label = value
        case "type": type = value
        case "descr": description = value
        case "techn": technology = value
        case "sprite": sprite = value
        case "tags": tags = value
        case "link": link = value
        case "bgColor": backgroundColor = value
        case "fontColor": fontColor = value
        case "borderColor": borderColor = value
        case "shadowing": shadowing = value
        case "shape": shape = value
        case "legendText": legendText = value
        case "legendSprite": legendSprite = value
        default: otherArguments.set(argument)
        }
    }
}

extension C4Relation {
    /// Sets the field a named argument names, the offsets read as numbers, or keeps it among the other arguments.
    mutating func referenceApply(_ argument: C4NamedArgument) {
        let value = argument.value
        switch argument.key {
        case "offsetX": labelOffsetX = JavaScriptInteger.parsed(value)
        case "offsetY": labelOffsetY = JavaScriptInteger.parsed(value)
        case "label": label = value
        case "descr": description = value
        case "techn": technology = value
        case "sprite": sprite = value
        case "tags": tags = value
        case "link": link = value
        case "textColor": textColor = value
        case "lineColor": lineColor = value
        default: otherArguments.set(argument)
        }
    }
}

/// Reads a whole text as 0.7.0's reader read a C4 diagram: preprocessed, its front matter's title taken, then the
/// keyword and the diagram.
enum ReferenceC4Reading {
    enum Reading: Equatable {
        case c4(ReferenceC4Diagram)
        case otherType
    }

    static func read(_ source: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> Reading {
        guard source.utf8.count <= limits.maximumSourceBytes else { throw .sourceTooLarge(limitBytes: limits.maximumSourceBytes) }
        var (title, cursor) = try ReferenceMermaidReader.preprocessed(source)
        ReferenceMermaidReader.skipCommentsAndBlankLines(&cursor)
        guard let keyword = ReferenceMermaidReader.readTypeKeyword(&cursor) else {
            throw cursor.isAtEnd ? .noDiagram : .invalidSyntax(line: cursor.line, problem: .unexpectedText(cursor.excerpt()))
        }
        guard C4DiagramLevel(rawValue: keyword) != nil else { return .otherType }
        var diagram = try ReferenceC4Parser.parse(keyword: keyword, endingAt: cursor.position, of: cursor.bytes, line: cursor.line, limits: limits)
        if diagram.title == nil { diagram.title = title }
        return .c4(diagram)
    }
}
