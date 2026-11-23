/**
 * File: InfoDiagram.swift
 * -----------------------
 * Layer: Core
 * Description: A Mermaid info diagram as its text describes it: a title and the accessibility statements, nothing else.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// A Mermaid info diagram (`info`, optionally `showInfo`): the page that says which version drew it. It states nothing but
/// its titles.
public struct InfoDiagram: Equatable, Sendable {
    /// `title …` in the diagram, else `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?

    init(title: String? = nil, accessibilityTitle: String? = nil, accessibilityDescription: String? = nil) {
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }
}

/// The package's own name and version, which an info diagram prints where Pele prints its own.
public enum MermaidDiagramsVersion {
    public static let name = "MermaidDiagrams"
    /// The version the next release of the package carries; kept in step with its tag.
    public static let number = "0.5.0"
    /// What an info diagram says under its title.
    public static let text = "\(name) v\(number)"
}
