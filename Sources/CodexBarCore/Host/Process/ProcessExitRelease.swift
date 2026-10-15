import Foundation

package enum ProcessExitRelease {
    /// Lets Foundation drop a launched `Process` once its child has exited. Never blocks the caller.
    ///
    /// swift-corelibs-foundation gives every launched `Process` a run-loop source whose context retains the
    /// process, and only `waitUntilExit()` clears it. A child observed through `terminationHandler` or `isRunning`
    /// alone therefore never deallocates on Linux, which pins its `Pipe` objects and their read descriptors until
    /// a long-running `codexbar serve` hits EMFILE. `waitUntilExit()` returns immediately for an exited child, so
    /// it is deferred until then instead of spinning a run loop, and serialized because callers may ask twice.
    package static func afterExit(_ process: Process) {}
}
