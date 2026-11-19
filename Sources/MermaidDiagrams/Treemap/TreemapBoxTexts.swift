/**
 * File: TreemapBoxTexts.swift
 * ---------------------------
 * Layer: Core
 * Description: Places the name and the value in a treemap's box as Pele does: in a section's header band, or centered in a leaf.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// The name and the value written in a box.
struct TreemapBoxTexts {
    let name: DiagramTextBlock?
    let value: DiagramTextBlock?
}

/// Fits and places the texts of treemap boxes: Pele's sizes (a section's name at seven eighths of the text's size, 12 points
/// in a short header, its value at three quarters; a leaf's name from the text's size down to 9 points, its value at four
/// fifths of that), and its rooms.
struct TreemapBoxTextPlacement<Measurer: DiagramTextMeasuring> {
    let text: Measurer
    let boldText: Measurer
    /// A section's name in a full header, in points.
    let nameSize: CGFloat
    /// A section's name in a short header and every value in a header, in points.
    let smallSize: CGFloat
    /// The smallest a leaf's name and value are written at, in points.
    let leastSize: CGFloat

    /// The height of a full header band, and of a short one.
    static var fullHeader: CGFloat { 28 }
    /// Between a section's edge and its name or value.
    static var headerSide: CGFloat { 6 }
    /// A line's height as a multiple of its text's size.
    static var lineRatio: CGFloat { 1.25 }
    /// What a header's name leaves to its value: the room between them.
    private static var valueGap: CGFloat { 12 }

    init(text: Measurer, boldText: Measurer) {
        self.text = text
        self.boldText = boldText
        let size = text.fontSize
        nameSize = (size * 0.875).rounded()
        smallSize = (size * 0.75).rounded()
        leastSize = (size * 0.5625).rounded()
    }

    /// The name and the value of a section's header band at `frame`, `header` points high. A short header holds a name only.
    func headerTexts(name: String, value: String, frame: CGRect, header: CGFloat) -> TreemapBoxTexts {
        let isShort = header < Self.fullHeader
        let nameFontSize = isShort ? smallSize : nameSize
        let valueFontSize = smallSize
        let room = frame.width - 2 * Self.headerSide - 4
        let valueWidth = value.isEmpty ? 0 : DiagramTextFitting.width(of: value, atFontSize: valueFontSize, measurer: text)
        let hasRoomForValue = !isShort && valueWidth > 0 && room - valueWidth - Self.valueGap >= 3 * nameFontSize
        let centerY = frame.minY + header / 2 + 1
        var nameBlock: DiagramTextBlock?
        if nameFontSize * Self.lineRatio < header,
           let fitted = DiagramTextFitting.fitted(name, maximumWidth: hasRoomForValue ? room - valueWidth - Self.valueGap : room, fontSize: nameFontSize,
                                                  minimumFontSize: nameFontSize, measurer: boldText) {
            var block = fitted.block
            block.center = CGPoint(x: frame.minX + Self.headerSide + 2 + fitted.width / 2, y: centerY)
            nameBlock = block
        }
        var valueBlock: DiagramTextBlock?
        if hasRoomForValue, valueFontSize * Self.lineRatio <= Self.fullHeader {
            var block = DiagramTextFitting.block(of: value, fontSize: valueFontSize, measurer: text)
            block.center = CGPoint(x: frame.maxX - Self.headerSide - 2 - valueWidth / 2, y: centerY)
            valueBlock = block
        }
        return TreemapBoxTexts(name: nameBlock, value: valueBlock)
    }

    /// The name, and under it the value when both fit, centered in a leaf's box: the name at the text's size or the largest the
    /// box's height allows, shrunk down to the least size to fit the box's width, then cut.
    func leafTexts(name: String, value: String, frame: CGRect) -> TreemapBoxTexts {
        let tallest = min(text.fontSize, ((frame.height - 4) / Self.lineRatio).rounded(.down))
        guard tallest >= leastSize,
              let fitted = DiagramTextFitting.fitted(name, maximumWidth: frame.width - 8, fontSize: tallest, minimumFontSize: leastSize, measurer: text)
        else { return TreemapBoxTexts(name: nil, value: nil) }
        let valueFontSize = max(leastSize, (fitted.fontSize * 0.8).rounded())
        let lineHeights = (fitted.fontSize + valueFontSize) * Self.lineRatio
        var nameBlock = fitted.block
        if !value.isEmpty, lineHeights <= frame.height - 4,
           DiagramTextFitting.width(of: value, atFontSize: valueFontSize, measurer: text) <= frame.width - 8 {
            nameBlock.center = CGPoint(x: frame.midX, y: frame.midY - lineHeights / 2 + fitted.fontSize * Self.lineRatio / 2)
            var valueBlock = DiagramTextFitting.block(of: value, fontSize: valueFontSize, measurer: text)
            valueBlock.center = CGPoint(x: frame.midX, y: frame.midY + lineHeights / 2 - valueFontSize * Self.lineRatio / 2)
            return TreemapBoxTexts(name: nameBlock, value: valueBlock)
        }
        nameBlock.center = CGPoint(x: frame.midX, y: frame.midY)
        return TreemapBoxTexts(name: nameBlock, value: nil)
    }
}
