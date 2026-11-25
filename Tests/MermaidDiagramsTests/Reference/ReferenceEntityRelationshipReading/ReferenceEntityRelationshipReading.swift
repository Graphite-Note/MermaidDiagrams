/**
 * File: ReferenceEntityRelationshipReading.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: An entity relationship diagram read by 0.7.0's reader (ReferenceEntityRelationshipParser) from the
 *              front end's cursor, with the front matter's title, as MermaidDiagramReader read it in 0.7.0.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

enum ReferenceEntityRelationshipReading {
    /// The entity relationship diagram `source` holds, nil when it is of another type.
    static func read(_ source: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> EntityRelationshipDiagram? {
        guard source.utf8.count <= limits.maximumSourceBytes else { throw .sourceTooLarge(limitBytes: limits.maximumSourceBytes) }
        let frontEnd = try MermaidFrontEnd.read(source)
        guard frontEnd.typeKeyword == .entityRelationship || frontEnd.keywordText == "erDiagram" else { return nil }
        var diagram = try ReferenceEntityRelationshipParser.parse(MermaidTextCursor(frontEnd), limits: limits)
        if diagram.title == nil { diagram.title = frontEnd.frontMatterTitle }
        return diagram
    }
}
