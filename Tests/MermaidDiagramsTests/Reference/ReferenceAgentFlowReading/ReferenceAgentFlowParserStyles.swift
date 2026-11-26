/**
 * File: ReferenceAgentFlowParserStyles.swift
 * ------------------------------------------
 * Layer: Tests
 * Description: 0.7.0's agent flow reader on UTF-16 code units (AgentFlowParserStyles.swift), kept unchanged but for its
 *              names as the reference the reader on bytes is compared with (AgentFlowReadingEquivalenceTests).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

@testable import MermaidDiagrams

extension ReferenceAgentFlowParser {
    /// Styles separated by commas, each its tokens run together.
    mutating func styles() throws(MermaidDiagramReadError) -> [String] {
        var styles = [try style()]
        while current == .comma {
            index += 1
            styles.append(try style())
        }
        return styles
    }

    private mutating func style() throws(MermaidDiagramReadError) -> String {
        guard Self.styleTokens.contains(current) else { throw failure(expecting: "'NODE_STRING', 'NUM', 'COLON', 'BRKT'") }
        var style = text(at: index)
        index += 1
        while Self.styleTokens.contains(current) {
            style += text(at: index)
            index += 1
        }
        return style
    }

    /// `linkStyle default|N,M [interpolate curve] [styles]`.
    mutating func linkStyleStatement() throws(MermaidDiagramReadError) {
        let line = builder.line(of: span(from: index, to: index))
        index += 1
        _ = try expect(.space)
        var positions: [String]
        if current == .defaultKeyword {
            positions = [text(at: index)]
            index += 1
        } else {
            positions = [try expect(.number, also: "'DEFAULT'")]
            while current == .comma {
                index += 1
                positions.append(try expect(.number))
            }
        }
        _ = try expect(.space)
        guard current == .interpolate else {
            try builder.updateLink(positions: positions, styles: try styles(), line: line)
            return
        }
        index += 1
        _ = try expect(.space)
        let interpolation = try joined(Self.alphanumericTokens)
        if current == .space {
            index += 1
            let styles = try styles()
            try builder.updateLinkInterpolation(positions: positions, interpolation: interpolation, line: line)
            try builder.updateLink(positions: positions, styles: styles, line: line)
        } else {
            try builder.updateLinkInterpolation(positions: positions, interpolation: interpolation, line: line)
        }
    }

    /// `click id callback`, `click id call callback(arguments)`, `click id href "url"`, `click id "url"`, each with an
    /// optional tooltip and target. Callbacks are never run: the node is only marked clickable, as in Mermaid's strict
    /// mode.
    mutating func clickStatement() throws(MermaidDiagramReadError) {
        let identifier = text(at: index)
        index += 1
        switch current {
        case .callbackName:
            index += 1
            if current == .callbackArguments { index += 1 }
            var tooltip: String?
            if current == .space {
                index += 1
                tooltip = try expect(.string)
            }
            builder.setClass(identifier, className: "clickable")
            if let tooltip { builder.setTooltip(identifier, tooltip: tooltip) }
        case .hyperlinkReference:
            index += 1
            try linkTail(identifier, url: try expect(.string))
        case .string:
            let url = text(at: index)
            index += 1
            try linkTail(identifier, url: url)
        default:
            _ = try joined(Self.alphanumericTokens)
            if current == .space {
                index += 1
                let tooltip = try expect(.string)
                builder.setClass(identifier, className: "clickable")
                builder.setTooltip(identifier, tooltip: tooltip)
            } else {
                builder.setClass(identifier, className: "clickable")
            }
        }
    }

    /// After a click's link: nothing, a target, or a tooltip and an optional target.
    private mutating func linkTail(_ identifier: String, url: String) throws(MermaidDiagramReadError) {
        guard current == .space else {
            builder.setLink(identifier, url: url)
            return
        }
        index += 1
        if current == .linkTarget {
            builder.setLink(identifier, url: url, target: text(at: index))
            index += 1
            return
        }
        let tooltip = try expect(.string, also: "'LINK_TARGET'")
        if current == .space {
            index += 1
            builder.setLink(identifier, url: url, target: try expect(.linkTarget))
        } else {
            builder.setLink(identifier, url: url)
        }
        builder.setTooltip(identifier, tooltip: tooltip)
    }
}
