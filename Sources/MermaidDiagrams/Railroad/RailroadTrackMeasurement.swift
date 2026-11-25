/**
 * File: RailroadTrackMeasurement.swift
 * ------------------------------------
 * Layer: Core
 * Description: Measures each part of a railroad rule as Pele does: a box whose track enters at its left and leaves at
 *              its right on one baseline, with room above and below it; long sequences folded into rows when the width
 *              is bounded.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 25/11/2026
 */

import CoreGraphics

/// The measurements a railroad diagram is laid out with, from its options and Pele's defaults.
struct RailroadMetrics {
    let terminalText: CoreTextDiagramTextMeasurer
    let nameText: CoreTextDiagramTextMeasurer
    let specialText: CoreTextDiagramTextMeasurer
    let countText: CoreTextDiagramTextMeasurer
    /// Room on either side of a box's text, and a box's height.
    let padding: CGFloat
    let height: CGFloat
    /// Between the parts of a sequence, and between stacked branches.
    let gap: CGFloat
    let separation: CGFloat
    /// The radius of the track's quarter turns.
    let arc: CGFloat

    /// The size of a repetition's count, and the length of the arrows on loops and folds.
    static let countSize: CGFloat = 12
    static let arrowLength: CGFloat = 7

    /// `value` rounded up to the next even number.
    static func even(_ value: CGFloat) -> CGFloat {
        (value / 2).rounded(.up) * 2
    }
}

/// A measured part of a rule: its kind, its width, how far it reaches above and below its baseline, its parts, and the
/// text of a box or of a loop's count.
struct RailroadTrackBox {
    enum Kind {
        case terminal
        case nonterminal
        case special
        case sequence
        case choice
        /// A part with a track above it that passes it by.
        case bypass
        /// A part with a track below it that leads back to its start.
        case loop
        /// A sequence folded into rows, one below the other, inside rails.
        case folded
    }

    let kind: Kind
    let width: CGFloat
    let up: CGFloat
    let down: CGFloat
    var children: [RailroadTrackBox] = []
    var text = ""
    /// How far a bypass rises above the baseline, or a loop drops below it.
    var reach: CGFloat = 0

    /// Where the branch after `above` sits below the baseline, `offset` being where `above` sits.
    static func offset(below above: RailroadTrackBox, at offset: CGFloat, of branch: RailroadTrackBox, metrics: RailroadMetrics) -> CGFloat {
        max(offset + above.down + metrics.separation + branch.up, 2 * metrics.arc)
    }

    /// The gap between two rows of a folded sequence.
    static func rowGap(_ metrics: RailroadMetrics) -> CGFloat {
        max(metrics.separation, 2 * metrics.arc)
    }
}

/// Measures a rule's definition as Pele's `measure` does. With a bounded `room`, each part is given the room its parent
/// leaves after its own rails (at least 40 points), and a sequence wider than its room is folded into rows that fit.
struct RailroadTrackMeasurement {
    let metrics: RailroadMetrics

    /// The box of `expression`. Leaves and each kind of part are measured by functions of their own, so that this one,
    /// which every level of a rule's tree passes through, keeps a small frame on the stack: a tree nested as deep as
    /// `RailroadExpression.maximumNestingDepth` allows is measured on a secondary thread's 512 KiB stack, in a debug
    /// build too.
    func box(of expression: RailroadExpression, room: CGFloat) -> RailroadTrackBox {
        switch expression {
        case .terminal(let value): terminalBox(value)
        case .nonterminal(let name): nameBox(name)
        case .special(let text): specialBox(text)
        case .sequence(let elements): sequence(boxes(of: elements, room: childRoom(room, around: 6 * metrics.arc)), room: room)
        case .choice(let alternatives): choice(boxes(of: alternatives, room: childRoom(room, around: 4 * metrics.arc)))
        case .optional(let element): bypass(box(of: element, room: childRoom(room, around: 4 * metrics.arc)))
        case .repetition(let element, let minimum, let maximum):
            repetition(box(of: element, room: childRoom(room, around: (minimum == 0 ? 6 : 2) * metrics.arc)), minimum: minimum, maximum: maximum)
        }
    }

    private func boxes(of expressions: [RailroadExpression], room: CGFloat) -> [RailroadTrackBox] {
        expressions.map { expression in box(of: expression, room: room) }
    }

    /// A terminal's box: a text of blanks alone is drawn as that many visible blanks.
    private func terminalBox(_ value: String) -> RailroadTrackBox {
        let text = RailroadText.shown(value)
        let blanks = !text.isEmpty && text.allSatisfy { character in character == " " }
        return leaf(.terminal, blanks ? String(repeating: "␣", count: text.count) : text, measurer: metrics.terminalText)
    }

    /// A name's box, the name of a rule.
    private func nameBox(_ name: String) -> RailroadTrackBox {
        leaf(.nonterminal, RailroadText.shown(name), measurer: metrics.nameText)
    }

    /// A special sequence's box, its text between `? ` and ` ?`.
    private func specialBox(_ text: String) -> RailroadTrackBox {
        leaf(.special, "? " + RailroadText.shown(text) + " ?", measurer: metrics.specialText)
    }

