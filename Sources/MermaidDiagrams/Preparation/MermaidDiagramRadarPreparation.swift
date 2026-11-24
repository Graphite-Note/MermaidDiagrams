/**
 * File: MermaidDiagramRadarPreparation.swift
 * ------------------------------------------
 * Layer: Core
 * Description: Prepares a radar chart, with its layout for a narrow column, and says what a screen reader hears of
 *              it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension MermaidDiagramPreparationContext {
    func prepared(_ radar: RadarChart) -> PreparedMermaidDiagram {
        let layout = RadarChartLayoutEngine.layout(radar, typography: typography)
        let narrow = narrowSceneIsWanted(forRegularSize: layout.size)
            ? narrowScene(of: narrowestColumnWidth.map { width in (radar, width) }, regularSize: layout.size, laidOut: { radar, width in
                RadarChartLayoutEngine.layout(radar, typography: typography, availableWidth: width)
            }, scene: DiagramScene.init(layout:)) : nil
        return PreparedMermaidDiagram(kind: .radar, scene: DiagramScene(layout: layout), preparedNarrowScene: narrow,
                                      accessibility: MermaidDiagramAccessibility(radar: radar))
    }
}

extension MermaidDiagramAccessibility {
    /// Each curve with its value on each axis, when it is drawn: “Alice: Math 85, Science 90”; a curve that is not drawn is
    /// named alone.
    init(radar chart: RadarChart) {
        self.init(kind: .radar, title: chart.accessibilityTitle ?? chart.title, description: chart.accessibilityDescription, summarySeparator: "; ") {
            let curves = chart.curves.map { curve in
                let name = curve.label.spokenText
                guard curve.values.count == chart.axes.count, !chart.axes.isEmpty else { return name }
                let values = zip(chart.axes, curve.values).map { axis, value in "\(axis.label.spokenText) \(Self.written(value))" }
                return name + ": " + values.joined(separator: ", ")
            }
            return curves
        }
    }
}
