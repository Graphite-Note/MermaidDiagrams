/**
 * File: PlaneMapPictures.swift
 * ----------------------------
 * Layer: Tests
 * Description: Writes the scenes of Venn diagrams, Cynefin frameworks and Wardley maps as PNG pictures into the folder
 *              `MERMAID_DIAGRAMS_PICTURES` names, for a person to look at; nothing when it names none.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics
import Foundation
import ImageIO
@testable import MermaidDiagrams

/// Writes a scene as a PNG on a white page at two pixels per point into the folder the environment variable
/// `MERMAID_DIAGRAMS_PICTURES` names. A test run without it writes nothing.
enum PlaneMapPictures {
    static var folder: URL? {
        ProcessInfo.processInfo.environment["MERMAID_DIAGRAMS_PICTURES"].map { path in URL(fileURLWithPath: path, isDirectory: true) }
    }

    static func write(_ scene: DiagramScene, named name: String, palette: DiagramPalette = .peleLight) {
        guard let folder else { return }
        let scale: CGFloat = 2
        let width = max(1, Int((scene.size.width * scale).rounded(.up)))
        let height = max(1, Int((scene.size.height * scale).rounded(.up)))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(palette.background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        DiagramSceneRenderer.draw(scene, in: context, palette: palette)
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name + ".png") as CFURL, "public.png" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
