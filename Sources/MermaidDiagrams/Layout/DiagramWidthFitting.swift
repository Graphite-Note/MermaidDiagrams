/**
 * File: DiagramWidthFitting.swift
 * -------------------------------
 * Layer: Core
 * Description: How a diagram fits the width its container has, as Pele's common/fit-width.ts does: a chart whose plot
 *              gives up the overflow, a chart drawn to a capped width, a diagram turned to run down below a breakpoint,
 *              one laid out tightly, and the room a title may take.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

import CoreGraphics

/// Pele's width fitting as value-type helpers. Each takes the width the container has (`availableWidth`; nil, zero or
/// negative for no limit, as Pele's `maxWidth` left out) and a function that lays the diagram out once, so that every
/// diagram type decides what it lays out and these decide how often and how wide. Nothing here measures text or draws.
public enum DiagramWidthFitting {
    /// Below this width a container is too narrow for a diagram that runs across to be shown across, unless the
    /// caller gives another (Pele's `directionBreakpoint`).
    public static let defaultDirectionBreakpoint: CGFloat = 640
    /// Around a title on each side when the caller gives no padding (Pele's `padding`).
    public static let defaultPadding: CGFloat = 8
    /// The narrowest a title may be made to wrap.
    public static let narrowestTitleRoom: CGFloat = 80
    /// The width a title may take when the container has no limit.
    public static let unlimitedTitleRoom: CGFloat = 4000
    /// How many times a chart's plot is drawn again after the first narrow drawing before it is accepted as it is.
    public static let plotRedrawLimit = 3

    /// The width the container has, or nil when it has no limit: `availableWidth` given and above zero.
    public static func limit(_ availableWidth: CGFloat?) -> CGFloat? {
        guard let availableWidth, availableWidth > 0, availableWidth.isFinite else { return nil }
        return availableWidth
    }

    /// The width a title may take before it wraps: the container's less the padding on both sides, at least 80 points;
    /// 4,000 for a container without a limit.
    public static func titleRoom(availableWidth: CGFloat?, padding: CGFloat = defaultPadding) -> CGFloat {
        guard let available = limit(availableWidth) else { return unlimitedTitleRoom }
        return max(narrowestTitleRoom, available - 2 * padding)
    }

    /// The width of a chart drawn to a set width: its own (`natural`), or the container's less what the chart adds
    /// outside that width (`around`) when that is smaller, but not under `least` (or `natural` when that is smaller).
    public static func capWidth(availableWidth: CGFloat?, natural: CGFloat, least: CGFloat, around: CGFloat = 0) -> CGFloat {
        guard let available = limit(availableWidth) else { return natural }
        return max(min(least, natural), min(natural, available - around))
    }

    /// A chart whose plot can be any width, drawn so that the whole diagram fits the container. What surrounds the plot
    /// (labels, a legend) is only known once it is drawn, so the plot gives up the overflow and is drawn again, up to
    /// three times. `draw` lays the diagram out with a plot of the width it is given and says whether the chart did not
    /// fit at its own width, for a chart that then arranges itself differently. `width` reads a layout's whole width.
    public static func fitWidth<Layout, Failure: Error>(availableWidth: CGFloat?, natural: CGFloat, least: CGFloat, width: (Layout) -> CGFloat,
                                                        draw: (_ plot: CGFloat, _ narrow: Bool) throws(Failure) -> Layout) throws(Failure) -> Layout {
        var layout = try draw(natural, false)
        guard let available = limit(availableWidth), width(layout) > available else { return layout }
        let floor = min(least, natural)
        var plot = natural
        layout = try draw(plot, true)
        var round = 0
        while round < plotRedrawLimit, width(layout) > available, plot > floor {
            plot = max(floor, plot - (width(layout) - available))
            layout = try draw(plot, true)
            round += 1
        }
        return layout
    }

    /// A diagram that can run across or down: laid out across, and down instead when the container is under the
    /// breakpoint, across does not fit it, and down is narrower. `autoDirection` false keeps it across.
    public static func turnToFit<Layout, Failure: Error>(availableWidth: CGFloat?, autoDirection: Bool = true, directionBreakpoint: CGFloat? = nil,
                                                         width: (Layout) -> CGFloat,
                                                         draw: (_ down: Bool) throws(Failure) -> Layout) throws(Failure) -> Layout {
        let across = try draw(false)
        guard autoDirection, let available = limit(availableWidth), width(across) > available else { return across }
        let breakpoint = directionBreakpoint.flatMap { $0 > 0 ? $0 : nil } ?? defaultDirectionBreakpoint
        guard available < breakpoint else { return across }
        let down = try draw(true)
        return width(down) < width(across) ? down : across
    }

    /// A diagram laid out with room to spare, and tightly instead when that does not fit the container and tight is
    /// narrower.
    public static func tighten<Layout, Failure: Error>(availableWidth: CGFloat?, width: (Layout) -> CGFloat,
                                                       draw: (_ tight: Bool) throws(Failure) -> Layout) throws(Failure) -> Layout {
        let loose = try draw(false)
        guard let available = limit(availableWidth), width(loose) > available else { return loose }
        let tight = try draw(true)
        return width(tight) < width(loose) ? tight : loose
    }
}
