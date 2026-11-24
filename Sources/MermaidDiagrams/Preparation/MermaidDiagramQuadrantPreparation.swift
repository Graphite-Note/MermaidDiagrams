/**
 * File: MermaidDiagramQuadrantPreparation.swift
 * ---------------------------------------------
 * Layer: Core
 * Description: Prepares a quadrant chart, with the chart on a page as wide as a narrow column, and says what a screen
 *              reader hears of it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    /// A quadrant chart, and for a narrow column the chart on a page as wide as the column (Pele's `capWidth`).
    func prepared(_ chart: QuadrantChart) -> PreparedMermaidDiagram {
        let layout = QuadrantChartLayoutEngine.layout(chart, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: chart, regularSize: layout.size, laidOut: { chart in
                QuadrantChartLayoutEngine.layout(chart, typography: typography, availableWidth: narrowestColumnWidth)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .quadrantChart, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(quadrantChart: chart))
    }
}

extension MermaidDiagramAccessibility {
    /// The quadrants' texts from quadrant 1, then each point drawn with its coordinates: “Campaign A (0.3, 0.6)”.
    init(quadrantChart chart: QuadrantChart) {
        self.init(kind: .quadrantChart, title: chart.accessibilityTitle ?? chart.title,
                  description: chart.accessibilityDescription, summarySeparator: "; ") {
            let points = chart.points.compactMap { point -> String? in
                guard let xCoordinate = point.xCoordinate, let yCoordinate = point.yCoordinate, (0...1).contains(xCoordinate),
                      (0...1).contains(yCoordinate) else { return nil }
                return Self.joined(point.label.spokenText, " (", Self.written(xCoordinate), ", ", Self.written(yCoordinate), ")")
            }
            return chart.quadrantLabels.compactMap { label in label?.spokenText } + points
        }
    }
}
