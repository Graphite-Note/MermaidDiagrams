/**
 * File: FlatFlowchartSubgraphs.swift
 * ----------------------------------
 * Layer: Core (design prototype, not for merging as is)
 * Description: Groups opened and ended as FlowchartParser and FlowchartDiagramBuilder open and end them, members
 *              kept as interned names in one list used as a stack, titles kept as ranges, and nested as
 *              FlowchartSubgraphNesting nests them, on name indexes in one working buffer instead of Strings and lists.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 24/11/2026
 */

extension FlatFlowchartReader {
    /// `subgraph id[title]`, `subgraph id ["title"]`, `subgraph "title"` or `subgraph title words`.
    mutating func readSubgraphOpening() {
        skipSpaces()
        var lookahead = position
        while lookahead < bytes.count {
            let byte = bytes.base[lookahead]
            if MermaidByte.isIdentifierByte(byte) || (byte == MermaidByte.hyphen && lookahead > position && MermaidByte.isIdentifierByte(bytes[lookahead + 1])) {
                lookahead += 1
            } else {
                break
            }
        }
        if lookahead > position {
            let identifier = FlatTextRange(start: Int32(position), end: Int32(lookahead))
            while MermaidByte.isSpace(bytes[lookahead]) { lookahead += 1 }
            if bytes[lookahead] == MermaidByte.openingBracket {
                let saved = position
                position = lookahead + 1
                if let (title, _) = try? readText(closedBy: FlatClosings("]"), state: .text) {
                    openSubgraph(identifier: identifier, title: title)
                    return
                }
                position = saved
            }
        }
        let wordsStart = position
        skipStatement()
        var trimmedStart = wordsStart
        var trimmedEnd = position
        while trimmedStart < trimmedEnd, MermaidByte.isWhitespace(bytes.base[trimmedStart]) { trimmedStart += 1 }
        while trimmedEnd > trimmedStart, MermaidByte.isWhitespace(bytes.base[trimmedEnd - 1]) { trimmedEnd -= 1 }
        var wordsEnd = position
        if wordsEnd > wordsStart, bytes.base[wordsEnd - 1] == MermaidByte.carriageReturn { wordsEnd -= 1 }
        let endsWithSpace = wordsEnd > wordsStart && MermaidByte.isWhitespace(bytes.base[wordsEnd - 1])
        let isASCII = !(trimmedStart..<trimmedEnd).contains { index in bytes.base[index] >= 0x80 }
        guard isASCII else { return openSubgraphWrittenBeyondASCII(from: trimmedStart, to: trimmedEnd, endsWithSpace: endsWithSpace) }
        // FlowchartTextSyntax.unquoted on bytes: `"…"`, and inside it "`…`", taken off.
        var start = trimmedStart
        var end = trimmedEnd
        var form = DiagramLabelDecoder.Form.plain
        if end - start >= 2, bytes.base[start] == MermaidByte.quotationMark, bytes.base[end - 1] == MermaidByte.quotationMark {
            start += 1
            end -= 1
            if end - start >= 2, bytes.base[start] == MermaidByte.graveAccent, bytes.base[end - 1] == MermaidByte.graveAccent {
                start += 1
                end -= 1
                form = .markdown
            }
        }
        let written = FlatTextRange(start: Int32(start), end: Int32(end))
        let title = writtenLabel(written, form: form)
        let isOneWord = end > start && !(start..<end).contains { index in Self.isASCIIWhitespace(bytes.base[index]) } && !endsWithSpace
        openSubgraph(identifier: isOneWord ? written : nil, title: title)
    }

    /// The words of a group's opening beyond ASCII, read through String as FlowchartParser reads them.
    private mutating func openSubgraphWrittenBeyondASCII(from start: Int, to end: Int, endsWithSpace: Bool) {
        let written = FlowchartTextSyntax.unquoted(string(from: start, to: end))
        let title = decoded(DiagramLabelDecoder.label(from: written.text, form: written.form))
        let isOneWord = !written.text.isEmpty && !written.text.contains(where: \.isWhitespace) && !endsWithSpace
        guard isOneWord else { return openSubgraph(identifier: nil, title: title) }
        // The word's bytes stand in the text, inside any quotation marks and grave accents the unquoting took off.
        let removed = (end - start - written.text.utf8.count) / 2
        openSubgraph(identifier: FlatTextRange(start: Int32(start + removed), end: Int32(end - removed)), title: title)
    }

    private mutating func openSubgraph(identifier: FlatTextRange?, title: FlatLabel) {
        let writtenName = identifier.map { range in Int32(intern(range)) } ?? -1
        openSubgraphs.append(FlatOpenSubgraph(writtenName: writtenName, writtenRange: identifier ?? FlatTextRange(start: 0, end: 0), title: title,
                                              openingOrder: openedSubgraphCount, serial: openedSubgraphCount, direction: nil,
                                              membersStart: Int32(openMembers.count)))
        openedSubgraphCount += 1
    }

