/**
 * File: FlowchartGroupReading.swift
 * ---------------------------------
 * Layer: Core
 * Description: Reads a flowchart's groups as they open and end: `subgraph` and its identifier and title, the names
 *              each group's statements write, which a group takes as it ends, and `direction` inside a group.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation

extension FlowchartParser {
    /// `subgraph id[title]`, `subgraph id ["title"]`, `subgraph "title"` or `subgraph title words`; words end at the
    /// line's end or a semicolon outside quotation marks, as statements do.
    mutating func readGroupOpening() {
        skipSpaces()
        var lookahead = position
        while lookahead < bytes.count, case let byte = bytes.base[lookahead],
              MermaidByte.isIdentifierByte(byte) || (byte == MermaidByte.hyphen && lookahead > position && MermaidByte.isIdentifierByte(bytes[lookahead + 1])) {
            lookahead += 1
        }
        if lookahead > position {
            let identifier = MermaidTextRange(start: position, end: lookahead)
            while MermaidByte.isSpace(bytes[lookahead]) { lookahead += 1 }
            if bytes[lookahead] == MermaidByte.openingBracket, lookahead < bytes.count {
                let wordsStart = position
                position = lookahead + 1
                // Brackets that do not close leave the line to be read as words.
                if let (title, _) = try? readText(closedBy: FlowchartClosings("]"), openedAt: lookahead) {
                    openGroup(identifier: identifier, title: title)
                    return
                }
                position = wordsStart
            }
        }
        readGroupOpeningWords()
    }

    /// The words of a group's opening: its title, and its identifier when it is one word. Pele's header text runs to the
    /// statement's end, spaces included, and names no group when it holds a space (flowchart/db.ts `addSubGraph`):
    /// `subgraph myTitle   ` is titled `myTitle` and named `subGraph0`.
    private mutating func readGroupOpeningWords() {
        let wordsStart = position
        skipStatement()
        let trimmed = trimmedRange(from: wordsStart, to: position)
        var wordsEnd = position
        if wordsEnd > wordsStart, bytes.base[wordsEnd - 1] == MermaidByte.carriageReturn { wordsEnd -= 1 }
        let endsWithSpace = wordsEnd > wordsStart && MermaidByte.isWhitespace(bytes.base[wordsEnd - 1])
        guard isASCII(trimmed) else {
            let written = FlowchartTextSyntax.unquoted(bytes.string(from: trimmed.lowerBound, to: trimmed.upperBound))
            let title = decoded(DiagramLabelDecoder.label(from: written.text, form: written.form))
            let isOneWord = !written.text.isEmpty && !written.text.contains(where: \.isWhitespace) && !endsWithSpace
            // The word's bytes stand in the text, inside any quotation marks and backticks unquoting took off.
            let removed = (trimmed.count - written.text.utf8.count) / 2
            return openGroup(identifier: isOneWord ? MermaidTextRange(start: trimmed.lowerBound + removed, end: trimmed.upperBound - removed) : nil,
                             title: title)
        }
        let (range, form) = unquotedRange(trimmed)
        let title = writtenLabel(range, form: form)
        let isOneWord = !range.isEmpty && !range.contains { index in Self.isASCIIWhitespace(bytes.base[index]) } && !endsWithSpace
        openGroup(identifier: isOneWord ? MermaidTextRange(start: range.lowerBound, end: range.upperBound) : nil, title: title)
    }

    /// Opens a group; `identifier` is nil when the text gives none, and Mermaid's is made as the group ends.
    private mutating func openGroup(identifier: MermaidTextRange?, title: FlowchartLabelReference) {
        let writtenName = identifier.map { range in Int32(lists.names.intern(range, in: bytes)) } ?? -1
        lists.openGroups.append(FlowchartOpenGroup(writtenName: writtenName, writtenIdentifier: identifier ?? .empty, title: title,
                                                   openingOrder: openedGroupCount, direction: nil, membersStart: Int32(lists.openMembers.count)))
        openedGroupCount += 1
    }

    /// Lists `name` as a member of the innermost open group, once.
    mutating func listMember(_ name: Int) {
        guard let group = lists.openGroups.last, lists.names.names[name].listingGroupSerial != group.openingOrder else { return }
        lists.openMembers.append(FlowchartOpenMember(name: Int32(name), previousListingSerial: lists.names.names[name].listingGroupSerial))
        lists.names.names[name].listingGroupSerial = group.openingOrder
    }

    /// Ends the innermost group: it takes the names written inside it that no group ended before it took, never its
    /// own, and its identifier joins the group around it. A group ended again under the same identifier adds these
    /// members to the first one's. False when no group is open.
    mutating func closeGroup() -> Bool {
        guard let group = lists.openGroups.popLast() else { return false }
        let generatedNumber = group.writtenName >= 0 ? -1 : Int32(endedGroupCount)
        let identifier = group.writtenName >= 0 ? Int(group.writtenName) : lists.names.intern(Array("subGraph\(endedGroupCount)".utf8), in: bytes)
        endedGroupCount += 1
        let runStart = lists.endedMembers.count
        for member in lists.openMembers[Int(group.membersStart)...] {
            let name = Int(member.name)
            lists.names.names[name].listingGroupSerial = member.previousListingSerial
            if !lists.names.names[name].isTaken, name != identifier { lists.endedMembers.append(member.name) }
        }
        lists.openMembers.removeSubrange(Int(group.membersStart)...)
        for place in runStart..<lists.endedMembers.count { lists.names.names[Int(lists.endedMembers[place])].isTaken = true }
        let run = Int32(lists.memberRuns.count)
        lists.memberRuns.append(FlowchartMemberRun(start: Int32(runStart), count: Int32(lists.endedMembers.count - runStart), next: -1))
        let existing = Int(lists.names.names[identifier].endedGroupIndex)
        if existing >= 0 {
            lists.memberRuns[Int(lists.endedGroups[existing].lastRun)].next = run
            lists.endedGroups[existing].lastRun = run
        } else {
            lists.names.names[identifier].endedGroupIndex = Int32(lists.endedGroups.count)
            lists.endedGroups.append(FlowchartEndedGroup(name: Int32(identifier), writtenIdentifier: group.writtenIdentifier, generatedNumber: generatedNumber,
                                                         title: group.title, direction: group.direction, openingOrder: group.openingOrder,
                                                         firstRun: run, lastRun: run))
        }
        listMember(identifier)
        return true
    }

    /// `direction TB` (or `TD`, `BT`, `LR`, `RL`) inside a group sets the group's direction, and the rest of the line
    /// is not read, as in Mermaid. Outside a group, or naming no direction, the statement is counted and left.
    mutating func readDirectionStatement() {
        var lookahead = position
        while MermaidByte.isSpace(bytes[lookahead]) { lookahead += 1 }
        if !lists.openGroups.isEmpty {
            let wordStart = lookahead
            while MermaidByte.isLetter(bytes[lookahead]) { lookahead += 1 }
            if lookahead - wordStart == 2, let direction = Self.groupDirection(bytes[wordStart], bytes[wordStart + 1]) {
                lists.openGroups[lists.openGroups.count - 1].direction = direction
                position = lookahead
                skipToEndOfLine()
                return
            }
        }
        skipStatement()
        unappliedStatementCount += 1
    }

    /// The words `direction` takes inside a group: Mermaid's, upper case only.
    private static func groupDirection(_ first: UInt8, _ second: UInt8) -> FlowchartDirection? {
        switch (first, second) {
        case (UInt8(ascii: "T"), UInt8(ascii: "B")), (UInt8(ascii: "T"), UInt8(ascii: "D")): .topToBottom
        case (UInt8(ascii: "B"), UInt8(ascii: "T")): .bottomToTop
        case (UInt8(ascii: "L"), UInt8(ascii: "R")): .leftToRight
        case (UInt8(ascii: "R"), UInt8(ascii: "L")): .rightToLeft
        default: nil
        }
    }

    /// Calls `body` with each member name of the ended group at `index`, in the order the group took them.
    func forEachMember(ofEndedGroup index: Int, _ body: (Int) -> Void) {
        var run = Int(lists.endedGroups[index].firstRun)
        while run >= 0 {
            let members = lists.memberRuns[run]
            for place in Int(members.start)..<Int(members.start + members.count) { body(Int(lists.endedMembers[place])) }
            run = Int(members.next)
        }
    }
}