    private func childRoom(_ room: CGFloat, around: CGFloat) -> CGFloat {
        room.isFinite ? max(40, room - around) : room
    }

    private func leaf(_ kind: RailroadTrackBox.Kind, _ text: String, measurer: CoreTextDiagramTextMeasurer) -> RailroadTrackBox {
        let width = max(RailroadMetrics.even(measurer.width(of: text) + 2 * metrics.padding), metrics.height)
        return RailroadTrackBox(kind: kind, width: width, up: metrics.height / 2, down: metrics.height / 2, text: text)
    }

    /// The parts side by side a gap apart; when wider than `room`, folded into rows of what fits beside the rails.
    private func sequence(_ children: [RailroadTrackBox], room: CGFloat) -> RailroadTrackBox {
        let width = children.reduce(CGFloat(max(0, children.count - 1)) * metrics.gap) { total, child in total + child.width }
        let sequence = RailroadTrackBox(kind: .sequence, width: width, up: Self.highestUp(of: children), down: Self.lowestDown(of: children),
                                        children: children)
        guard width > room, children.count >= 2 else { return sequence }
        var rows: [RailroadTrackBox] = []
        var row: [RailroadTrackBox] = []
        var rowWidth: CGFloat = 0
        func finishRow() {
            rows.append(RailroadTrackBox(kind: .sequence, width: rowWidth, up: Self.highestUp(of: row), down: Self.lowestDown(of: row), children: row))
            row = []
            rowWidth = 0
        }
        for child in children {
            if !row.isEmpty, rowWidth + metrics.gap + child.width > max(40, room - 6 * metrics.arc) { finishRow() }
            rowWidth += (row.isEmpty ? 0 : metrics.gap) + child.width
            row.append(child)
        }
        finishRow()
        guard rows.count >= 2 else { return sequence }
        var offset: CGFloat = 0
        for index in 1..<rows.count { offset += rows[index - 1].down + RailroadTrackBox.rowGap(metrics) + rows[index].up }
        return RailroadTrackBox(kind: .folded, width: Self.widest(of: rows) + 6 * metrics.arc, up: rows[0].up,
                                down: offset + (rows.last?.down ?? 0), children: rows)
    }

    /// The largest reach above the baseline of `boxes`, 0 for none: the first of equal ones, as `max()` of their list
    /// gives, without making the list.
    private static func highestUp(of boxes: [RailroadTrackBox]) -> CGFloat {
        guard var highest = boxes.first?.up else { return 0 }
        for box in boxes.dropFirst() where box.up > highest { highest = box.up }
        return highest
    }

    /// The largest reach below the baseline of `boxes`, 0 for none, as `highestUp(of:)` finds it.
    private static func lowestDown(of boxes: [RailroadTrackBox]) -> CGFloat {
        guard var lowest = boxes.first?.down else { return 0 }
        for box in boxes.dropFirst() where box.down > lowest { lowest = box.down }
        return lowest
    }

    /// The largest width of `boxes`, 0 for none, as `highestUp(of:)` finds it.
    private static func widest(of boxes: [RailroadTrackBox]) -> CGFloat {
        guard var widest = boxes.first?.width else { return 0 }
        for box in boxes.dropFirst() where box.width > widest { widest = box.width }
        return widest
    }

    /// The branches stacked, the first on the baseline, the next ones below.
    private func choice(_ children: [RailroadTrackBox]) -> RailroadTrackBox {
        var offset: CGFloat = 0
        for index in children.indices.dropFirst() {
            offset = RailroadTrackBox.offset(below: children[index - 1], at: offset, of: children[index], metrics: metrics)
        }
        return RailroadTrackBox(kind: .choice, width: Self.widest(of: children) + 4 * metrics.arc, up: children.first?.up ?? 0,
                                down: offset + (children.last?.down ?? 0), children: children)
    }

    private func bypass(_ child: RailroadTrackBox) -> RailroadTrackBox {
        let reach = max(child.up + metrics.separation, 2 * metrics.arc)
        return RailroadTrackBox(kind: .bypass, width: child.width + 4 * metrics.arc, up: reach, down: child.down, children: [child], reach: reach)
    }

    /// A part taken once is the part itself; otherwise a loop back below it with its count, bypassed when it may be
    /// taken no time.
    private func repetition(_ child: RailroadTrackBox, minimum: Double, maximum: Double) -> RailroadTrackBox {
        guard minimum != 1 || maximum != 1 else { return child }
        let count = RailroadText.count(minimum: minimum, maximum: maximum)
        let reach = max(child.down + metrics.separation, 2 * metrics.arc)
        let countWidth = count.isEmpty ? 0 : RailroadMetrics.even(metrics.countText.width(of: count))
        let loop = RailroadTrackBox(kind: .loop, width: max(child.width, countWidth) + 2 * metrics.arc, up: child.up,
                                    down: reach + (count.isEmpty ? RailroadMetrics.arrowLength / 2 + 1 : RailroadMetrics.countSize + 6),
                                    children: [child], text: count, reach: reach)
        return minimum == 0 ? bypass(loop) : loop
    }
}
