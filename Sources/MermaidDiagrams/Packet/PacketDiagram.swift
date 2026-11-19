/**
 * File: PacketDiagram.swift
 * -------------------------
 * Layer: Core
 * Description: A Mermaid packet diagram as its text describes it: fields over consecutive bits, with their labels.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// A Mermaid packet diagram (`packet`, `packet-beta`): the fields of a packet, each over its bits, in the order they are
/// written. The fields are contiguous (a field starts one bit after the one before it, the first at bit 0), as Mermaid
/// requires; a field longer than a row is split across rows when the diagram is laid out.
public struct PacketDiagram: Equatable, Sendable {
    public internal(set) var fields: [PacketField]
    /// `title …` in the diagram, else `title:` in the front matter, or nil.
    public internal(set) var title: String?
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// The options its front matter and directives set.
    public internal(set) var options = PacketOptions()

    init(fields: [PacketField] = [], title: String? = nil, accessibilityTitle: String? = nil, accessibilityDescription: String? = nil) {
        self.fields = fields
        self.title = title
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }
}

/// One field of a packet: its label, as written (entity codes not yet read), and its first and last bit, both included.
public struct PacketField: Equatable, Sendable {
    public let label: String
    public let firstBit: Int
    public let lastBit: Int

    init(label: String, firstBit: Int, lastBit: Int) {
        self.label = label
        self.firstBit = firstBit
        self.lastBit = lastBit
    }

    /// How many bits the field covers.
    public var bitCount: Int { lastBit - firstBit + 1 }
}
