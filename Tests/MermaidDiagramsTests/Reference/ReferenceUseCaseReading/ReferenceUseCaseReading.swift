/**
 * File: ReferenceUseCaseReading.swift
 * -----------------------------------
 * Layer: Tests
 * Description: A use case diagram read by 0.7.0's reader (ReferenceUseCaseParser, on UTF-16 code units, into Strings
 *              and String-keyed dictionaries) from the front end's cursor, with the front matter's title, as
 *              MermaidDiagramReader read it in 0.7.0; and whether a diagram read now holds what it holds.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

enum ReferenceUseCaseReading {
    /// The use case diagram `source` holds, nil when it is of another type.
    static func read(_ source: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> ReferenceUseCaseDiagram? {
        guard source.utf8.count <= limits.maximumSourceBytes else { throw .sourceTooLarge(limitBytes: limits.maximumSourceBytes) }
        let frontEnd = try MermaidFrontEnd.read(source)
        guard frontEnd.typeKeyword == .useCase || frontEnd.keywordText == "usecase-beta" else { return nil }
        var diagram = try ReferenceUseCaseParser.parse(keyword: frontEnd.keywordText, endingAt: MermaidTextCursor(frontEnd), limits: limits)
        if diagram.title == nil { diagram.title = frontEnd.frontMatterTitle }
        return diagram
    }

    /// The first field in which `read` differs from `expected`, or nil when every one is alike.
    static func difference(_ read: UseCaseDiagram, from expected: ReferenceUseCaseDiagram) -> String? {
        if read.actors != expected.actors { return "actors \(read.actors) where the reference has \(expected.actors)" }
        if read.useCases != expected.useCases { return "use cases \(read.useCases) where the reference has \(expected.useCases)" }
        if read.systemBoundaries != expected.systemBoundaries { return "boundaries \(read.systemBoundaries) where the reference has \(expected.systemBoundaries)" }
        if read.relationships != expected.relationships { return "relationships \(read.relationships) where the reference has \(expected.relationships)" }
        if read.notes != expected.notes { return "notes \(read.notes) where the reference has \(expected.notes)" }
        if read.jsonNodes != expected.jsonNodes { return "JSON tables \(read.jsonNodes) where the reference has \(expected.jsonNodes)" }
        if read.classDefinitions != expected.classDefinitions { return "class definitions \(read.classDefinitions) where the reference has \(expected.classDefinitions)" }
        if read.direction != expected.direction { return "direction \(read.direction) where the reference has \(expected.direction)" }
        if read.title != expected.title { return "title \(String(describing: read.title)) where the reference has \(String(describing: expected.title))" }
        if read.accessibilityTitle != expected.accessibilityTitle || read.accessibilityDescription != expected.accessibilityDescription {
            return "accessibility texts \(read.accessibilityTitle), \(read.accessibilityDescription)"
        }
        if read.nodeSpacing != expected.nodeSpacing || read.rankSpacing != expected.rankSpacing {
            return "spacing \(String(describing: read.nodeSpacing)), \(String(describing: read.rankSpacing))"
        }
        return nil
    }
}
