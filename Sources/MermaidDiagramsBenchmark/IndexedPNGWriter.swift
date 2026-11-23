/**
 * File: IndexedPNGWriter.swift
 * ----------------------------
 * Layer: Benchmark
 * Description: Writes an opaque picture as a PNG of at most 256 colors (color type 3), its colors chosen by median cut
 *              when it has more, so that the README's pictures stay small.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import CoreGraphics
import Foundation

/// A PNG with a palette: every pixel one byte naming one of at most 256 colors. A diagram's flat fills, lines and
/// smoothed text edges fit that palette with no visible change, at about a third of the bytes of a full-color PNG.
enum IndexedPNGWriter {
    static let maximumColorCount = 256

    struct WritingFailure: Error, CustomStringConvertible {
        let description: String
    }

    /// The picture's PNG bytes. `image` is drawn into an sRGB bitmap first, so any picture is accepted; its alpha is dropped.
    static func pngData(of image: CGImage) throws -> Data {
        let width = image.width, height = image.height
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let pixelMemory = context.data else { throw WritingFailure(description: "no bitmap for a picture of \(width) by \(height)") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixelCount = width * height
        let pixels = pixelMemory.bindMemory(to: UInt32.self, capacity: pixelCount)
        var population: [UInt32: Int] = [:]
        for pixelIndex in 0..<pixelCount { population[pixels[pixelIndex] & 0x00FF_FFFF, default: 0] += 1 }
        let palette = population.count <= maximumColorCount ? population.keys.sorted() : MedianCutPalette.colors(of: population, count: maximumColorCount)
        let paletteIndexByColor = paletteIndices(of: population.keys, in: palette)
        var rows = Data(capacity: pixelCount + height)
        for row in 0..<height {
            rows.append(0) // The filter "None": a palette's indices gain nothing from the others.
            for column in 0..<width { rows.append(paletteIndexByColor[pixels[row * width + column] & 0x00FF_FFFF] ?? 0) }
        }
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var header = Data()
        header.appendBigEndian(UInt32(width))
        header.appendBigEndian(UInt32(height))
        header.append(contentsOf: [8, 3, 0, 0, 0]) // 8 bits an index, a palette, deflate, adaptive filters, no interlace.
        appendChunk("IHDR", header, to: &png)
        var paletteBytes = Data(capacity: palette.count * 3)
        for color in palette { paletteBytes.append(contentsOf: [UInt8(color & 0xFF), UInt8(color >> 8 & 0xFF), UInt8(color >> 16 & 0xFF)]) }
        appendChunk("PLTE", paletteBytes, to: &png)
        appendChunk("IDAT", try zlibStream(of: rows), to: &png)
        appendChunk("IEND", Data(), to: &png)
        return png
    }

    /// The nearest palette color of each color, by squared distance in sRGB.
    private static func paletteIndices(of colors: Dictionary<UInt32, Int>.Keys, in palette: [UInt32]) -> [UInt32: UInt8] {
        var indices: [UInt32: UInt8] = [:]
        indices.reserveCapacity(colors.count)
        for color in colors {
            var nearestIndex = 0, nearestDistance = Int.max
            for (paletteIndex, candidate) in palette.enumerated() {
                let distance = squaredDistance(color, candidate)
                if distance < nearestDistance { nearestDistance = distance; nearestIndex = paletteIndex }
                if distance == 0 { break }
            }
            indices[color] = UInt8(nearestIndex)
        }
        return indices
    }

    private static func squaredDistance(_ first: UInt32, _ second: UInt32) -> Int {
        var total = 0
        for shift in [0, 8, 16] as [UInt32] {
            let difference = Int(first >> shift & 0xFF) - Int(second >> shift & 0xFF)
            total += difference * difference
        }
        return total
    }

    /// A zlib stream (RFC 1950) around Foundation's raw deflate: the two header bytes, the data, its Adler-32.
    private static func zlibStream(of bytes: Data) throws -> Data {
        guard let deflated = try? (bytes as NSData).compressed(using: .zlib) as Data else { throw WritingFailure(description: "deflate failed") }
        var stream = Data([0x78, 0xDA])
        stream.append(deflated)
        var sumOfBytes: UInt32 = 1, sumOfSums: UInt32 = 0
        for byte in bytes {
            sumOfBytes = (sumOfBytes + UInt32(byte)) % 65_521
            sumOfSums = (sumOfSums + sumOfBytes) % 65_521
        }
        stream.appendBigEndian(sumOfSums << 16 | sumOfBytes)
        return stream
    }

    private static func appendChunk(_ type: String, _ content: Data, to png: inout Data) {
        png.appendBigEndian(UInt32(content.count))
        var typeAndContent = Data(type.utf8)
        typeAndContent.append(content)
        png.append(typeAndContent)
        png.appendBigEndian(crc32(of: typeAndContent))
    }

    private static let crcTable: [UInt32] = (0..<256).map { tableIndex in
        var crc = UInt32(tableIndex)
        for _ in 0..<8 { crc = crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
        return crc
    }

    private static func crc32(of bytes: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

/// Heckbert's median cut: the colors, weighted by how many pixels hold them, split again and again across the widest
/// channel of the box that spans the most, at its weighted median; each box gives its weighted mean.
enum MedianCutPalette {
    private struct ColorBox {
        var colors: [(color: UInt32, pixelCount: Int)]

        var widestChannel: (shift: UInt32, span: Int) {
            var widest: (shift: UInt32, span: Int) = (0, -1)
            for shift in [0, 8, 16] as [UInt32] {
                var lowest = 255, highest = 0
                for entry in colors {
                    let channel = Int(entry.color >> shift & 0xFF)
                    lowest = min(lowest, channel)
                    highest = max(highest, channel)
                }
                if highest - lowest > widest.span { widest = (shift, highest - lowest) }
            }
            return widest
        }

        var meanColor: UInt32 {
            var sums = [0, 0, 0], total = 0
            for entry in colors {
                for (channelIndex, shift) in ([0, 8, 16] as [UInt32]).enumerated() { sums[channelIndex] += Int(entry.color >> shift & 0xFF) * entry.pixelCount }
                total += entry.pixelCount
            }
            let means = sums.map { sum in UInt32((sum + total / 2) / max(total, 1)) }
            return means[0] | means[1] << 8 | means[2] << 16
        }
    }

    static func colors(of population: [UInt32: Int], count: Int) -> [UInt32] {
        // In the colors' order, not the dictionary's, which changes from run to run: the same picture gives the same file.
        let colors = population.keys.sorted().map { color in (color: color, pixelCount: population[color] ?? 0) }
        var boxes = [ColorBox(colors: colors)]
        while boxes.count < count {
            // The box to split: the widest span, weighted by the square root of its pixels so that large flat areas
            // keep their exact color and smoothed edges share the rest.
            var chosenIndex = -1, chosenScore = 0.0
            for (boxIndex, box) in boxes.enumerated() where box.colors.count > 1 {
                let pixels = box.colors.reduce(0) { total, entry in total + entry.pixelCount }
                let score = Double(box.widestChannel.span) * Double(pixels).squareRoot()
                if score > chosenScore { chosenScore = score; chosenIndex = boxIndex }
            }
            guard chosenIndex >= 0 else { break }
            let box = boxes[chosenIndex]
            let shift = box.widestChannel.shift
            let sorted = box.colors.sorted { first, second in
                let firstChannel = first.color >> shift & 0xFF, secondChannel = second.color >> shift & 0xFF
                return firstChannel != secondChannel ? firstChannel < secondChannel : first.color < second.color
            }
            let half = sorted.reduce(0) { total, entry in total + entry.pixelCount } / 2
            var running = 0, splitIndex = 1
            for (entryIndex, entry) in sorted.enumerated() {
                running += entry.pixelCount
                if running >= half { splitIndex = min(max(entryIndex + 1, 1), sorted.count - 1); break }
            }
            boxes[chosenIndex] = ColorBox(colors: Array(sorted[..<splitIndex]))
            boxes.append(ColorBox(colors: Array(sorted[splitIndex...])))
        }
        return boxes.map(\.meanColor)
    }
}

private extension Data {
    mutating func appendBigEndian(_ number: UInt32) {
        append(contentsOf: [UInt8(number >> 24 & 0xFF), UInt8(number >> 16 & 0xFF), UInt8(number >> 8 & 0xFF), UInt8(number & 0xFF)])
    }
}
