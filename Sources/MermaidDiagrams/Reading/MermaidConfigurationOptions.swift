/**
 * File: MermaidConfigurationOptions.swift
 * ---------------------------------------
 * Layer: Core
 * Description: The options a diagram's front matter and its `%%{init: …}%%` directives give its type.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.6
 * Date: 23/11/2026
 */

import Foundation

/// The options a diagram gives its type, as Pele reads them: first the front matter's under `config:` and the type's
/// section (`config:`, then `sankey:`, then `showValues: false`), read as YAML by the port of Pele's reader
/// (`MermaidFrontMatter`, `MermaidYAMLDocument`), then those of each `%%{init: …}%%` directive over them
/// (`MermaidDirectiveConfiguration`). Each option's value is a Boolean (`true`, `false`), a number, text, or a
/// collection (a mapping, whose options are kept by their path as well, or a sequence), as `Value` holds them.
struct MermaidConfigurationOptions {
    enum Value: Equatable {
        case boolean(Bool)
        case number(Double)
        case text(String)
        case collection
    }

    private(set) var values: [String: Value] = [:]
    /// The options inside an option that is a mapping, by their path from the section with the names joined by dots
    /// (`xAxis.showLabel`, `nodeColors.Coal`); the mapping itself is a collection in `values`, or here when it is
    /// itself nested.
    private(set) var nestedValues: [String: Value] = [:]

    /// The options under `config:` and then `section:` in the front matter at the start of `bytes`, with those the
    /// directives after it set under `section` over them; none without either. A section that is not a mapping gives
    /// no option, as a directive's does.
    init(section: String, in bytes: [UInt8]) {
        self.init(section: section, in: bytes, frontMatter: MermaidReadFrontMatter(in: bytes))
    }

    /// The options of the cursor's text, from the front matter the reader already read when it has.
    init(section: String, in cursor: MermaidTextCursor) {
        self.init(section: section, in: cursor.sourceBytes, frontMatter: cursor.readFrontMatter ?? MermaidReadFrontMatter(in: cursor.sourceBytes))
    }

    private init(section: String, in bytes: [UInt8], frontMatter read: MermaidReadFrontMatter) {
        if read.frontMatter != nil, case .object(let document)? = read.value {
            if case .object(let configuration)? = document["config"], case .object(let options)? = configuration[section] {
                for (name, value) in options { record(value, named: name) }
            }
            // The front matter's own `displayMode`, when it is truthy, is the Gantt chart's over its `config:`, as Pele
            // moves it there.
            if section == Self.ganttSection, let displayMode = document["displayMode"], MermaidYAMLDocument.isTruthy(displayMode) {
                record(.text(MermaidYAMLDocument.javaScriptText(displayMode)), named: "displayMode")
            }
        }
        MermaidDirectiveConfiguration.apply(section: section, in: bytes, from: read.frontMatter?.end ?? 0, to: &self)
    }

    /// The section whose options take the front matter's own `displayMode`.
    private static let ganttSection = "gantt"

    /// Leaves no option.
    mutating func removeAll() {
        values = [:]
        nestedValues = [:]
    }

    /// Records `value` under `name` (empty for the section itself): a scalar as it is; a mapping as a collection and,
    /// each entry by its path, its options; an array as a collection.
    mutating func record(_ value: DirectiveValue, named name: String, depth: Int = 0) {
        if case .object(let object) = value {
            if !name.isEmpty { store(.collection, named: name) }
            guard depth < Self.deepestNesting else { return }
            for (key, entry) in object where !Self.prototypeKeys.contains(key) {
                record(entry, named: name.isEmpty ? key : name + "." + key, depth: depth + 1)
            }
        } else if let read = value.optionValue {
            store(read, named: name)
        } else {
            removeValue(named: name)
        }
    }

    private mutating func record(_ value: Value, named name: String) {
        store(value, named: name)
    }

    private mutating func store(_ value: Value, named name: String) {
        guard !name.isEmpty else { return }
        if Self.isPath(name) { nestedValues[name] = value } else { values[name] = value }
    }

    private mutating func removeValue(named name: String) {
        if Self.isPath(name) { nestedValues.removeValue(forKey: name) } else { values.removeValue(forKey: name) }
    }

    /// Whether the name holds a dot, looked for in its bytes before its characters.
    private static func isPath(_ name: String) -> Bool {
        name.utf8.contains(UInt8(ascii: ".")) && name.contains(".")
    }

    private static let prototypeKeys: Set<String> = ["__proto__", "constructor", "prototype"]
    /// How deep a mapping's options are kept by their path, as deep as Pele's YAML reader nests collections.
    private static let deepestNesting = 64
}
