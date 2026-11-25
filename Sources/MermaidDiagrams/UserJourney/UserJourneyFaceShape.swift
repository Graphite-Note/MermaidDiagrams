/**
 * File: UserJourneyFaceShape.swift
 * --------------------------------
 * Layer: Core
 * Description: Pele's face for a user journey's score, added to Core Graphics paths or to lanes.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.2
 * Date: 25/11/2026
 */

import CoreGraphics
import Foundation

/// Pele's face for a user journey's score: a circle 11 points in radius, two eyes, and a mouth that smiles, stays
/// straight or frowns. Measured from the face's center, y running down.
enum UserJourneyFaceShape {
    /// Where the right eye is; the left one mirrors it.
    static let eyeOffset = CGVector(dx: 3.6, dy: -2.8)
    static let eyeRadius: CGFloat = 1.3
    /// A smile or a frown is an arc of a circle this wide between corners this far apart.
    static let curvedMouthRadius: CGFloat = 6
    static let curvedMouthHalfWidth: CGFloat = 5
    /// How far below the center a smile's corners are, and a frown's.
    static let smileCornerDepth: CGFloat = 2
    static let frownCornerDepth: CGFloat = 6.5
    /// A straight mouth's half width and depth below the center.
    static let straightMouthHalfWidth: CGFloat = 4.5
    static let straightMouthDepth: CGFloat = 4.5

    /// Adds the face's circle at `center` to `circles`, its eyes to `eyes` and its mouth to `mouths`, Core Graphics paths.
    static func add(_ mood: UserJourneyMood, at center: CGPoint, circles: CGMutablePath, eyes: CGMutablePath, mouths: CGMutablePath) {
        add(mood, at: center, circles: DiagramCoreGraphicsPath(mutable: circles), eyes: DiagramCoreGraphicsPath(mutable: eyes),
            mouths: DiagramCoreGraphicsPath(mutable: mouths))
    }

    /// Adds the face's circle at `center` to `circles`, its eyes to `eyes` and its mouth to `mouths`.
    static func add<Path: DiagramCurvedPathRecording>(_ mood: UserJourneyMood, at center: CGPoint, circles: Path, eyes: Path, mouths: Path) {
        let radius = UserJourneyGeometry.faceRadius
        circles.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        for side in [-1.0, 1.0] {
            let eye = CGPoint(x: center.x + side * eyeOffset.dx, y: center.y + eyeOffset.dy)
            eyes.addEllipse(in: CGRect(x: eye.x - eyeRadius, y: eye.y - eyeRadius, width: 2 * eyeRadius, height: 2 * eyeRadius))
        }
        switch mood {
        case .happy: addCurvedMouth(at: center, cornerDepth: smileCornerDepth, bulgesDown: true, to: mouths)
        case .sad: addCurvedMouth(at: center, cornerDepth: frownCornerDepth, bulgesDown: false, to: mouths)
        case .neutral:
            mouths.move(to: CGPoint(x: center.x - straightMouthHalfWidth, y: center.y + straightMouthDepth))
            mouths.addLine(to: CGPoint(x: center.x + straightMouthHalfWidth, y: center.y + straightMouthDepth))
        }
    }

    /// How far a curved mouth's corners are from its circle's center, up or down: the same for every face.
    private static let curvedMouthRise = (curvedMouthRadius * curvedMouthRadius - curvedMouthHalfWidth * curvedMouthHalfWidth).squareRoot()
    /// The angle of a smile's right corner, and of a frown's, from its circle's center, worked out once instead of for
    /// each face: the same operations on the same constants, so the same bits.
    private static let smileCornerAngle = atan2(curvedMouthRise, curvedMouthHalfWidth)
    private static let frownCornerAngle = atan2(-curvedMouthRise, curvedMouthHalfWidth)

    /// The shorter arc between the corners, below them for a smile and above them for a frown, from left to right.
    private static func addCurvedMouth<Path: DiagramCurvedPathRecording>(at center: CGPoint, cornerDepth: CGFloat, bulgesDown: Bool, to mouths: Path) {
        let rise = curvedMouthRise
        let arcCenter = CGPoint(x: center.x, y: center.y + cornerDepth + (bulgesDown ? -rise : rise))
        let cornerAngle = bulgesDown ? smileCornerAngle : frownCornerAngle
        let leftAngle = bulgesDown ? CGFloat.pi - cornerAngle : -CGFloat.pi - cornerAngle
        mouths.move(to: CGPoint(x: center.x - curvedMouthHalfWidth, y: center.y + cornerDepth))
        // Angles grow from the x axis toward the y axis, which runs down here: a smile runs from the left corner down
        // through the bottom to the right one by decreasing angles, a frown up through the top by increasing ones.
        mouths.addArc(center: arcCenter, radius: curvedMouthRadius, startAngle: leftAngle, endAngle: cornerAngle, clockwise: bulgesDown)
    }
}
