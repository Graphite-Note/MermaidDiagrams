/**
 * File: MermaidConfigurationNumbers.swift
 * ---------------------------------------
 * Layer: Core
 * Description: Reads a number option as Pele's charts do: a number of at least its least, cut to its largest, else its default.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

extension MermaidConfigurationOptions {
    /// The number the option `name` holds when it is one of at least `least`, cut to `largest`; else `fallback`. A value
    /// of another kind, or a number below its least, is left at the default, as Pele's charts read their options.
    func boundedNumber(_ name: String, fallback: Double, least: Double, largest: Double) -> Double {
        guard case .number(let value) = values[name], value >= least else { return fallback }
        return min(value, largest)
    }
}
