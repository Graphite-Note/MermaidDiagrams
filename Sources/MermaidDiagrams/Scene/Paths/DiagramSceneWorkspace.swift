/**
 * File: DiagramSceneWorkspace.swift
 * ---------------------------------
 * Layer: Core
 * Description: One thread's path lanes, kept between scenes: a recording hands lanes out of a pool whose blocks keep
 *              their size, takes back those a drawing made for a moment, last first, and all of them when it ends; a
 *              recording begun inside another gets a workspace of its own, blocks grown past a mebibyte are freed, and
 *              every lane is capped by the diagram limits, a lane past its cap remembered until the recording ends.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 25/11/2026
 */

import CoreGraphics
import Darwin

/// The path lanes of one thread (`current`), which a scene records its paths into. A recording
/// (`withRecording(limits:_:)`) hands out lanes (`makeLane()`, or one already holding a rectangle, a rounded rectangle or
/// an ellipse) from a pool of lane states that keep their blocks, so that a thread drawing scene after scene allocates
/// nothing once its lanes have grown; when the recording ends every lane is emptied and given back, and a lane used
/// afterwards fails debug builds' check. A recording begun while one runs on the same thread (a narrow scene read while
/// another scene records) gets a workspace of its own. Blocks grown past `largestKeptByteCount` are freed at the end of a
/// recording, and every grown block when the pool's blocks together take more, and each lane records at most
/// `elementLimit(for:)` verbs, so hostile input cannot grow it without bound.
final class DiagramSceneWorkspace {
    /// The lane states, each at its own address, which lanes point at; the first `handedOutCount` are in use. A
    /// workspace is used by one thread at a time (`current`, or one of a recording's own), so Swift's checks of
    /// exclusive access at run time are left out of the lane handed out for each shape.
    @exclusivity(unchecked) private var pool: [UnsafeMutablePointer<DiagramPathLaneState>] = []
    @exclusivity(unchecked) private var handedOutCount = 0
    private var isRecording = false
    private var elementLimit = DiagramSceneWorkspace.elementLimit(for: .standard)
    /// Whether a lane given back in this recording had gone past its element limit, which emptying it forgets.
    private var gaveBackOverflowedLane = false
    /// The number of the last lane handed out: each lane handed out gets the next, and a lane given back or ended
    /// with its recording gets 0, which no handle has, so that debug builds catch a handle used after its lane went back.
    private var generation: UInt32 = 0

    /// The most bytes a lane state keeps between recordings.
    static let largestKeptByteCount = 1 << 20
    /// The verbs a new or trimmed lane state has room for.
    private static let smallVerbCapacity = 32

    deinit {
        for state in pool {
            state.pointee.deallocate()
            state.deallocate()
        }
    }

    /// The most verbs a lane records under `limits`: room for every node, edge and layout point drawn as a few dozen
    /// elements, at most 2²⁴, far below what the scene's 32-bit counts hold.
    static func elementLimit(for limits: MermaidDiagramLimits) -> Int {
        let drawn = (limits.maximumNodeCount.clamped(atMost: 1 << 24) + limits.maximumEdgeCount.clamped(atMost: 1 << 24)
            + limits.maximumLayoutPointCount.clamped(atMost: 1 << 24)) * 64
        return min(max(drawn, 1 << 16), 1 << 24)
    }

    // MARK: The thread's workspace

