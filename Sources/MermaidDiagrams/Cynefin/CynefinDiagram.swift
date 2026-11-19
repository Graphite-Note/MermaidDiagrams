/**
 * File: CynefinDiagram.swift
 * --------------------------
 * Layer: Core
 * Description: A Mermaid Cynefin framework (`cynefin-beta`) as its text describes it: the items of each domain, the
 *              transitions between domains, the title, the accessibility statements and the options.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// A Mermaid Cynefin framework (`cynefin-beta`) as Mermaid's database holds it. All five domains are drawn whether the
/// text declares them or not.
public struct CynefinDiagram: Equatable, Sendable {
    /// `title …`, else `title:` in the front matter.
    public internal(set) var title: String?
    public internal(set) var accessibilityTitle: String?
    public internal(set) var accessibilityDescription: String?
    /// The items of each domain the text declares; a later block of a domain replaces an earlier one.
    public internal(set) var items: [CynefinDomain: [String]]
    /// The transitions between two domains in the order written, those from a domain to itself left out.
    public internal(set) var transitions: [CynefinTransition]
    public internal(set) var options: CynefinOptions

    init(title: String? = nil, accessibilityTitle: String? = nil, accessibilityDescription: String? = nil, items: [CynefinDomain: [String]] = [:],
         transitions: [CynefinTransition] = [], options: CynefinOptions = CynefinOptions()) {
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.items = items
        self.transitions = transitions
        self.options = options
    }
}

/// The five domains of the Cynefin framework.
public enum CynefinDomain: String, CaseIterable, Sendable {
    case complex
    case complicated
    case clear
    case chaotic
    case confusion

    /// The domain's name as drawn.
    public var name: String {
        switch self {
        case .complex: "Complex"
        case .complicated: "Complicated"
        case .clear: "Clear"
        case .chaotic: "Chaotic"
        case .confusion: "Confusion"
        }
    }

    /// Its decision model, drawn under its name; empty for confusion.
    var decisionModel: String {
        switch self {
        case .complex: "Probe → Sense → Respond"
        case .complicated: "Sense → Analyse → Respond"
        case .clear: "Sense → Categorise → Respond"
        case .chaotic: "Act → Sense → Respond"
        case .confusion: ""
        }
    }

    /// Its kind of practice, drawn under the decision model.
    var practice: String {
        switch self {
        case .complex: "Emergent Practices"
        case .complicated: "Good Practices"
        case .clear: "Best Practices"
        case .chaotic: "Novel Practices"
        case .confusion: "Disorder"
        }
    }
}

/// A transition from one domain to another, with its quoted label or nil.
public struct CynefinTransition: Equatable, Sendable {
    public let from: CynefinDomain
    public let to: CynefinDomain
    public let label: String?
}

/// The options of Cynefin frameworks the front matter (`config:`, then `cynefin:`) and directives set, each within
/// Pele's range, else its default.
public struct CynefinOptions: Equatable, Sendable {
    /// `width`, 100 to 10,000: the board's least width; its quadrants are half of it.
    public internal(set) var width: CGFloat = 640
    /// `height`, 100 to 10,000.
    public internal(set) var height: CGFloat = 440
    /// `showDomainDescriptions`: whether each domain shows its decision model and practice; false only when written false.
    public internal(set) var showsDomainDescriptions = true
    /// `boundaryAmplitude`, 0 to 50: how far the boundaries between domains wave.
    public internal(set) var boundaryAmplitude: Double = 8
    /// `seed`, other than zero: the seed of the boundaries' waves, else the hash of Pele's identifier prefix.
    public internal(set) var seed: Double?

    public init() {}

    init(_ options: MermaidConfigurationOptions) {
        if case .number(let width) = options.values["width"], (100...10_000).contains(width) { self.width = CGFloat(width) }
        if case .number(let height) = options.values["height"], (100...10_000).contains(height) { self.height = CGFloat(height) }
        if case .boolean(false) = options.values["showDomainDescriptions"] { showsDomainDescriptions = false }
        if case .number(let amplitude) = options.values["boundaryAmplitude"], (0...50).contains(amplitude) { boundaryAmplitude = amplitude }
        if case .number(let seed) = options.values["seed"], (-1e15...1e15).contains(seed), seed != 0 { self.seed = seed }
    }
}

/// What broke a Cynefin framework's syntax, beyond text no terminal reads.
public enum CynefinSyntaxProblem: Equatable, Sendable {
    /// A statement was expected: a domain, a transition, a title, an accessibility statement or a line break.
    case expectedStatement
    /// A domain was expected after `-->`.
    case expectedDomain
    /// Quoted text was expected after a transition's colon.
    case expectedQuotedLabel
    /// A line break or the end of the text was expected after a statement.
    case expectedLineEnd
}
