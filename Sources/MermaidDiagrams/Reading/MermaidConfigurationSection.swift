/**
 * File: MermaidConfigurationSection.swift
 * ---------------------------------------
 * Layer: Core
 * Description: One section of a diagram's options looked up option by option, in the front matter's tree and the
 *              directives' merged object, without building every option of the section.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 24/11/2026
 */

/// A section of a diagram's options (`themeVariables`), each option looked up when it is asked for as
/// `MermaidConfigurationOptions(section:in:).values` holds it: the directives' value when they set the option (null
/// leaving none), else the front matter's under `config:` and the section, and none at all when a directive gives the
/// section a value that is not an object. Only for options whose names hold no dot, which are kept by their name.
struct MermaidConfigurationSection {
    /// The front matter's tree and its mapping of the section, when it has one.
    private let tree: MermaidYAMLTree?
    private let frontMatterOptions: Int
    /// What the directives set under the section, nil when they set nothing there.
    private let directiveOptions: [String: DirectiveValue]?
    /// Whether a directive gives the section a value that is not an object, which leaves the type no option.
    private let isCleared: Bool

    init(named section: String, in cursor: MermaidTextCursor) {
        let read = cursor.readFrontMatter ?? MermaidReadFrontMatter(in: cursor.sourceBytes)
        if read.frontMatter != nil, let tree = read.tree, let configuration = tree.entry(of: MermaidYAMLTree.root, named: "config"),
           let options = tree.entry(of: configuration, named: section), tree.kind(of: options) == .mapping {
            self.tree = tree
            frontMatterOptions = options
        } else {
            tree = nil
            frontMatterOptions = -1
        }
        let directives = cursor.directiveConfiguration ?? MermaidDirectiveConfiguration.configuration(in: cursor.sourceBytes, from: read.frontMatter?.end ?? 0)
        switch directives[section] {
        case nil:
            directiveOptions = nil
            isCleared = false
        case .object(let options)?:
            directiveOptions = options
            isCleared = false
        case _?:
            directiveOptions = nil
            isCleared = true
        }
    }

    /// Whether no option is set: no front matter entry, and no directive's.
    var isEmpty: Bool {
        guard !isCleared else { return true }
        let hasFrontMatterOption = tree.map { tree in tree.children(of: frontMatterOptions).first { _ in true } != nil } ?? false
        return !hasFrontMatterOption && (directiveOptions?.isEmpty ?? true)
    }

    /// The option `name`, which holds no dot, as the section's options hold it; nil when none is set.
    func value(named name: String) -> MermaidConfigurationOptions.Value? {
        guard !isCleared else { return nil }
        if let directiveOptions, let value = directiveOptions[name] { return value.optionValue }
        guard let tree, let entry = tree.entry(of: frontMatterOptions, named: name) else { return nil }
        return tree.optionValue(of: entry)
    }
}
