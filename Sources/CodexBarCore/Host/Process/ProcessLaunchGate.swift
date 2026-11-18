import Foundation

/// Serializes `Process.run()` with the creation of the pipes that launches hand to their children.
///
/// On Linux, swift-corelibs-foundation (6.3) emulates `POSIX_SPAWN_CLOEXEC_DEFAULT`: `run()` lists the descriptors
/// that are open while it builds the spawn file actions and closes only those in the child. A descriptor that
/// another thread opens before `posix_spawn` returns stays open in the child for its whole life. That includes the
/// socket through which Foundation notices another launch's exit and the pipes of another launch, so a long-running
/// child hides the exit and the end of output of an unrelated short one until it exits itself.
///
/// Launches and pipe creations that go through this gate never overlap, so no descriptor of one gated launch can
/// reach the child of another. Darwin spawns with `POSIX_SPAWN_CLOEXEC_DEFAULT`, so the gate does nothing there.
package enum ProcessLaunchGate {
    #if os(Linux)
    private static let lock = NSRecursiveLock()
    #endif

    /// Runs `body` while no gated launch or pipe creation can start.
    package static func withLock<T>(_ body: () throws -> T) rethrows -> T {
        #if os(Linux)
        self.lock.lock()
        defer { self.lock.unlock() }
        #endif
        return try body()
    }

    /// Launches `process` while no other gated launch or pipe creation is in progress.
    package static func run(_ process: Process) throws {
        try self.withLock { try process.run() }
    }

    /// A pipe whose descriptors cannot be inherited by a concurrent gated launch.
    package static func makePipe() -> Pipe {
        self.withLock { Pipe() }
    }
}
