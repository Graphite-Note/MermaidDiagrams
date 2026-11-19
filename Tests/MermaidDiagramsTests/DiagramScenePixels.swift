/**
 * File: DiagramScenePixels.swift
 * ------------------------------
 * Layer: Tests
 * Description: Paints a drawing into a bitmap at a scale and counts the pixels where two such bitmaps differ.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The pixels of a drawing painted into a transparent sRGB bitmap at `scale` pixels per point, its y running down.
struct DiagramScenePixels: Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(size: CGSize, scale: CGFloat, painting: (CGContext) -> Void) {
        width = max(1, Int((size.width * scale).rounded(.up)))
        height = max(1, Int((size.height * scale).rounded(.up)))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let width = width
        let height = height
        let painted: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: scale, y: -scale)
            painting(context)
            return true
        }
        guard painted else { return nil }
        self.bytes = bytes
    }

    /// How many pixels differ from `other`'s, or every pixel when the sizes differ.
    func differingPixelCount(from other: DiagramScenePixels) -> Int {
        guard width == other.width, height == other.height else { return max(width * height, other.width * other.height) }
        var count = 0
        var index = 0
        while index < bytes.count {
            if bytes[index] != other.bytes[index] || bytes[index + 1] != other.bytes[index + 1] || bytes[index + 2] != other.bytes[index + 2]
                || bytes[index + 3] != other.bytes[index + 3] {
                count += 1
            }
            index += 4
        }
        return count
    }

    /// Whether any pixel is painted at all.
    var hasPaintedPixel: Bool {
        stride(from: 3, to: bytes.count, by: 4).contains { index in bytes[index] != 0 }
    }
}