    private static let threadKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { workspace in Unmanaged<DiagramSceneWorkspace>.fromOpaque(workspace).release() }
        return key
    }()

    /// The calling thread's workspace, made on its first use and freed when the thread ends.
    static var current: DiagramSceneWorkspace {
        if let stored = pthread_getspecific(threadKey) { return Unmanaged<DiagramSceneWorkspace>.fromOpaque(stored).takeUnretainedValue() }
        let workspace = DiagramSceneWorkspace()
        pthread_setspecific(threadKey, Unmanaged.passRetained(workspace).toOpaque())
        return workspace
    }

    /// Runs `body` with the thread's workspace recording, or with a workspace of its own when the thread's records
    /// already; every lane handed out is given back when `body` returns.
    static func withRecording<Result>(limits: MermaidDiagramLimits = .standard,
                                      _ body: (DiagramSceneWorkspace) throws -> Result) rethrows -> Result {
        let threadWorkspace = current
        let workspace = threadWorkspace.isRecording ? DiagramSceneWorkspace() : threadWorkspace
        workspace.beginRecording(limits: limits)
        defer { workspace.endRecording() }
        return try body(workspace)
    }

    private func beginRecording(limits: MermaidDiagramLimits) {
        isRecording = true
        gaveBackOverflowedLane = false
        elementLimit = Self.elementLimit(for: limits)
    }

    private func endRecording() {
        giveLanesBack(downTo: 0)
        if pooledByteCount > Self.largestKeptByteCount {
            for state in pool { state.pointee.trim(toAtMost: Self.smallVerbCapacity * Self.smallLaneByteCountPerVerb, verbCapacity: Self.smallVerbCapacity) }
        }
        isRecording = false
    }

    /// The bytes a small lane's blocks take for each verb they have room for: the verb and three points.
    private static let smallLaneByteCountPerVerb = MemoryLayout<DiagramPathVerb>.stride + 3 * MemoryLayout<CGPoint>.stride

    /// How many lanes this recording has handed out and not taken back.
    var handedOutLaneCount: Int { handedOutCount }

    /// Takes back the lanes handed out after `count` were, the last first: they are emptied, and their blocks serve the
    /// lanes handed out next. A drawing gives back the lanes it made for a moment once it has added them where they go.
    func giveLanesBack(downTo count: Int) {
        precondition(count <= handedOutCount, "lanes are given back in the order opposite to the one they were handed out in")
        for index in count..<handedOutCount {
            let state = pool[index]
            if state.pointee.hasOverflowed { gaveBackOverflowedLane = true }
            state.pointee.trim(toAtMost: Self.largestKeptByteCount, verbCapacity: Self.smallVerbCapacity)
            state.pointee.removeAll()
            state.pointee.generation = 0
        }
        handedOutCount = count
    }

    // MARK: Lanes

    /// An empty lane, valid until the recording ends.
    func makeLane() -> DiagramPathLane {
        precondition(isRecording, "lanes are made while the workspace records")
        if handedOutCount == pool.count {
            let state = UnsafeMutablePointer<DiagramPathLaneState>.allocate(capacity: 1)
            state.initialize(to: DiagramPathLaneState(verbCapacity: Self.smallVerbCapacity, elementLimit: elementLimit))
            pool.append(state)
        }
        let state = pool[handedOutCount]
        handedOutCount += 1
        if state.pointee.elementLimit != elementLimit {
            state.pointee.deallocate()
            state.initialize(to: DiagramPathLaneState(verbCapacity: Self.smallVerbCapacity, elementLimit: elementLimit))
        }
        generation &+= 1
        if generation == 0 { generation = 1 }
        state.pointee.generation = generation
        return DiagramPathLane(state: state)
    }

    /// A lane of a rectangle, as `CGPath(rect:transform: nil)` makes one.
    func rectangle(_ rect: CGRect) -> DiagramPathLane {
        let lane = makeLane()
        lane.addRect(rect)
        return lane
    }

    /// A lane of a rounded rectangle, as `CGPath(roundedRect:cornerWidth:cornerHeight:transform: nil)` makes one, the
    /// radii clamped to half the sides.
    func roundedRectangle(_ rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) -> DiagramPathLane {
        let lane = makeLane()
        lane.addRoundedRect(in: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
        return lane
    }

    /// A lane of an ellipse, as `CGPath(ellipseIn:transform: nil)` makes one.
    func ellipse(in rect: CGRect) -> DiagramPathLane {
        let lane = makeLane()
        lane.addEllipse(in: rect)
        return lane
    }

    /// Whether any lane handed out in this recording went past its element limit, given back since or not, which
    /// refuses the scene.
    var anyLaneOverflowed: Bool {
        if gaveBackOverflowedLane { return true }
        for index in 0..<handedOutCount where pool[index].pointee.hasOverflowed { return true }
        return false
    }

    /// The most verbs each lane of this recording holds.
    var laneElementLimit: Int { elementLimit }

    /// How many lane states the pool keeps, and how many bytes their blocks take, for tests.
    var pooledLaneCount: Int { pool.count }
    var pooledByteCount: Int { pool.reduce(0) { total, state in total + state.pointee.capacityByteCount } }
}

private extension Int {
    func clamped(atMost largest: Int) -> Int {
        Swift.max(0, Swift.min(self, largest))
    }
}
