/**
 * File: RequirementKeywordWords.swift
 * -----------------------------------
 * Layer: Core
 * Description: The requirement lexer's keywords told from a word's bytes: lowered and packed eight to a number, then
 *              compared with each keyword of the word's length, with no table to look up and no String made.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

extension RequirementKeywords {
    /// The keyword the word from `start` to `end`, of word characters (`RequirementLexer.isWordByte`), is in any case, or
    /// nil: its bytes lowered (setting bit 5 lowers a letter and leaves a digit; an underscore becomes a byte no keyword
    /// holds) and packed into three numbers, eight bytes each from its first, compared with the keywords of its length
    /// (`byLowercaseWord`'s, packed the same way).
    static func keyword(from start: Int, to end: Int, in bytes: UnsafeBufferPointer<UInt8>) -> RequirementTokenKind? {
        let length = end - start
        guard length >= 2, length <= longestKeywordLength, start >= 0, end <= bytes.count else { return nil }
        let first = packedLowered(bytes, from: start, to: min(end, start + 8))
        guard length > 8 else { return shortKeyword(length: length, first) }
        let second = packedLowered(bytes, from: start + 8, to: min(end, start + 16))
        let third = length > 16 ? packedLowered(bytes, from: start + 16, to: end) : 0
        return longKeyword(length: length, first, second, third)
    }

    /// The keyword of at most eight bytes, `first` packed, of `length`.
    private static func shortKeyword(length: Int, _ first: UInt64) -> RequirementTokenKind? {
        switch length {
        case 2:
            if first == 0x6469 { return .field(.identifier) } // id
            return nil
        case 3:
            if first == 0x776F6C { return .risk(.low) } // low
            return nil
        case 4:
            if first == 0x68676968 { return .risk(.high) } // high
            if first == 0x6B736972 { return .field(.risk) } // risk
            if first == 0x74736574 { return .verificationMethod(.test) } // test
            if first == 0x74786574 { return .field(.text) } // text
            if first == 0x65707974 { return .field(.type) } // type
            return nil
        case 5:
            if first == 0x7373616C63 { return .classAssignment } // class
            if first == 0x656C797473 { return .style } // style
            return nil
        case 6:
            if first == 0x736569706F63 { return .relation(.copies) } // copies
            if first == 0x666572636F64 { return .field(.documentReference) } // docref
            if first == 0x6D756964656D { return .risk(.medium) } // medium
            if first == 0x736563617274 { return .relation(.traces) } // traces
            return nil
        case 7:
            if first == 0x73657669726564 { return .relation(.derives) } // derives
            if first == 0x746E656D656C65 { return .element } // element
            if first == 0x73656E69666572 { return .relation(.refines) } // refines
            return nil
        case 8:
            if first == 0x736973796C616E61 { return .verificationMethod(.analysis) } // analysis
            if first == 0x6665647373616C63 { return .classDefinition } // classdef
            if first == 0x736E6961746E6F63 { return .relation(.contains) } // contains
            if first == 0x7365696669726576 { return .relation(.verifies) } // verifies
            return nil
        default:
            return nil
        }
    }

    /// The keyword of more than eight bytes, packed eight to a number, of `length`.
    private static func longKeyword(length: Int, _ first: UInt64, _ second: UInt64, _ third: UInt64) -> RequirementTokenKind? {
        switch length {
        case 9:
            if first == 0x6569667369746173 && second == 0x73 { return .relation(.satisfies) } // satisfies
            return nil
        case 10:
            if first == 0x6974636570736E69 && second == 0x6E6F { return .verificationMethod(.inspection) } // inspection
            return nil
        case 11:
            if first == 0x6D65726975716572 && second == 0x746E65 { return .requirementKind(.requirement) } // requirement
            return nil
        case 12:
            if first == 0x656D796669726576 && second == 0x646F6874 { return .field(.verificationMethod) } // verifymethod
            return nil
        case 13:
            if first == 0x7274736E6F6D6564 && second == 0x6E6F697461 { return .verificationMethod(.demonstration) } // demonstration
            return nil
        case 16:
            if first == 0x6F636E6769736564 && second == 0x746E69617274736E { return .requirementKind(.designConstraint) } // designconstraint
            return nil
        case 18:
            if first == 0x6D65726975716572 && second == 0x7267616964746E65 && third == 0x6D61 { return .diagramKeyword } // requirementdiagram
            return nil
        case 19:
            if first == 0x6C61636973796870 && second == 0x6D65726975716572 && third == 0x746E65 { return .requirementKind(.physicalRequirement) } // physicalrequirement
            return nil
        case 20:
            if first == 0x6361667265746E69 && second == 0x6572697571657265 && third == 0x746E656D { return .requirementKind(.interfaceRequirement) } // interfacerequirement
            return nil
        case 21:
            if first == 0x6E6F6974636E7566 && second == 0x7269757165726C61 && third == 0x746E656D65 { return .requirementKind(.functionalRequirement) } // functionalrequirement
            return nil
        case 22:
            if first == 0x616D726F66726570 && second == 0x697571657265636E && third == 0x746E656D6572 { return .requirementKind(.performanceRequirement) } // performancerequirement
            return nil
        default:
            return nil
        }
    }

    /// The bytes from `start` to `end`, at most eight, each with bit 5 set, the first in the lowest byte of the number:
    /// loaded at once where eight bytes follow `start`, else a byte at a time.
    @inline(__always)
    private static func packedLowered(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> UInt64 {
        let length = end - start
        if start + 8 <= bytes.count, let base = bytes.baseAddress {
            let loaded = UInt64(littleEndian: UnsafeRawPointer(base + start).loadUnaligned(as: UInt64.self))
            let mask: UInt64 = length >= 8 ? ~0 : (1 << UInt64(8 * length)) &- 1
            return (loaded | 0x2020_2020_2020_2020) & mask
        }
        var packed: UInt64 = 0
        var index = end
        while index > start {
            index -= 1
            packed = packed << 8 | UInt64(bytes[index] | 0x20)
        }
        return packed
    }
}
