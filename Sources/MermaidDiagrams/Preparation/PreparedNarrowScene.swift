/**
 * File: PreparedNarrowScene.swift
 * -------------------------------
 * Layer: Core
 * Description: A prepared diagram's scene for a narrow column, laid out the first time it is read and kept, behind a lock
 *              so that a prepared diagram read from several threads lays it out once.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 */

import Foundation

/// The narrow scene of a prepared diagram: either made already, or the work that makes it, run on the first read and then
/// let go, so that a diagram shown only in columns it fits never lays out its narrow form, and a diagram whose narrow scene
/// is read keeps the scene and no longer the diagram it was made from. The work holds the diagram as written (it turns it
/// when it runs), the preparation's context (typography, limits, moment and time zone) and the regular scene's size, never
/// a layout. Reads from several threads wait for one another: the first lays the scene out, the others get what it made.
final class PreparedNarrowScene: @unchecked Sendable {
    private let lock = NSLock()
    /// The work, until it has run: nil once the scene is made (`made` then holds it, nil when the work made none).
    private var layingOut: (@Sendable () -> DiagramScene?)?
    private var made: DiagramScene?

    /// A scene made already (nil for none).
    init(made scene: DiagramScene?) {
        made = scene
    }

    /// A scene `layingOut` makes on the first read.
    init(layingOut: @escaping @Sendable () -> DiagramScene?) {
        self.layingOut = layingOut
    }

    /// The scene, laid out on the first read. The work never reads this store again, so holding the lock while it runs
    /// cannot wait on itself.
    var scene: DiagramScene? {
        lock.lock()
        defer { lock.unlock() }
        if let layingOut {
            made = layingOut()
            self.layingOut = nil
        }
        return made
    }

    /// Whether the scene is still to be laid out: what a test reads to see that a read was not needed.
    var isPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return layingOut != nil
    }
}
