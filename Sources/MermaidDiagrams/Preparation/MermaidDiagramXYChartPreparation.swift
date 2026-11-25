/**
 * File: MermaidDiagramXYChartPreparation.swift
 * --------------------------------------------
 * Layer: Core
 * Description: Prepares an XY chart, with the chart on a page as wide as a narrow column, and says what a screen
 *              reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// An XY chart, and for a narrow column the chart on a page as wide as the column (Pele's `capWidth`).
    func prepared(_ chart: XYChart) throws(MermaidDiagramPreparationFailure) -> PreparedMermaidDiagram {
        let layout: XYChartLayout
        do { layout = try XYChartLayoutEngine.layout(chart, typography: typography) } catch { throw .xyChartLayout(error) }
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: chart, regularSize: layout.size, laidOut: { chart in
                try XYChartLayoutEngine.layout(chart, typography: typography, availableWidth: narrowestColumnWidth)
            }, scene: { layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .xyChart, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(xyChart: chart))
    }
}

extension MermaidDiagramAccessibility {
    /// Each series with its values: “Revenue: jan 5000, feb 6000” along categories, “Revenue: 5000, 6000” along a range;
    /// a series without a title is named by its kind.
    init(xyChart chart: XYChart) {
        self.init(kind: .xyChart, title: chart.accessibilityTitle ?? chart.title,
                  description: chart.accessibilityDescription, summarySeparator: "; ") {
            var categories: [String] = []
            if case .categories(let labels) = chart.xAxis.scale { categories = labels.map(\.spokenText) }
            let seriesSummaries = chart.series.map { series in
                let name = series.title.isEmpty ? (series.kind == .bar ? "Bars" : "Line") : series.title.spokenText
                let values = series.values.enumerated().compactMap { index, value in
                    value.map { value in index < categories.count ? categories[index] + " " + Self.written(value) : Self.written(value) }
                }
                return name + ": " + values.joined(separator: ", ")
            }
            return seriesSummaries
        }
    }
}
