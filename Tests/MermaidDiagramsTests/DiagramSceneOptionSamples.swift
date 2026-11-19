/**
 * File: DiagramSceneOptionSamples.swift
 * -------------------------------------
 * Layer: Tests
 * Description: Chart texts that set options of their own (sizes, orientation, data labels, colors, outlines), which the
 *              scene tests run over with the other samples.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Texts whose options change how a chart is laid out and painted.
enum DiagramSceneOptionSamples {
    static let all: [(String, String)] = [
        ("quadrant with options", """
            ---
            config:
              quadrantChart:
                chartWidth: 420
                chartHeight: 380
                titleFontSize: 22
                quadrantLabelFontSize: 14
                xAxisLabelFontSize: 12
                yAxisLabelFontSize: 18
                pointLabelFontSize: 11
                quadrantPadding: 14
                xAxisPosition: bottom
                yAxisPosition: right
                pointRadius: 8
            ---
            quadrantChart
                title Reach
                x-axis Low --> High
                y-axis Calm --> Busy
                quadrant-1 Expand
                quadrant-3 Drop
                A: [0.3, 0.6]
                B: [0.8, 0.2]
            """),
        ("xy chart with options", """
            ---
            config:
              xyChart: {width: 560, height: 320, showDataLabel: true, showLegend: false, xAxis: {showTick: false}, yAxis: {showAxisLine: false}}
            ---
            xychart
                title "Sales"
                x-axis [jan, feb, mar, apr]
                y-axis "Revenue" -20 --> 100
                bar [30, 60, -10, 90]
                line [20, 50, 70, 10]
            """),
        ("xy horizontal chart with options", """
            ---
            config:
              xyChart:
                chartOrientation: horizontal
                showDataLabel: true
                xAxis:
                  showLabel: false
            ---
            xychart
                x-axis [alpha, beta, gamma]
                bar "Count" [3, 7, 5]
            """),
        ("sankey source links", "---\nconfig:\n  sankey:\n    linkColor: source\n    labelStyle: outlined\n---\nsankey\nCoal,Power,60\nGas,Power,40\nPower,Homes,70\nPower,Industry,30"),
        ("sankey fixed links and node colors", "---\nconfig:\n  sankey: {linkColor: \"#88aacc\", nodeColors: {Coal: \"#222222\", Homes: orange}}\n---\nsankey\nCoal,Power,60\nGas,Power,40\nPower,Homes,70\nPower,Industry,30"),
        ("sankey target links", "---\nconfig:\n  sankey:\n    linkColor: target\n    width: 400\n---\nsankey\nA,B,5\nB,C,3\nB,D,2"),
    ]
}
