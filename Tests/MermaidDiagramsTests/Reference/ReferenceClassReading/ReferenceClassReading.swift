/**
 * File: ReferenceClassReading.swift
 * ---------------------------------
 * Layer: Tests
 * Description: A class diagram read by 0.7.0's reader (ReferenceClassDiagramParser) from the front end's cursor, with
 *              the front matter's title, as MermaidDiagramReader read it in 0.7.0.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 25/11/2026
 */

@testable import MermaidDiagrams

enum ReferenceClassReading {
    /// The class diagram `source` holds, nil when it is of another type.
    static func read(_ source: String, limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) -> ClassDiagram? {
        guard source.utf8.count <= limits.maximumSourceBytes else { throw .sourceTooLarge(limitBytes: limits.maximumSourceBytes) }
        let frontEnd = try MermaidFrontEnd.read(source)
        guard frontEnd.typeKeyword == .classDiagram || ["classDiagram", "classDiagram-v2"].contains(frontEnd.keywordText) else { return nil }
        var diagram = try ReferenceClassDiagramParser.parse(MermaidTextCursor(frontEnd), limits: limits)
        if diagram.title == nil { diagram.title = frontEnd.frontMatterTitle }
        return diagram
    }
}
