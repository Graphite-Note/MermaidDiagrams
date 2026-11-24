/**
 * File: DiagramTextReflection.swift
 * ---------------------------------
 * Layer: Core
 * Description: How a label and a text block show themselves to a debugger, a dump or a mirror: as the lines, spans,
 *              widths and runs they hold, as when they held them as Strings and lists, never as storage offsets.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

extension DiagramLabel: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, children: ["lines": lines, "spans": spans as Any, "isReadWithoutMarkup": isReadWithoutMarkup], displayStyle: .struct)
    }
}

extension DiagramTextBlock: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, children: ["lines": lines, "lineWidths": lineWidths, "fontSize": fontSize, "lineHeight": lineHeight, "center": center,
                                "lineRuns": lineRuns as Any],
               displayStyle: .struct)
    }
}
