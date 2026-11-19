/**
 * File: GitGraphLayoutError.swift
 * -------------------------------
 * Layer: Core
 * Description: Why a Git graph was not laid out.
 *
 * Authors: felixchvl, Bahey Shalash
 * Version: 0.1
 * Date: 19/11/2026
 */

/// Why a Git graph was not laid out.
public enum GitGraphLayoutError: Error, Equatable, Sendable {
    /// No longer thrown: Pele reads six options and ignores the others, and so does the layout. The case stays so that
    /// code that names it still compiles.
    case optionsNotApplied
}
