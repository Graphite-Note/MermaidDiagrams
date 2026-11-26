/**
 * File: DiagramSceneShapeRunRulesTests.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: The scene builder's rules for joining shapes, given as Core Graphics paths and as lanes: a fill and the
 *              stroke of its own path in the same part become one shape, in any other part, order or count they stay
 *              apart, and a run outlined so is joined by the next shape painted as it is. Every scene of every type and
 *              the reference scenes the equivalence tests compare with go through this builder, so its rules are
 *              checked here on their own.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams

final class DiagramSceneShapeRunRulesTests: XCTestCase {
    private static let line = DiagramStroke(lineWidth: 1)
    private static let dashed = DiagramStroke.rounded(lineWidth: 1, dashLengths: [3, 4])

    private static func square(at x: CGFloat) -> CGRect { CGRect(x: x, y: 0, width: 10, height: 10) }

    /// One shape given to the builder: a square at `x`, filled, stroked or both, in `part`.
    private enum Given {
        case fill(CGFloat, DiagramPaint, DiagramScenePart)
        case stroke(CGFloat, DiagramPaint, DiagramStroke, DiagramScenePart)
        case fillAndStroke(CGFloat, DiagramPaint, DiagramPaint, DiagramScenePart)
    }

    /// The shapes given, and the shapes the builder must make of them: painting, part and the bounds of the joined paths.
    private static let cases: [(given: [Given], expected: [(DiagramShapePainting, DiagramScenePart, CGRect)])] = [
        // The stroke of the run's path in another part is a shape of its own.
        ([.fill(0, .surface, .node), .stroke(0, .border, line, .cluster)],
         [(.fill(.surface), .node, square(at: 0)), (.stroke(.border, line), .cluster, square(at: 0))]),
        // In the same part it outlines the fill, and the next box painted so, apart, joins it.
        ([.fill(0, .surface, .node), .stroke(0, .border, line, .node), .fillAndStroke(100, .surface, .border, .node)],
         [(.fillAndStroke(.surface, .border, line), .node, CGRect(x: 0, y: 0, width: 110, height: 10))]),
        // A stroke then a fill of the same path, or a stroke after a stroke, is never outlined.
        ([.stroke(0, .border, line, .node), .fill(0, .surface, .node), .stroke(0, .border, line, .node)],
         [(.stroke(.border, line), .node, square(at: 0)), (.fillAndStroke(.surface, .border, line), .node, square(at: 0))]),
        // The stroke of another path, apart, does not outline the fill.
        ([.fill(0, .surface, .node), .stroke(100, .border, line, .node)],
         [(.fill(.surface), .node, square(at: 0)), (.stroke(.border, line), .node, square(at: 100))]),
        // A run of two fills is not outlined by the stroke of the first.
        ([.fill(0, .surface, .node), .fill(100, .surface, .node), .stroke(0, .border, line, .node)],
         [(.fill(.surface), .node, CGRect(x: 0, y: 0, width: 110, height: 10)), (.stroke(.border, line), .node, square(at: 0))]),
        // A translucent fill is outlined, but a translucent shape painted as the run never joins it.
        ([.fill(0, DiagramPaint.surface.atOpacity(0.5), .node), .stroke(0, .border, line, .node),
          .fillAndStroke(100, DiagramPaint.surface.atOpacity(0.5), .border, .node)],
         [(.fillAndStroke(DiagramPaint.surface.atOpacity(0.5), .border, line), .node, square(at: 0)),
          (.fillAndStroke(DiagramPaint.surface.atOpacity(0.5), .border, line), .node, square(at: 100))]),
        // A shape painted otherwise, or in another part, or touching the run, starts a run of its own.
        ([.stroke(0, .border, line, .edge), .stroke(100, .border, dashed, .edge), .stroke(200, .border, dashed, .marker),
          .stroke(205, .border, dashed, .marker), .stroke(400, .border, dashed, .marker)],
         [(.stroke(.border, line), .edge, square(at: 0)), (.stroke(.border, dashed), .edge, square(at: 100)),
          (.stroke(.border, dashed), .marker, square(at: 200)), (.stroke(.border, dashed), .marker, CGRect(x: 205, y: 0, width: 205, height: 10))]),
    ]

    func testShapesGivenAsCoreGraphicsPathsAreJoinedByTheRules() {
        for (given, expected) in Self.cases {
            var builder = DiagramSceneBuilder()
            for shape in given {
                switch shape {
                case .fill(let x, let paint, let part): builder.fill(CGPath(rect: Self.square(at: x), transform: nil), paint, part: part)
                case .stroke(let x, let paint, let stroke, let part):
                    builder.stroke(CGPath(rect: Self.square(at: x), transform: nil), paint, stroke, part: part)
                case .fillAndStroke(let x, let fill, let paint, let part):
                    builder.fillAndStroke(CGPath(rect: Self.square(at: x), transform: nil), fill: fill, stroke: paint, Self.line, part: part)
                }
            }
            assert(builder.scene(size: CGSize(width: 500, height: 10), font: DiagramFont(postScriptName: nil, size: 16)), makes: expected, from: given)
        }
    }

    func testShapesGivenAsLanesAreJoinedByTheRules() {
        DiagramSceneWorkspace.withRecording { workspace in
            for (given, expected) in Self.cases {
                var builder = DiagramSceneBuilder(workspace: workspace)
                for shape in given {
                    switch shape {
                    case .fill(let x, let paint, let part): builder.fill(workspace.rectangle(Self.square(at: x)), paint, part: part)
                    case .stroke(let x, let paint, let stroke, let part): builder.stroke(workspace.rectangle(Self.square(at: x)), paint, stroke, part: part)
                    case .fillAndStroke(let x, let fill, let paint, let part):
                        builder.fillAndStroke(workspace.rectangle(Self.square(at: x)), fill: fill, stroke: paint, Self.line, part: part)
                    }
                }
                assert(builder.scene(size: CGSize(width: 500, height: 10), font: DiagramFont(postScriptName: nil, size: 16)), makes: expected, from: given)
            }
        }
    }

    private func assert(_ scene: DiagramScene, makes expected: [(DiagramShapePainting, DiagramScenePart, CGRect)], from given: [Given],
                        file: StaticString = #filePath, line: UInt = #line) {
        let shapes = scene.shapes
        XCTAssertEqual(shapes.count, expected.count, "\(given)", file: file, line: line)
        for (shape, (painting, part, bounds)) in zip(shapes, expected) {
            XCTAssertEqual(shape.painting, painting, "\(given)", file: file, line: line)
            XCTAssertEqual(shape.part, part, "\(given)", file: file, line: line)
            XCTAssertEqual(shape.path.boundingBoxOfPath, bounds, "\(given)", file: file, line: line)
        }
    }
}
