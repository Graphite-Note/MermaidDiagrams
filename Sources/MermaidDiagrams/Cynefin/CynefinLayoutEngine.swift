/**
 * File: CynefinLayoutEngine.swift
 * -------------------------------
 * Layer: Core
 * Description: Lays a Cynefin framework out as Pele's renderCynefin does: the quadrants sized to their blocks and clear
 *              of the confusion ellipse, the seeded boundaries and the cliff, the regions they outline, the blocks.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Lays a Cynefin framework out in Pele's measurements: quadrants half the options' width and height (640 by 440), grown
/// to hold their blocks 20 points from their sides, and wider or taller where a block's inner corner would reach into the
/// confusion ellipse; the ellipse at least 88 by 64 points in radius around confusion's block; the boundaries waving by
/// the options' amplitude from their seed; 8 points of padding and the bold title 12 points above.
public enum CynefinLayoutEngine {
    static let padding: CGFloat = 8
    static let titleGap: CGFloat = 12
    /// Between a block and its quadrant's sides.
    static let blockMargin: CGFloat = 20
    /// Between a block's inner corner and the ellipse.
    static let ellipseClearance: CGFloat = 10
    /// The ellipse's least radii, and how far it reaches past confusion's block: 0.71 of the block plus 8 and 6 points.
    static let leastEllipseRadii = CGSize(width: 88, height: 64)
    static let ellipseShare: CGFloat = 0.71
    static let ellipsePadding = CGSize(width: 8, height: 6)
    /// The cliff waves by this share of the board's width.
    static let cliffShare: CGFloat = 0.03
    /// The quadrants in Pele's order, with their column, row and series color.
    static let quadrants: [(domain: CynefinDomain, column: CGFloat, row: CGFloat, seriesIndex: Int)] = [
        (.complex, 0, 0, 0), (.complicated, 1, 0, 1), (.chaotic, 0, 1, 3), (.clear, 1, 1, 2),
    ]
    /// Confusion's series color.
    static let confusionSeriesIndex = 4

    public static func layout(_ diagram: CynefinDiagram, typography: DiagramTypography) -> CynefinLayout {
        layout(diagram, measurers: CynefinMeasurers(nameText: typography.boldNodeText, subtitleText: typography.planeMapText.italicRowText,
                                                     itemText: typography.edgeText, labelText: typography.rowText), font: typography.font)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: CynefinDiagram, measurers: CynefinMeasurers<Measurer>, font: DiagramFont) -> CynefinLayout {
        let options = diagram.options
        let drafts = quadrants.map { quadrant in
            CynefinBlockDraft(domain: quadrant.domain, items: diagram.items[quadrant.domain] ?? [], showsDescriptions: options.showsDomainDescriptions,
                              measurers: measurers)
        }
        let confusion = CynefinBlockDraft(domain: .confusion, items: diagram.items[.confusion] ?? [], showsDescriptions: options.showsDomainDescriptions,
                                          measurers: measurers)
        let radii = CGSize(width: max(leastEllipseRadii.width, confusion.size.width * ellipseShare + ellipsePadding.width),
                           height: max(leastEllipseRadii.height, confusion.size.height * ellipseShare + ellipsePadding.height))
        let quadrant = quadrantSize(blocks: drafts, options: options, radii: radii)
        let title = PlaneMapLabel.block(diagram.title, measurer: measurers.nameText)
        let titleHeight = title.map { block in block.size.height + titleGap } ?? 0
        let board = CGRect(x: padding, y: padding + titleHeight, width: 2 * quadrant.width, height: 2 * quadrant.height)
        let center = CGPoint(x: board.midX, y: board.midY)
        var blocks = zip(quadrants, drafts).map { placement, draft in
            draft.placed(at: CGPoint(x: board.minX + quadrant.width * (placement.column + 0.5), y: board.minY + quadrant.height * (placement.row + 0.5)))
        }
        blocks.append(confusion.placed(at: center))
        let boundaries = CynefinBoard(board: board, seed: CynefinBoundaries.seed(configured: options.seed), amplitude: options.boundaryAmplitude)
        let ellipse = CGRect(x: center.x - radii.width, y: center.y - radii.height, width: 2 * radii.width, height: 2 * radii.height)
        let transitions = CynefinTransitionRouting(blocks: blocks, ellipse: ellipse, board: board, labelText: measurers.labelText).routed(diagram.transitions)
        let size = CGSize(width: (max(board.width, title?.size.width ?? 0) + 2 * padding).rounded(.up),
                          height: (board.height + titleHeight + 2 * padding).rounded(.up))
        return CynefinLayout(size: size, font: font, title: title.map { block in PlaneMapLabel.placed(block, at: CGPoint(x: board.midX, y: padding + block.size.height / 2)) },
                             regions: boundaries.regions, boundaries: [boundaries.fold, boundaries.west, boundaries.east], cliff: boundaries.cliff,
                             confusion: ellipse, blocks: blocks, transitions: transitions)
    }

    /// Each quadrant's size: half the options' board, grown to hold every block with its margins, then wider or taller,
    /// whichever keeps the board's proportions closer, where a block in the middle of its quadrant would reach into the
    /// ellipse with its clearance.
    private static func quadrantSize(blocks: [CynefinBlockDraft], options: CynefinOptions, radii: CGSize) -> CGSize {
        var width = options.width / 2
        var height = options.height / 2
        for block in blocks {
            width = max(width, block.size.width + 2 * blockMargin)
            height = max(height, block.size.height + 2 * blockMargin)
        }
        for block in blocks {
            let across = (width - block.size.width) / 2
            let down = (height - block.size.height) / 2
            let reachAcross = radii.width + ellipseClearance
            let reachDown = radii.height + ellipseClearance
            if (across / reachAcross) * (across / reachAcross) + (down / reachDown) * (down / reachDown) >= 1 { continue }
            let wider = block.size.width + 2 * reachAcross
            let taller = block.size.height + 2 * reachDown
            if wider * height <= width * taller { width = max(width, wider) } else { height = max(height, taller) }
        }
        return CGSize(width: width, height: height)
    }
}

/// The board's boundaries from their seed and the regions they outline: the fold from the top to the middle, the
/// boundaries from the left side and to the right side through the middle, and the cliff from the middle to the bottom.
struct CynefinBoard {
    let fold: DiagramPath
    let west: DiagramPath
    let east: DiagramPath
    let cliff: DiagramPath
    let regions: [CynefinLayoutRegion]

    /// Each boundary's seed is the board's, the west one's 100 more and the east one's 200 more, as in Mermaid.
    static let westSeedOffset: Double = 100
    static let eastSeedOffset: Double = 200
    static let boundarySegmentCount = 4

    init(board: CGRect, seed: Double, amplitude: Double) {
        var foldShape = CynefinBoundaries.WaveShape.fold
        foldShape.segmentCount = Self.boundarySegmentCount
        foldShape.pinsEnd = true
        var westShape = CynefinBoundaries.WaveShape.horizon
        westShape.segmentCount = Self.boundarySegmentCount
        westShape.pinsEnd = true
        var eastShape = westShape
        eastShape.pinsEnd = false
        eastShape.pinsStart = true
        fold = CynefinBoundaries.wave(from: board.minY, to: board.midY, center: board.midX, seed: seed, amplitude: amplitude, shape: foldShape)
        west = CynefinBoundaries.wave(from: board.minX, to: board.midX, center: board.midY, seed: seed + Self.westSeedOffset, amplitude: amplitude, shape: westShape)
        east = CynefinBoundaries.wave(from: board.midX, to: board.maxX, center: board.midY, seed: seed + Self.eastSeedOffset, amplitude: amplitude, shape: eastShape)
        cliff = CynefinBoundaries.cliff(centerX: board.midX, top: board.midY, bottom: board.maxY, amplitude: board.width * CynefinLayoutEngine.cliffShare)
        let reversed = CynefinBoundaries.reversed
        let outlines: [CynefinDomain: DiagramPath] = [
            .complex: DiagramPath(start: board.origin, segments: [.line(to: fold.start)] + fold.segments + reversed(west).segments),
            .complicated: DiagramPath(start: fold.start, segments: [.line(to: CGPoint(x: board.maxX, y: board.minY)), .line(to: CynefinBoundaries.endPoint(of: east))]
                                      + reversed(east).segments + reversed(fold).segments),
            .chaotic: DiagramPath(start: west.start, segments: west.segments + cliff.segments + [.line(to: CGPoint(x: board.minX, y: board.maxY))]),
            .clear: DiagramPath(start: east.start, segments: east.segments + [.line(to: CGPoint(x: board.maxX, y: board.maxY)), .line(to: CynefinBoundaries.endPoint(of: cliff))]
                                + reversed(cliff).segments),
        ]
        regions = CynefinLayoutEngine.quadrants.compactMap { quadrant in
            outlines[quadrant.domain].map { outline in CynefinLayoutRegion(domain: quadrant.domain, outline: outline, seriesIndex: quadrant.seriesIndex) }
        }
    }
}
