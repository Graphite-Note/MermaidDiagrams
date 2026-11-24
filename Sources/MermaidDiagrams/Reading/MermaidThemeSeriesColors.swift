/**
 * File: MermaidThemeSeriesColors.swift
 * ------------------------------------
 * Layer: Core
 * Description: Reads the series colors a diagram's theme variables set, from its front matter's config.themeVariables
 *              and its %%{init: …}%% directives, as Pele's palette.ts reads them per type: only the variables a type
 *              reads are looked up, and a diagram that sets none gets none at once.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
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

    /// The series colors the theme variables of the cursor's text set for this type: each numbered variable looked up
    /// in the front matter's tree and the directives (`MermaidConfigurationSection`), none at all when neither sets a
    /// theme variable, as most diagrams do; an XY chart's list read from the section's options by its path.
    func seriesColors(in cursor: MermaidTextCursor) -> DiagramSeriesColors {
        guard let (prefix, first) = numberedVariables else {
            return seriesColors(MermaidConfigurationOptions(section: Self.themeVariablesSection, in: cursor))
        }
        let themeVariables = MermaidConfigurationSection(named: Self.themeVariablesSection, in: cursor)
        guard !themeVariables.isEmpty else { return .none }
        return seriesColors(numberedValues: (0..<DiagramSeriesColors.slotCount).map { slot in themeVariables.value(named: prefix + String(first + slot)) })
    }

    /// Pele's `palette`: each of the eight slots from its entry (an XY chart's list and a Venn diagram's taken again in
    /// turn), an entry that is not a color Pele accepts leaving its slot unset.
    func seriesColors(_ themeVariables: MermaidConfigurationOptions) -> DiagramSeriesColors {
        guard let (prefix, first) = numberedVariables else {
            guard themeVariables.values[Self.xyChartSection] == .collection,
                  case .text(let list)? = themeVariables.nestedValues[Self.xyChartSection + "." + Self.plotColorPaletteName] else { return .none }
            return seriesColors(entries: Self.colorList(list).map { entry in .text(entry) }, repeats: true)
        }
        return seriesColors(numberedValues: (0..<DiagramSeriesColors.slotCount).map { slot in themeVariables.values[prefix + String(first + slot)] })
    }

    /// The colors of the values of the numbered variables in order: a Venn diagram's those set and not empty, taken
    /// again in turn.
    private func seriesColors(numberedValues values: [MermaidConfigurationOptions.Value?]) -> DiagramSeriesColors {
        guard self == .venn else { return seriesColors(entries: values, repeats: false) }
        return seriesColors(entries: values.filter { value in value != nil && value != .text("") }, repeats: true)
    }

    private func seriesColors(entries: [MermaidConfigurationOptions.Value?], repeats: Bool) -> DiagramSeriesColors {
        guard !entries.isEmpty else { return .none }
        let colors = (0..<DiagramSeriesColors.slotCount).map { slot -> DiagramThemeColor? in
            guard repeats || slot < entries.count, case .text(let text)? = entries[slot % entries.count] else { return nil }
            return DiagramThemeColor(cssText: text)
        }
        guard colors.contains(where: { color in color != nil }) else { return .none }
        return DiagramSeriesColors(colors: colors)
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
