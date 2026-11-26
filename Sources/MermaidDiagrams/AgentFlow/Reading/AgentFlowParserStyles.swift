/**
 * File: AgentFlowParserStyles.swift
 * ---------------------------------
 * Layer: Core
 * Description: An agent flow's style lists, `linkStyle` statements and `click` statements, as Pele's parser.ts reads
 *              them.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 26/11/2026
 */

extension AgentFlowParser {
    /// Styles separated by commas, each its tokens run together.
    mutating func styles() throws(MermaidDiagramReadError) -> [MermaidTextRange] {
        var styles = [try style()]
        while current == .comma {
            index += 1
            styles.append(try style())
        }
        return styles
    }

    private mutating func style() throws(MermaidDiagramReadError) -> MermaidTextRange {
        guard Self.styleTokens.contains(current) else { throw failure(expecting: "'NODE_STRING', 'NUM', 'COLON', 'BRKT'") }
        let first = index
        index += 1
        while Self.styleTokens.contains(current) { index += 1 }
        return joinedText(from: first, to: index)
    }

    /// `linkStyle default|N,M [interpolate curve] [styles]`.
    mutating func linkStyleStatement() throws(MermaidDiagramReadError) {
        let line = builder.line(of: span(from: index, to: index))
        index += 1
        _ = try expect(.space)
        var positions: [MermaidTextRange]
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
            var tooltip: MermaidTextRange?
            if current == .space {
                index += 1
                tooltip = try expect(.string)
            }
            builder.setClass(identifier, className: builder.constant(.clickable))
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
                builder.setClass(identifier, className: builder.constant(.clickable))
                builder.setTooltip(identifier, tooltip: tooltip)
            } else {
                builder.setClass(identifier, className: builder.constant(.clickable))
            }
        }
    }

    /// After a click's link: nothing, a target, or a tooltip and an optional target.
    private mutating func linkTail(_ identifier: MermaidTextRange, url: MermaidTextRange) throws(MermaidDiagramReadError) {
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
