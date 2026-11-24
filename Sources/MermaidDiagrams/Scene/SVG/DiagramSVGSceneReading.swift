/**
 * File: DiagramSVGSceneReading.swift
 * ----------------------------------
 * Layer: Core
 * Description: How the SVG writer reads a scene where it keeps its items: whether it has gradient fills, the gradients'
 *              definitions, and each item's element, a path's data written straight from the elements in the scene's
 *              storage, without a Core Graphics path.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 24/11/2026
 */

import CoreGraphics

extension DiagramSVGBody {
    /// Whether any shape of `scene` is filled with a gradient, which needs `<defs>`.
    static func hasGradientFills(_ scene: DiagramScene) -> Bool {
        scene.paintings.withUnsafeBufferPointer { paintings in
            for index in paintings.indices {
                if case .gradientFill = paintings[index] { return true }
            }
            return false
        }
    }

    /// `<defs>` with a definition of each gradient fill of `scene`, numbered in their order as `add(_:)` numbers their
    /// uses (the paintings are in the shapes' order), or nothing when no shape has one: written before the items, where
    /// the document has them, so that nothing is put in before the body afterwards.
    mutating func appendDefinitions(of scene: DiagramScene) {
        var definitionCount = 0
        for painting in scene.paintings {
            guard case .gradientFill(let gradient) = painting else { continue }
            if definitionCount == 0 { appendDefinitionsOpening() }
            definitionCount += 1
            appendGradientDefinition(gradient, number: definitionCount)
        }
        if definitionCount > 0 { appendDefinitionsClosing() }
    }

    /// Every item, back to front.
    mutating func addItems(of scene: DiagramScene) {
        scene.storage.withContents { contents in
            for index in 0..<contents.itemCount {
                let record = contents.records[index]
                switch record.kind {
                case .shape:
                    appendShapeOpening(part: record.part)
                    appendPathData(contents, itemAt: index)
                    appendShapeClosing(painting: scene.paintings[Int(record.index)])
                case .text:
                    add(scene.texts[Int(record.index)])
                }
            }
        }
    }

    /// The path data of the shape at `index`: `M`, `L`, `Q`, `C` and `Z` with absolute coordinates, written up to
    /// `elementsReservedTogether` elements at a time into room made once for them, the cursor kept in a register.
    private mutating func appendPathData(_ contents: DiagramSceneStorageContents, itemAt index: Int) {
        var point = UnsafePointer(contents.points + Int(contents.records[index].firstPoint))
        let verbs = UnsafePointer(contents.verbs)
        let range = contents.verbRange(ofItemAt: index)
        var verbIndex = range.lowerBound
        while verbIndex < range.upperBound {
            let end = min(verbIndex + Self.elementsReservedTogether, range.upperBound)
            content.write(reserving: (end - verbIndex) * DiagramSVGNumberWriting.largestPathElementByteCount) { start in
                var cursor = start
                for element in verbIndex..<end {
                    let verb = verbs[element]
                    cursor += DiagramSVGNumberWriting.writePathElement(verb, point, to: cursor)
                    point += verb.pointCount
                }
                return cursor - start
            }
            verbIndex = end
        }
    }

    /// How many path elements have their room made at once: 6.5 KB, so that a long path never asks for much more room
    /// than it takes.
    private static let elementsReservedTogether = 64
}
