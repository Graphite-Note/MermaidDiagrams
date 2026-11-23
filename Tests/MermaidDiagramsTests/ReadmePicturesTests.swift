/**
 * File: ReadmePicturesTests.swift
 * -------------------------------
 * Layer: Tests
 * Description: The README's pictures: one chosen example of every type, each of that type; a picture cropped to the
 *              painted diagram and its margin; IndexedPNGWriter's files read back by Core Graphics with every pixel kept
 *              (at most 256 colors) or near (more), the same picture always giving the same bytes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

final class ReadmePicturesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryTypeHasOneChosenExampleAndItIsOfThatType() throws {
        let chosenKinds = ReadmePictures.chosenExamples.map(\.kind)
        XCTAssertEqual(chosenKinds.count, MermaidDiagramKind.allCases.count)
        XCTAssertEqual(Set(chosenKinds), Set(MermaidDiagramKind.allCases))
        for chosen in ReadmePictures.chosenExamples {
            let sources = try PeleResults.sources(ofCorpus: chosen.corpus)
            XCTAssertTrue(sources.indices.contains(chosen.exampleIndex), "\(chosen.corpus) \(chosen.exampleIndex)")
            guard sources.indices.contains(chosen.exampleIndex) else { continue }
            let prepared = try MermaidDiagramPreparation.prepare(source: sources[chosen.exampleIndex], typography: typography,
                                                                 narrowestColumnWidth: nil, now: ReadmePictures.ganttToday,
                                                                 timeZone: TimeZone(identifier: "UTC") ?? .current)
            XCTAssertEqual(prepared.kind, chosen.kind, "\(chosen.corpus) \(chosen.exampleIndex)")
        }
    }

    /// The painted pixels nearest each edge lie exactly one margin (12 points, 24 pixels) inside it.
    func testAPictureIsCroppedToThePaintedDiagramAndItsMargin() throws {
        let prepared = try MermaidDiagramPreparation.prepare(source: "flowchart LR\n  A[Start] --> B[End]", typography: typography,
                                                             narrowestColumnWidth: nil)
        for appearance in ReadmePictures.appearances {
            let image = try XCTUnwrap(ReadmePictures.picture(of: prepared.scene, palette: appearance.palette))
            let pixels = try pixelColors(of: image)
            let background = pixels[0]
            var top = image.height, bottom = -1, left = image.width, right = -1
            for row in 0..<image.height {
                for column in 0..<image.width where pixels[row * image.width + column] != background {
                    top = min(top, row); bottom = max(bottom, row); left = min(left, column); right = max(right, column)
                }
            }
            let marginPixels = Int(ReadmePictures.marginPoints * ReadmePictures.pixelsPerPoint)
            XCTAssertEqual(top, marginPixels, appearance.name)
            XCTAssertEqual(left, marginPixels, appearance.name)
            XCTAssertEqual(image.height - 1 - bottom, marginPixels, appearance.name)
            XCTAssertEqual(image.width - 1 - right, marginPixels, appearance.name)
        }
    }

    func testAPictureOfAtMost256ColorsIsReadBackWithEveryPixelKept() throws {
        let width = 40, height = 30
        let original = (0..<(width * height)).map { pixelIndex -> UInt32 in
            // 200 colors, each channel different so that a red and blue swapped in the palette shows.
            let colorIndex = UInt32(pixelIndex % 200)
            return colorIndex | (colorIndex * 3 % 256) << 8 | (255 - colorIndex) << 16
        }
        let image = try makeImage(width: width, height: height, pixels: original)
        let png = try IndexedPNGWriter.pngData(of: image)
        XCTAssertEqual(png[25], 3, "a PNG with a palette")
        let readBack = try pixelColors(of: try readPNG(png))
        XCTAssertEqual(readBack.count, original.count)
        let changedPixelCount = zip(original, readBack).filter { originalColor, readColor in originalColor != readColor }.count
        XCTAssertEqual(changedPixelCount, 0)
    }

    func testAPictureOfManyColorsKeepsAtMost256NearTheOriginalAndTheSameBytesEachTime() throws {
        let width = 64, height = 48
        let original = (0..<(width * height)).map { pixelIndex -> UInt32 in
            let row = UInt32(pixelIndex / width), column = UInt32(pixelIndex % width)
            return column * 255 / 63 | (row * 255 / 47) << 8 | ((row + column) * 255 / 110) << 16
        }
        let image = try makeImage(width: width, height: height, pixels: original)
        let png = try IndexedPNGWriter.pngData(of: image)
        XCTAssertEqual(try IndexedPNGWriter.pngData(of: image), png)
        let readBack = try pixelColors(of: try readPNG(png))
        XCTAssertLessThanOrEqual(Set(readBack).count, IndexedPNGWriter.maximumColorCount)
        var largestChannelDifference = 0
        for (originalColor, readColor) in zip(original, readBack) {
            for shift in [0, 8, 16] as [UInt32] {
                largestChannelDifference = max(largestChannelDifference, abs(Int(originalColor >> shift & 0xFF) - Int(readColor >> shift & 0xFF)))
            }
        }
        XCTAssertLessThanOrEqual(largestChannelDifference, 24)
    }

    // MARK: - Pictures as red, green and blue bytes (red lowest)

    private func makeImage(width: Int, height: Int, pixels: [UInt32]) throws -> CGImage {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = pixels
        return try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
    }

    private func readPNG(_ png: Data) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: png as CFData))
        return try XCTUnwrap(CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func pixelColors(of image: CGImage) throws -> [UInt32] {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = [UInt32](repeating: 0, count: image.width * image.height)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                                  bytesPerRow: image.width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels.map { pixel in pixel & 0x00FF_FFFF }
    }
}
