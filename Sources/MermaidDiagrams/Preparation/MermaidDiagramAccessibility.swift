/**
 * File: MermaidDiagramAccessibility.swift
 * ---------------------------------------
 * Layer: Core
 * Description: What a screen reader says of a prepared diagram: its label, the title or the type's name, and its value,
 *              the description or a summary of what it shows, made the first time it is read; the summary's parts each
 *              built in one string, and how the types' summaries write numbers and texts.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 24/11/2026
 */

/// What a screen reader says of a diagram: its title, else the type's name, then its description, else a summary of
/// what it shows (the nodes' text, the slices with their shares, each message), as the reading view says it. The title
/// and the description are known when the diagram is prepared; the summary is made the first time it is read
/// (`summary`, `value`), from any thread, and kept.
public struct MermaidDiagramAccessibility: Equatable, Sendable {
    /// `accTitle`, else the diagram's title, else nil.
    public let title: String?
    /// `accDescr`, or nil.
    public let description: String?
    /// What the summary's parts are joined with: a comma for names, a semicolon for parts that hold commas.
    public let summarySeparator: String
    let kind: MermaidDiagramKind
    /// The summary's parts, made when first read.
    let summaryParts: MermaidDiagramAccessibilitySummary

    init(kind: MermaidDiagramKind, title: String?, description: String?, summary: [String], summarySeparator: String = ", ") {
        self.init(kind: kind, title: title, description: description, summaryParts: .made(summary), summarySeparator: summarySeparator)
    }

    /// A summary `summary` makes the first time it is read: the diagram it captures is kept until then.
    init(kind: MermaidDiagramKind, title: String?, description: String?, summarySeparator: String = ", ",
         summary: @escaping @Sendable () -> [String]) {
        self.init(kind: kind, title: title, description: description, summaryParts: .later(MermaidDiagramAccessibilityLaterSummary(summary)),
                  summarySeparator: summarySeparator)
    }

    private init(kind: MermaidDiagramKind, title: String?, description: String?, summaryParts: MermaidDiagramAccessibilitySummary,
                 summarySeparator: String) {
        self.kind = kind
        self.title = title
        self.description = description
        self.summaryParts = summaryParts
        self.summarySeparator = summarySeparator
    }

    /// What the diagram shows, part by part, in the order it is written; made the first time it is read.
    public var summary: [String] {
        summaryParts.parts
    }

    /// The title, else the type's name (`MermaidDiagramKind.spokenName`).
    public var label: String {
        title ?? kind.spokenName
    }

    /// The description, else the summary.
    public var value: String {
        description ?? summary.joined(separator: summarySeparator)
    }

    public static func == (left: MermaidDiagramAccessibility, right: MermaidDiagramAccessibility) -> Bool {
        left.kind == right.kind && left.title == right.title && left.description == right.description
            && left.summarySeparator == right.summarySeparator && left.summary == right.summary
    }
}

extension MermaidDiagramAccessibility {
    /// The texts one after the other, in one string given its room at once, where `+` would make a string per step.
    static func joined(_ parts: String...) -> String {
        var text = ""
        text.reserveCapacity(parts.reduce(0) { total, part in total + part.utf8.count })
        for part in parts { text += part }
        return text
    }

    /// 2⁵³: past it, a double holds no fraction and not every whole number.
    private static let largestExactWholeNumber = 9_007_199_254_740_992.0

    /// A number as it is written: a whole number without a fraction (`5`), else with its fraction (`3.5`).
    static func written(_ value: Double) -> String {
        value == value.rounded() && value.magnitude < largestExactWholeNumber ? String(Int64(value)) : String(value)
    }

    /// A text as it is drawn, its lines joined by spaces.
    static func spoken(_ text: String) -> String {
        DiagramLabelDecoder.label(from: text, form: .plain).spokenText
    }
}
