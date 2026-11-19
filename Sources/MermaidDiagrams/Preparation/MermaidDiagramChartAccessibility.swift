/**
 * File: MermaidDiagramChartAccessibility.swift
 * --------------------------------------------
 * Layer: Core
 * Description: What a screen reader says of timelines, pie, Gantt, quadrant and XY charts, user journeys and Sankey
 *              diagrams, as the reading view says it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

extension MermaidDiagramAccessibility {
    /// Each period with its events, in the order the diagram writes them: “2004: Facebook, Google”.
    init(timeline diagram: TimelineDiagram) {
        let periodTexts = diagram.periods.map { period in
            period.events.isEmpty ? period.label.spokenText
                : period.label.spokenText + ": " + period.events.map(\.spokenText).joined(separator: ", ")
        }
        self.init(kind: .timeline, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription,
                  summary: periodTexts, summarySeparator: "; ")
    }

    /// Each slice as the legend shows it, with its percentage when it is drawn (`Dogs 79%`), in the written order.
    init(pieChart chart: PieChart, layout: PieChartLayout) {
        var percentages: [Int: String] = [:]
        for slice in layout.slices { percentages[slice.seriesIndex] = slice.percentage.lines.joined() }
        let sliceSummaries = layout.legend.map { entry in
            let label = entry.text.lines.joined(separator: " ")
            guard let percentage = percentages[entry.seriesIndex] else { return label }
            return label + " " + percentage
        }
        self.init(kind: .pieChart, title: chart.accessibilityTitle ?? chart.title, description: chart.accessibilityDescription, summary: sliceSummaries)
    }

    /// The tasks' text, in the order they are written.
    init(ganttChart chart: GanttChart) {
        self.init(kind: .ganttChart, title: chart.accessibilityTitle ?? chart.title, description: chart.accessibilityDescription,
                  summary: chart.tasks.map(\.name))
    }

    /// Each task with the level its face shows when it has a score, and the actors who take part: “Do work: 1 (Me, Cat)”.
    init(userJourney diagram: UserJourneyDiagram, layout: UserJourneyLayout) {
        let taskTexts = zip(diagram.tasks, layout.tasks).map { task, placed in
            var text = task.label.spokenText
            if task.score != nil { text += ": " + Self.written(task.level) }
            let actors = placed.actorDots.compactMap { dot in
                layout.legend.indices.contains(dot.seriesIndex) ? layout.legend[dot.seriesIndex].text.lines.joined(separator: " ") : nil
            }
            return actors.isEmpty ? text : text + " (" + actors.joined(separator: ", ") + ")"
        }
        self.init(kind: .userJourney, title: diagram.accessibilityTitle ?? diagram.title, description: diagram.accessibilityDescription,
                  summary: taskTexts, summarySeparator: "; ")
    }

    /// The quadrants' texts from quadrant 1, then each point drawn with its coordinates: “Campaign A (0.3, 0.6)”.
    init(quadrantChart chart: QuadrantChart) {
        let points = chart.points.compactMap { point -> String? in
            guard let xCoordinate = point.xCoordinate, let yCoordinate = point.yCoordinate, (0...1).contains(xCoordinate),
                  (0...1).contains(yCoordinate) else { return nil }
            return point.label.spokenText + " (" + Self.written(xCoordinate) + ", " + Self.written(yCoordinate) + ")"
        }
        self.init(kind: .quadrantChart, title: chart.accessibilityTitle ?? chart.title, description: chart.accessibilityDescription,
                  summary: chart.quadrantLabels.compactMap { label in label?.spokenText } + points, summarySeparator: "; ")
    }

    /// Each series with its values: “Revenue: jan 5000, feb 6000” along categories, “Revenue: 5000, 6000” along a range;
    /// a series without a title is named by its kind.
    init(xyChart chart: XYChart) {
        var categories: [String] = []
        if case .categories(let labels) = chart.xAxis.scale { categories = labels.map(\.spokenText) }
        let seriesSummaries = chart.series.map { series in
            let name = series.title.isEmpty ? (series.kind == .bar ? "Bars" : "Line") : series.title.spokenText
            let values = series.values.enumerated().compactMap { index, value in
                value.map { value in index < categories.count ? categories[index] + " " + Self.written(value) : Self.written(value) }
            }
            return name + ": " + values.joined(separator: ", ")
        }
        self.init(kind: .xyChart, title: chart.accessibilityTitle ?? chart.title, description: chart.accessibilityDescription,
                  summary: seriesSummaries, summarySeparator: "; ")
    }

    /// Each flow in the order of its row, with its value rounded to two decimals: “Coal to Solid: 75.57”. Mermaid's
    /// Sankey grammar has no accessibility statements: the title is the front matter's.
    init(sankey diagram: SankeyDiagram) {
        let flows = diagram.links.map { link in
            let flow = diagram.nodes[link.sourceIndex].name + " to " + diagram.nodes[link.targetIndex].name
            guard let value = link.value, value.isFinite, value > 0 else { return flow }
            return flow + ": " + Self.written((value * 100).rounded() / 100)
        }
        self.init(kind: .sankey, title: diagram.title, description: nil, summary: flows, summarySeparator: "; ")
    }

    /// 2⁵³: past it, a double holds no fraction and not every whole number.
    private static let largestExactWholeNumber = 9_007_199_254_740_992.0

    /// A number as it is written: a whole number without a fraction (`5`), else with its fraction (`3.5`).
    static func written(_ value: Double) -> String {
        value == value.rounded() && value.magnitude < largestExactWholeNumber ? String(Int64(value)) : String(value)
    }
}
