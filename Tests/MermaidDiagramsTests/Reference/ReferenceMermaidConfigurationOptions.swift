/**
 * File: ReferenceMermaidConfigurationOptions.swift
 * ------------------------------------------------
 * Layer: Tests
 * Description: MermaidDiagrams 0.7.0's configuration options, frozen as the reference: the front matter's YAML read
 *              whole into a directive's values by the YAML reader, each directive's JSON read by JSONDecoder, merged,
 *              and a type's section kept by name and by path.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

import Foundation
@testable import MermaidDiagrams

/// The options a diagram gives its type, as 0.7.0's `MermaidConfigurationOptions` read them from the text as written.
struct ReferenceMermaidConfigurationOptions: Equatable {
    typealias Value = MermaidConfigurationOptions.Value

    private(set) var values: [String: Value] = [:]
    private(set) var nestedValues: [String: Value] = [:]

    /// The options under `config:` and `section:` in the front matter at the start of `bytes`, then those the
    /// directives after it set under `section`.
    init(section: String, in bytes: [UInt8]) {
        let frontMatter = MermaidFrontMatter.find(in: bytes)
        if let frontMatter, case .object(let document)? = MermaidYAMLDocument.value(of: frontMatter.bodyBytes) {
            if case .object(let configuration)? = document["config"], case .object(let options)? = configuration[section] {
                for (name, value) in options { record(value, named: name) }
            }
            if section == "gantt", let displayMode = document["displayMode"], MermaidYAMLDocument.isTruthy(displayMode) {
                record(.text(MermaidYAMLDocument.javaScriptText(displayMode)), named: "displayMode")
            }
        }
        let start = frontMatter?.end ?? 0
        guard MermaidPreprocessing.firstIndex(of: Array("%%{".utf8), in: bytes, from: min(start, bytes.count)) != nil,
              let sectionValue = Self.directiveConfiguration(in: bytes, from: start)[section] else { return }
        guard case .object(let directiveOptions) = sectionValue else {
            values = [:]
            nestedValues = [:]
            return
        }
        for (name, value) in directiveOptions { record(value, named: name) }
    }

    /// The options as the production type holds them.
    init(_ options: MermaidConfigurationOptions) {
        values = options.values
        nestedValues = options.nestedValues
    }

    private mutating func record(_ value: DirectiveValue, named name: String, depth: Int = 0) {
        if case .object(let object) = value {
            if !name.isEmpty { store(.collection, named: name) }
            guard depth < 64 else { return }
            for (key, entry) in object where !["__proto__", "constructor", "prototype"].contains(key) {
                record(entry, named: name.isEmpty ? key : name + "." + key, depth: depth + 1)
            }
        } else if let read = value.optionValue {
            store(read, named: name)
        } else if name.contains(".") {
            nestedValues.removeValue(forKey: name)
        } else {
            values.removeValue(forKey: name)
        }
    }

    private mutating func store(_ value: Value, named name: String) {
        guard !name.isEmpty else { return }
        if name.contains(".") { nestedValues[name] = value } else { values[name] = value }
    }

    /// Every `init` directive's object merged in their order, each read by `JSONDecoder`.
    static func directiveConfiguration(in bytes: [UInt8], from start: Int) -> [String: DirectiveValue] {
        var text = Array(bytes[min(start, bytes.count)...])
        for index in text.indices where text[index] == UInt8(ascii: "'") { text[index] = UInt8(ascii: "\"") }
        var configuration: [String: DirectiveValue] = [:]
        var position = 0
        while let match = MermaidDirectiveConfiguration.nextDirective(in: text, from: position) {
            position = max(match.end, match.start + 1)
            guard match.name == "init" || match.name == "initialize", let content = match.content,
                  let object = directiveObject(String(decoding: text[content], as: UTF8.self)) else { continue }
            merge(object, into: &configuration)
        }
        return configuration
    }

    /// A directive's content read by `JSONDecoder`, as 0.7.0 read it: nil when it is not an object.
    static func directiveObject(_ content: String) -> [String: DirectiveValue]? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .object(let object)? = try? JSONDecoder().decode(DirectiveValue.self, from: Data(trimmed.utf8)) else { return nil }
        return object
    }

    private static func merge(_ source: [String: DirectiveValue], into target: inout [String: DirectiveValue]) {
        for (key, value) in source where !["__proto__", "constructor", "prototype"].contains(key) {
            if case .object(let object) = value {
                var merged: [String: DirectiveValue] = [:]
                if case .object(let former) = target[key] { merged = former }
                merge(object, into: &merged)
                target[key] = .object(merged)
            } else {
                target[key] = value
            }
        }
    }
}
