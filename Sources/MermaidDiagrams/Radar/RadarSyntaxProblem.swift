/**
 * File: RadarSyntaxProblem.swift
 * ------------------------------
 * Layer: Core
 * Description: What a radar chart's text can get wrong that no other diagram can.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A problem of a radar chart's own syntax, or a curve its axes cannot take.
public enum RadarSyntaxProblem: Equatable, Sendable {
    /// A name was expected: after `axis`, after a comma in an axis list, after `curve`, or before an entry's value. A word
    /// the grammar keeps (`axis`, `curve`, `max`, `true`, `circle` …) is no name.
    case expectedName
    /// A number was expected: an option's, a curve's value, or an entry's.
    case expectedNumber
    /// An axis' or curve's `[` is not followed by its label in quotation marks and `]`.
    case expectedLabel
    /// A curve's name is not followed by `{`.
    case expectedOpeningBrace
    /// A curve's entries are not separated by commas and closed by `}`.
    case expectedClosingBrace
    /// `showLegend` is not followed by `true` or `false`.
    case expectedBoolean
    /// `graticule` is not followed by `circle` or `polygon`.
    case expectedGraticule
    /// An option was expected after a comma in a list of options.
    case expectedOption
    /// A curve gives its values by axis, and the chart has no axes.
    case entriesNamedBeforeAxes(curve: String)
    /// A curve gives its values by axis and gives none for an axis, by the axis's label.
    case missingEntry(curve: String, axis: String)
}
