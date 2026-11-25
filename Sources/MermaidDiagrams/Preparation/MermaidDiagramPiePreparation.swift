/**
 * File: MermaidDiagramPiePreparation.swift
 * ----------------------------------------
 * Layer: Core
 * Description: Prepares a pie chart, with its layout for a narrow column, and says what a screen reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

extension MermaidDiagramPreparationContext {
    func prepared(_ chart: PieChart) -> PreparedMermaidDiagram {
        let layout = PieChartLayoutEngine.layout(chart, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (chart, width) }, regularSize: layout.size, laidOut: { chart, width in
                PieChartLayoutEngine.layout(chart, typography: typography, availableWidth: width)
            }, scene: { layout in DiagramScene(layout: layout, limits: limits) }) : nil
        return PreparedMermaidDiagram(kind: .pieChart, scene: DiagramScene(layout: layout, limits: limits), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(pieChart: chart, layout: layout))
    }
}

extension MermaidDiagramAccessibility {
    /// Each slice as the legend shows it, with its percentage when it is drawn (`Dogs 79%`), in the written order.
    init(pieChart chart: PieChart, layout: PieChartLayout) {
        // The slices and the legend alone are taken into the work, not the whole layout.
        let slices = layout.slices
        let legend = layout.legend
        self.init(kind: .pieChart, title: chart.accessibilityTitle ?? chart.title, description: chart.accessibilityDescription) {
            var percentages: [Int: String] = [:]
            for slice in slices { percentages[slice.seriesIndex] = slice.percentage.lines.joined() }
            let sliceSummaries = legend.map { entry in
                let label = entry.text.lines.joined(separator: " ")
                guard let percentage = percentages[entry.seriesIndex] else { return label }
                return label + " " + percentage
            }
            return sliceSummaries
        }
    }
}