    /// `subGraph` and the number, interned from the side bytes.
    private mutating func internGeneratedName(_ number: Int) -> Int {
        let start = sideBytes.count
        sideBytes.append(contentsOf: [0x73, 0x75, 0x62, 0x47, 0x72, 0x61, 0x70, 0x68])
        var digits = number
        let digitsStart = sideBytes.count
        repeat {
            sideBytes.append(UInt8(truncatingIfNeeded: 0x30 + digits % 10))
            digits /= 10
        } while digits > 0
        sideBytes[digitsStart...].reverse()
        let length = sideBytes.count - start
        return intern(FlatTextRange(start: ~Int32(start), end: ~Int32(start) + Int32(length)))
    }

    /// Ends the innermost group (FlowchartDiagramBuilder.closeSubgraph); false when none is open.
    mutating func closeSubgraph() -> Bool {
        guard let group = openSubgraphs.popLast() else { return false }
        let generatedNumber = group.writtenName >= 0 ? -1 : Int32(endedSubgraphCount)
        let identifierName = group.writtenName >= 0 ? group.writtenName : Int32(internGeneratedName(endedSubgraphCount))
        endedSubgraphCount += 1
        let existing = names[Int(identifierName)].endedSubgraphIndex
        // A group ended again under the same identifier takes the new members after its own: its members move to the
        // list's end first when another group's stand after them.
        if existing >= 0, Int(endedSubgraphs[Int(existing)].membersStart + endedSubgraphs[Int(existing)].membersCount) != endedMembers.count {
            let moved = endedSubgraphs[Int(existing)]
            let newStart = Int32(endedMembers.count)
            for place in Int(moved.membersStart)..<Int(moved.membersStart + moved.membersCount) { endedMembers.append(endedMembers[place]) }
            endedSubgraphs[Int(existing)].membersStart = newStart
        }
        let membersStart = Int32(endedMembers.count)
        for place in Int(group.membersStart)..<openMembers.count {
            let name = openMembers[place]
            if !names[Int(name)].isTaken, name != identifierName { endedMembers.append(name) }
        }
        openMembers.removeSubrange(Int(group.membersStart)...)
        for place in Int(membersStart)..<endedMembers.count { names[Int(endedMembers[place])].isTaken = true }
        let addedCount = Int32(endedMembers.count) - membersStart
        if existing >= 0 {
            endedSubgraphs[Int(existing)].membersCount += addedCount
        } else {
            names[Int(identifierName)].endedSubgraphIndex = Int32(endedSubgraphs.count)
            endedSubgraphs.append(FlatEndedSubgraph(nameIndex: identifierName, writtenRange: group.writtenRange, generatedNumber: generatedNumber,
                                                    title: group.title, direction: group.direction, openingOrder: group.openingOrder,
                                                    membersStart: membersStart, membersCount: addedCount))
        }
        if !openSubgraphs.isEmpty {
            openSubgraphs[openSubgraphs.count - 1].hasClosedChild = true
            listMember(Int(identifierName), in: openSubgraphs[openSubgraphs.count - 1])
        }
        return true
    }

    /// `direction TB` inside a group sets its direction and the rest of the line is not read; else it is counted.
    mutating func readDirectionStatement() {
        var lookahead = position
        while MermaidByte.isSpace(bytes[lookahead]) { lookahead += 1 }
        if !openSubgraphs.isEmpty {
            let wordStart = lookahead
            while MermaidByte.isLetter(bytes[lookahead]) { lookahead += 1 }
            if lookahead - wordStart == 2, let direction = Self.subgraphDirection(bytes[wordStart], bytes[wordStart + 1]) {
                openSubgraphs[openSubgraphs.count - 1].direction = direction
                position = lookahead
                skipToEndOfLine()
                return
            }
        }
        skipStatement()
        document.unappliedStatementCount += 1
    }

    private static func subgraphDirection(_ first: UInt8, _ second: UInt8) -> FlowchartDirection? {
        switch (first, second) {
        case (0x54, 0x42), (0x54, 0x44): .topToBottom
        case (0x42, 0x54): .bottomToTop
        case (0x4C, 0x52): .leftToRight
        case (0x52, 0x4C): .rightToLeft
        default: nil
        }
    }

    // MARK: Nesting

