/**
 * File: MermaidThemeSeriesColors.swift
 * ------------------------------------
 * Layer: Core
 * Description: Reads the series colors a diagram's theme variables set, from its front matter's config.themeVariables
 *              and its %%{init: …}%% directives, as Pele's palette.ts reads them per type.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

/// Which of Mermaid's theme variables set a type's series colors, as Pele's `PALETTES` names them: the variables'
/// prefix and the number of the first series' variable. A mindmap's start at `cScale1`, as `cScale0` is its root's in
/// Mermaid's styles; a Venn diagram's repeat the colors that are set; an XY chart's are one comma list.
enum MermaidThemeSeriesPalette {
    case pieChart
    case gitGraph
    case timeline
    case radar
    case treemap
    case mindmap
    case venn
    case xyChart

    /// The prefix and first number of its variables; nil for the XY chart's list.
    private var numberedVariables: (prefix: String, first: Int)? {
        switch self {
        case .pieChart: ("pie", 1)
        case .gitGraph: ("git", 0)
        case .timeline, .radar, .treemap: ("cScale", 0)
        case .mindmap: ("cScale", 1)
        case .venn: ("venn", 1)
        case .xyChart: nil
        }
    }

    /// The series colors the theme variables of the cursor's text set for this type.
    func seriesColors(in cursor: MermaidTextCursor) -> DiagramSeriesColors {
        seriesColors(MermaidConfigurationOptions(section: Self.themeVariablesSection, in: cursor))
    }

    /// Pele's `palette`: each of the eight slots from its entry (an XY chart's list and a Venn diagram's taken again in
    /// turn), an entry that is not a color Pele accepts leaving its slot unset.
    func seriesColors(_ themeVariables: MermaidConfigurationOptions) -> DiagramSeriesColors {
        guard let (entries, repeats) = entries(themeVariables), !entries.isEmpty else { return .none }
        let colors = (0..<DiagramSeriesColors.slotCount).map { slot -> DiagramThemeColor? in
            guard repeats || slot < entries.count, case .text(let text)? = entries[slot % entries.count] else { return nil }
            return DiagramThemeColor(cssText: text)
        }
        return DiagramSeriesColors(colors: colors)
    }

    /// The values of its variables in order, and whether they are taken again in turn.
    private func entries(_ themeVariables: MermaidConfigurationOptions) -> ([MermaidConfigurationOptions.Value?], Bool)? {
        guard let (prefix, first) = numberedVariables else {
            guard themeVariables.values[Self.xyChartSection] == .collection,
                  case .text(let list)? = themeVariables.nestedValues[Self.xyChartSection + "." + Self.plotColorPaletteName] else { return nil }
            return (Self.colorList(list).map { entry in .text(entry) }, true)
        }
        let values = (0..<DiagramSeriesColors.slotCount).map { slot in themeVariables.values[prefix + String(first + slot)] }
        guard self == .venn else { return (values, false) }
        return (values.filter { value in value != nil && value != .text("") }, true)
    }

    /// Pele's `splitList`: the comma list cut at the commas outside parentheses (those of `rgb()` stay), each entry
    /// trimmed. Only the first eight entries are kept: no slot reaches past them.
    static func colorList(_ value: String) -> [String] {
        var entries: [String] = []
        var depth = 0
        var start = value.startIndex
        for index in value.indices {
            switch value[index] {
            case "(": depth += 1
            case ")": depth -= 1
            case "," where depth == 0:
                entries.append(String(JavaScriptWhitespace.trimmed(value[start..<index])))
                if entries.count == DiagramSeriesColors.slotCount { return entries }
                start = value.index(after: index)
            default: break
            }
        }
        entries.append(String(JavaScriptWhitespace.trimmed(value[start...])))
        return entries
    }

    private static let themeVariablesSection = "themeVariables"
    private static let xyChartSection = "xyChart"
    private static let plotColorPaletteName = "plotColorPalette"
}
