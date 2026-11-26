/**
 * File: ReferenceUseCaseNodeMeasurement.swift
 * -------------------------------------------
 * Layer: Tests
 * Description: The 0.7.0 UseCaseNodeMeasurement kept as the reference the 0.8.0 layout is checked against: each node of
 *              a use case diagram measured as Pele's renderUsecase measures it: an actor's figure over its stereotype
 *              and label, an oval or a box around its text, a note, a JSON table's rows, and a boundary's title and
 *              padding.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

import CoreGraphics
@testable import MermaidDiagrams

/// Pele's measurements of a use case diagram's nodes.
enum ReferenceUseCaseNodeMeasurement {
    static let figureWidth: CGFloat = 40
    static let figureHeight: CGFloat = 60
    static let figureGap: CGFloat = 6
    static let boundaryPadding: CGFloat = 20
    static let tabPadding: CGFloat = 6
    static let cellPadding: CGFloat = 10
    static let rowPadding: CGFloat = 8
    /// The room of each kind of text before it wraps.
    static let titleRoom: CGFloat = 4_000
    static let actorRoom: CGFloat = 140
    static let textRoom: CGFloat = 180
    static let stereotypeRoom: CGFloat = 200
    static let jsonValueRoom: CGFloat = 260

    /// The sizes of a diagram measured at `size`: the edges' and notes' seven eighths and the stereotypes' thirteen
    /// sixteenths, rounded.
    static func smallSize(_ size: CGFloat) -> CGFloat { (size * 0.875).rounded() }
    static func stereotypeSize(_ size: CGFloat) -> CGFloat { (size * 0.8125).rounded() }

    static func view<Measurer>(of node: ReferenceUseCaseGraphNode, size: CGFloat, measurers: inout ReferenceUseCaseTextMeasurers<Measurer>) -> ReferenceUseCaseNodeView {
        let look = UseCaseLook(styles: node.styles)
        let fontSize = look.fontSize ?? size
        let stereotypeMeasurer = measurers.measurer(size: stereotypeSize(size), isBold: look.isBold, isItalic: look.isItalic)
        let stereotype = ReferenceUseCaseTextLabel.block(node.stereotype.map { stereotype in "«\(stereotype)»" }, measurer: stereotypeMeasurer, room: stereotypeRoom)
        var view = ReferenceUseCaseNodeView(node: node, look: look, label: stereotype, stereotype: stereotype)
        let labelMeasurer = measurers.measurer(size: fontSize, isBold: look.isBold, isItalic: look.isItalic)
        if node.isGroup {
            view.form = .boundary
            view.label = ReferenceUseCaseTextLabel.block(node.label, labelType: node.labelType, measurer: labelMeasurer, room: titleRoom)
            let titleHeight = view.label.size.height
            let top = node.boundaryType == .package ? titleHeight + 2 * tabPadding + 16 : titleHeight > 0 ? titleHeight + 16 : boundaryPadding
            view.clusterPadding = LayeredClusterPadding(side: boundaryPadding, top: top, bottom: boundaryPadding)
            view.clusterMinimumWidth = view.label.size.width + 2 * boundaryPadding
        } else if let rows = node.jsonRows {
            measureTable(rows, of: &view, size: size, fontSize: fontSize, measurers: &measurers)
        } else if node.actorType != nil {
            view.form = .actor
            view.label = ReferenceUseCaseTextLabel.block(node.label, labelType: node.labelType, measurer: labelMeasurer, room: actorRoom)
            view.size = CGSize(width: max(figureWidth, view.label.size.width, stereotype.size.width),
                               height: figureHeight + figureGap + stereotype.size.height + view.label.size.height)
        } else {
            measureOutlined(&view, size: size, fontSize: fontSize, measurers: &measurers)
        }
        return view
    }

    /// An oval, a box or a note around its stereotype and label.
    private static func measureOutlined<Measurer>(_ view: inout ReferenceUseCaseNodeView, size: CGFloat, fontSize: CGFloat,
                                                  measurers: inout ReferenceUseCaseTextMeasurers<Measurer>) {
        let node = view.node
        let measurer = measurers.measurer(size: node.shape == .note ? smallSize(size) : fontSize, isBold: view.look.isBold, isItalic: view.look.isItalic)
        view.label = ReferenceUseCaseTextLabel.block(node.label, labelType: node.labelType, measurer: measurer, room: textRoom)
        let textWidth = max(view.label.size.width, view.stereotype.size.width)
        let textHeight = view.label.size.height + view.stereotype.size.height
        switch node.shape {
        case .ellipse, .businessEllipse:
            view.form = .ellipse
            // An oval needs more room around its text than a box, and a business oval room for its slash.
            view.size = CGSize(width: max(textWidth + 2 * node.padding + (node.isBusiness ? 16 : 4), 88), height: max(textHeight + 28, 48))
        case .note: view.size = CGSize(width: textWidth + 2 * node.padding + 6, height: textHeight + 18)
        default: view.size = CGSize(width: max(textWidth + 2 * node.padding + 12, 80), height: max(textHeight + 24, 44))
        }
    }

    /// A JSON table: its name in bold over a row for each leaf, keys in a column of their own when any has one.
    private static func measureTable<Measurer>(_ rows: [UseCaseJSONRow], of view: inout ReferenceUseCaseNodeView, size: CGFloat, fontSize: CGFloat,
                                               measurers: inout ReferenceUseCaseTextMeasurers<Measurer>) {
        view.form = .json
        let look = view.look
        view.label = ReferenceUseCaseTextLabel.block(view.node.label, measurer: measurers.measurer(size: fontSize, isBold: true, isItalic: look.isItalic),
                                            room: titleRoom)
        let small = smallSize(size)
        let cellMeasurer = measurers.measurer(size: small, isBold: look.isBold, isItalic: look.isItalic)
        let leastRowHeight = (small * 1.5).rounded()
        var valueWidth: CGFloat = 0
        var height: CGFloat = 0
        view.rows.reserveCapacity(rows.count)
        for row in rows {
            let key = ReferenceUseCaseTextLabel.block(row.key, measurer: cellMeasurer, room: titleRoom)
            let value = ReferenceUseCaseTextLabel.block(row.value, measurer: cellMeasurer, room: jsonValueRoom)
            let rowHeight = max(key.size.height, value.size.height, leastRowHeight) + rowPadding
            view.rows.append((key, value, rowHeight))
            view.keyColumnWidth = max(view.keyColumnWidth, key.size.width)
            valueWidth = max(valueWidth, value.size.width)
            height += rowHeight
        }
        // The root of an empty object has a value and no key, and then there is no key column.
        if view.keyColumnWidth > 0 { view.keyColumnWidth += 2 * cellPadding }
        view.headHeight = max(view.label.size.height, (fontSize * 1.5).rounded()) + rowPadding
        let width = max(view.label.size.width + 2 * cellPadding, rows.isEmpty ? 0 : view.keyColumnWidth + valueWidth + 2 * cellPadding, 72)
        view.size = CGSize(width: width, height: height + view.headHeight)
    }
}