    /// FlowchartSubgraphNesting.subgraphs on name indexes, every working list a part of one buffer on the stack: parents,
    /// children (a range of the child list per group, a child lifted out of a loop marked rather than removed), the
    /// reachability marks, the preorder and each group's place in it.
    mutating func nestSubgraphs() {
        let groupCount = endedSubgraphs.count
        guard groupCount > 0 else { return }
        let childCapacity = endedMembers.count
        withUnsafeTemporaryAllocation(of: Int32.self, capacity: groupCount * 7 + childCapacity + 1) { buffer in
            let parents = UnsafeMutableBufferPointer(rebasing: buffer[0..<groupCount])
            let childStarts = UnsafeMutableBufferPointer(rebasing: buffer[groupCount..<groupCount * 2 + 1])
            let marks = UnsafeMutableBufferPointer(rebasing: buffer[(groupCount * 2 + 1)..<(groupCount * 3 + 1)])
            let order = UnsafeMutableBufferPointer(rebasing: buffer[(groupCount * 3 + 1)..<(groupCount * 4 + 1)])
            let place = UnsafeMutableBufferPointer(rebasing: buffer[(groupCount * 4 + 1)..<(groupCount * 5 + 1)])
            let stack = UnsafeMutableBufferPointer(rebasing: buffer[(groupCount * 5 + 1)..<(groupCount * 7 + 1)])
            let children = UnsafeMutableBufferPointer(rebasing: buffer[(groupCount * 7 + 1)...])
            // Bit 0 of a mark: reachable; bit 1: lifted out of its former parent's children.
            for group in 0..<groupCount {
                parents[group] = -1
                marks[group] = 0
            }
            var childCount = 0
            for group in 0..<groupCount {
                childStarts[group] = Int32(childCount)
                let ended = endedSubgraphs[group]
                for place in Int(ended.membersStart)..<Int(ended.membersStart + ended.membersCount) {
                    let child = names[Int(endedMembers[place])].endedSubgraphIndex
                    guard child >= 0 else { continue }
                    parents[Int(child)] = Int32(group)
                    children[childCount] = child
                    childCount += 1
                }
            }
            childStarts[groupCount] = Int32(childCount)
            func markReachable(from root: Int) {
                var depth = 0
                stack[0] = Int32(root)
                depth = 1
                while depth > 0 {
                    depth -= 1
                    let group = Int(stack[depth])
                    guard marks[group] & 1 == 0 else { continue }
                    marks[group] |= 1
                    for place in Int(childStarts[group])..<Int(childStarts[group + 1]) {
                        let child = Int(children[place])
                        // A child lifted away from this group is no longer among its children.
                        if marks[child] & 2 != 0, parents[child] != Int32(group) { continue }
                        if depth == stack.count { break }
                        stack[depth] = Int32(child)
                        depth += 1
                    }
                }
            }
            for group in 0..<groupCount where parents[group] < 0 { markReachable(from: group) }
            for group in stride(from: groupCount - 1, through: 0, by: -1) where marks[group] & 1 == 0 {
                if parents[group] >= 0 { marks[group] |= 2 }
                parents[group] = -1
                markReachable(from: group)
            }
            var rootCount = 0
            for group in 0..<groupCount where parents[group] < 0 {
                order[rootCount] = Int32(group)
                rootCount += 1
            }
            var roots = UnsafeMutableBufferPointer(rebasing: order[0..<rootCount])
            roots.sort { first, second in
                endedSubgraphs[Int(first)].openingOrder < endedSubgraphs[Int(second)].openingOrder
            }
            // Preorder: the roots in their order, each group before its children in theirs.
            var orderCount = 0
            var depth = 0
            for root in stride(from: rootCount - 1, through: 0, by: -1) {
                stack[depth] = order[root]
                depth += 1
            }
            while depth > 0 {
                depth -= 1
                let group = Int(stack[depth])
                order[orderCount] = Int32(group)
                orderCount += 1
                var place = Int(childStarts[group + 1]) - 1
                while place >= Int(childStarts[group]) {
                    let child = Int(children[place])
                    if !(marks[child] & 2 != 0 && parents[child] != Int32(group)), depth < stack.count {
                        stack[depth] = Int32(child)
                        depth += 1
                    }
                    place -= 1
                }
            }
            for position in 0..<orderCount { place[Int(order[position])] = Int32(position) }
            let rare = document.rare
            rare.subgraphs.reserveCapacity(orderCount)
            for position in 0..<orderCount {
                let endedIndex = Int(order[position])
                let group = endedSubgraphs[endedIndex]
                let nodesStart = Int32(rare.subgraphMembers.count)
                for member in Int(group.membersStart)..<Int(group.membersStart + group.membersCount) {
                    let name = names[Int(endedMembers[member])]
                    if name.endedSubgraphIndex < 0, name.nodeIndex >= 0 { rare.subgraphMembers.append(name.nodeIndex) }
                }
                let childrenStart = Int32(rare.subgraphMembers.count)
                for childPlace in Int(childStarts[endedIndex])..<Int(childStarts[endedIndex + 1]) {
                    let child = Int(children[childPlace])
                    if marks[child] & 2 != 0, parents[child] != Int32(endedIndex) { continue }
                    rare.subgraphMembers.append(place[child])
                }
                let name = names[Int(group.nameIndex)]
                rare.subgraphs.append(FlatFlowchartSubgraph(writtenRange: group.writtenRange, generatedNumber: group.generatedNumber, title: group.title,
                                                            direction: group.direction, representingNodeIndex: name.nodeIndex, isCollapsed: name.isCollapsed,
                                                            nodeIndices: nodesStart..<childrenStart,
                                                            childSubgraphIndices: childrenStart..<Int32(rare.subgraphMembers.count)))
            }
        }
    }
}
