/**
 * File: FlatReadingPrototypeHooks.swift
 * -------------------------------------
 * Layer: Core (design prototype, not for merging as is)
 * Description: What the benchmark calls to time the prototype against the present reader and to check that the two
 *              read every input to the same model.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
#if canImport(Darwin)
import Darwin
#endif

extension FlatMermaidReadingPrototype {
    public struct CheckResult: CustomStringConvertible {
        public var readFlat = 0
        public var equal = 0
        public var different: [String] = []
        public var bailedOut = 0
        public var otherType = 0
        public var errorsAgreeing = 0
        public var errorsDisagreeing: [String] = []

        public var description: String {
            "read flat \(readFlat), equal \(equal), different \(different.count), bailed out \(bailedOut), other types \(otherType), "
                + "errors agreeing \(errorsAgreeing), errors disagreeing \(errorsDisagreeing.count)"
        }
    }

    /// Reads with the prototype and the present reader and compares the models (the prototype's made into the present one).
    public static func check(_ sources: [String]) -> CheckResult {
        var result = CheckResult()
        for source in sources {
            let bailOuts = bailOutCount
            let others = otherTypeCount
            let present: Result<MermaidDiagram, MermaidDiagramReadError> = Result { () throws(MermaidDiagramReadError) in
                try MermaidDiagramReader.read(source, limits: .standard)
            }
            let flat: Result<Outcome, MermaidDiagramReadError> = Result { () throws(MermaidDiagramReadError) in try read(source, limits: .standard) }
            if bailOutCount > bailOuts { result.bailedOut += 1 }
            if otherTypeCount > others { result.otherType += 1 }
            switch (present, flat) {
            case (.success(let diagram), .success(.flowchart(let document))):
                result.readFlat += 1
                let materialized = document.materialized()
                if case .flowchart(let expected) = diagram, expected == materialized {
                    result.equal += 1
                } else {
                    result.different.append(source)
                    if ProcessInfo.processInfo.environment["FLAT_DEBUG"] != nil, result.different.count <= 3 {
                        print("PRESENT:", diagram)
                        print("FLAT:   ", MermaidDiagram.flowchart(materialized))
                    }
                }
            case (.success(let diagram), .success(.presentReader(let other))):
                if diagram != other { result.different.append(source) }
            case (.failure(let expected), .failure(let error)):
                if expected == error { result.errorsAgreeing += 1 } else { result.errorsDisagreeing.append(source) }
            default:
                result.different.append(source)
            }
        }
        return result
    }

    /// Reads every source with the prototype; the model is dropped, as the benchmark's reading drops the present one.
    public static func readAll(_ sources: [String]) {
        for source in sources { _ = try? read(source, limits: .standard) }
    }

    /// Reads every source with the prototype and makes the present model from the flat one.
    public static func readAndMaterializeAll(_ sources: [String]) {
        for source in sources {
            if case .flowchart(let document)? = try? read(source, limits: .standard) { _ = document.materialized() }
        }
    }

    /// Reads every source with the present reader.
    public static func readAllWithPresentReader(_ sources: [String]) {
        for source in sources { _ = try? MermaidDiagramReader.read(source, limits: .standard) }
    }

    /// The present front end alone: preprocessing (with its copies), front matter, comments, the keyword.
    public static func presentFrontEnd(_ sources: [String]) {
        for source in sources {
            guard var (_, cursor) = try? MermaidDiagramReader.preprocessed(source) else { continue }
            cursor.skipWhitespace()
            _ = cursor.readWord()
        }
    }

    /// The prototype's front end alone: one scan of the String's own bytes and the passes' detectors; a text that needs a
    /// pass (or has front matter) goes through the present preprocessing.
    public static func flatFrontEnd(_ sources: [String]) {
        for source in sources {
            var text = source
            var lineCount = 1
            let needsPreprocessing = text.withUTF8 { buffer -> Bool in
                guard let base = buffer.baseAddress, buffer.count > 0 else { return true }
                if buffer.count >= 3, base[0] == 0xEF, base[1] == 0xBB, base[2] == 0xBF { return true }
                let found = bytesFound(buffer, lineCount: &lineCount)
                if found.contains(.zero) || found.contains(.carriageReturn) { return true }
                if found.contains(.lessThan), found.contains(.greaterThan), memmem(base, buffer.count, "=\"", 2) != nil { return true }
                if found.contains(.percent), memmem(base, buffer.count, "%%{", 3) != nil { return true }
                if found.contains(.hash), wouldDropColorSemicolon(buffer, after: "style") || wouldDropColorSemicolon(buffer, after: "classDef") { return true }
                var start = 0
                while start < buffer.count, base[start] == MermaidByte.space || base[start] == MermaidByte.tab { start += 1 }
                return start + 3 <= buffer.count && base[start] == MermaidByte.hyphen && base[start + 1] == MermaidByte.hyphen && base[start + 2] == MermaidByte.hyphen
            }
            if needsPreprocessing { _ = try? MermaidDiagramReader.preprocessed(source) }
        }
    }

    /// The prototype's reading made into the present model, for timing it with the present layout.
    public static func readMaterialized(_ source: String) -> MermaidDiagram? {
        switch try? read(source, limits: .standard) {
        case .flowchart(let document)?: .flowchart(document.materialized())
        case .presentReader(let diagram)?: diagram
        case nil: nil
        }
    }

    public static func resetCounts() {
        bailOutCount = 0
        otherTypeCount = 0
    }

    public static var counts: (bailedOut: Int, otherType: Int) { (bailOutCount, otherTypeCount) }
}
