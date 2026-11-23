/**
 * File: VennDiagram.swift
 * -----------------------
 * Layer: Core
 * Description: A Mermaid Venn diagram (`venn-beta`) as its text describes it: its sets and overlaps with their sizes,
 *              the texts written inside them, and the styles of each.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 23/11/2026
 */

/// A Mermaid Venn diagram (`venn-beta`) as Mermaid's database holds it: every `set` and `union` statement in order, every
/// `text` statement, every `style` statement, and the title.
public struct VennDiagram: Equatable, Sendable {
    /// The series colors its theme variables set, which its series are painted in over a palette's; none unless it
    /// sets them.
    public internal(set) var seriesColors = DiagramSeriesColors.none
    /// `title …`, without the spaces at its ends and one pair of quotation marks, else `title:` in the front matter.
    public internal(set) var title: String?
    /// Each `set` and `union` in the order written; a later statement about the same sets replaces an earlier one where
    /// they are drawn.
    public internal(set) var subsets: [VennSubset]
    /// Each `text`, inside the region of its sets.
    public internal(set) var texts: [VennText]
    /// Each `style`, in the order written; a later one for the same targets wins property by property.
    public internal(set) var styles: [VennStyle]

    init(title: String? = nil, subsets: [VennSubset] = [], texts: [VennText] = [], styles: [VennStyle] = []) {
        self.title = title
        self.subsets = subsets
        self.texts = texts
        self.styles = styles
    }

    /// How many style declarations are read and not drawn: a property other than a fill, a stroke, their opacities and
    /// a text color, or a value not read.
    public var unappliedDeclarationCount: Int {
        styles.reduce(0) { count, style in count + style.declarations.filter { declaration in !VennAppearance.applies(declaration) }.count }
    }
}

/// A set (one identifier) or an overlap of sets (several, sorted), with its relative area and its label.
public struct VennSubset: Equatable, Sendable {
    /// The sets' identifiers without one pair of quotation marks, sorted; an overlap may name a set twice.
    public let sets: [String]
    /// The area relative to the others': as written, else 10 for a set and 10 / n² for an overlap of n identifiers.
    public let size: Double
    /// The text in brackets (`set A["Alpha"]`), or nil.
    public let label: String?
}

/// A line of text written inside the region of its sets (`text A1["React"]`, or indented under a set or a union).
public struct VennText: Equatable, Sendable {
    /// The identifiers of the region's sets, sorted.
    public let sets: [String]
    /// The text's own identifier, which a `style` names and which is drawn when it has no label.
    public let identifier: String
    public let label: String?
}

/// A `style` statement: the sets, the overlap or the text it names (sorted), and its declarations in order.
public struct VennStyle: Equatable, Sendable {
    public let targets: [String]
    public let declarations: [VennStyleDeclaration]
}

/// One `property:value` of a style; the value loses one pair of quotation marks.
public struct VennStyleDeclaration: Equatable, Sendable {
    public let property: String
    public let value: String
}

/// What broke a Venn diagram's syntax, beyond text that fits nowhere.
public enum VennSyntaxProblem: Equatable, Sendable {
    /// A set's identifier, plain or quoted, was expected: after `set`, `union`, `text`, `style` or a comma.
    case expectedIdentifier
    /// A number was expected after a set's or an overlap's colon.
    case expectedSize
    /// A text's identifier was expected: a word, quoted text or a number.
    case expectedTextIdentifier
    /// A style's property, then a colon, then its value was expected.
    case expectedStyleDeclaration
    /// A statement was expected: `title`, `set`, `union`, `text`, `style` or a line break.
    case expectedStatement
    /// `union` names one set: it takes two or more.
    case unionOfOneSet
    /// `union` names sets no `set` declared, by their identifiers.
    case unknownSetIdentifiers([String])
    /// An indented `text` follows no set or union.
    case textWithoutSet
}
