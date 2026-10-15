import Foundation

package final class ProcessPipeCapture: @unchecked Sendable {
    package static let defaultMaxBytes = 1 * 1024 * 1024

    private let handle: FileHandle
    private let onData: (@Sendable () -> Void)?
    private let maxBytes: Int
    private let condition = NSCondition()
    private var data = Data()
    private var activeCallbacks = 0
    private var isFinished = false
    private var didReachEOF = false
    private var isStopping = false
    private var continuation: CheckedContinuation<Void, Never>?

    package convenience init(
        pipe: Pipe,
        maxBytes: Int = ProcessPipeCapture.defaultMaxBytes,
        onData: (@Sendable () -> Void)? = nil)
    {
        self.init(handle: pipe.fileHandleForReading, maxBytes: maxBytes, onData: onData)
    }

    package init(
        handle: FileHandle,
        maxBytes: Int = ProcessPipeCapture.defaultMaxBytes,
        onData: (@Sendable () -> Void)? = nil)
    {
        self.handle = handle
        self.maxBytes = max(0, maxBytes)
        self.onData = onData
    }

    package func start() {
        self.installReadabilityHandler()
    }

    package func finish(timeout: Duration) async -> Data {
        let drainTask = Task<Void, Error> {
            await self.waitUntilFinished()
        }
        let join = BoundedTaskJoin(sourceTask: drainTask)
        _ = await join.value(joinGrace: timeout)
        return self.stopAndSnapshot()
    }

    package func finishSynchronously(timeout: TimeInterval) -> Data {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        self.condition.lock()
        while !self.isFinished, !self.isStopping {
            guard self.condition.wait(until: deadline) else { break }
        }
        self.condition.unlock()
        return self.stopAndSnapshot()
    }

    /// Waits only for the first complete output line. Useful for helpers whose descendants may inherit stdout
    /// after the helper itself exits, preventing EOF even though the caller already has its complete answer.
    package func finishFirstLineSynchronously(timeout: TimeInterval) -> Data {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        self.condition.lock()
        while !self.isFinished, !self.isStopping, !self.data.contains(0x0A) {
            guard self.condition.wait(until: deadline) else { break }
        }
        self.condition.unlock()
        return self.stopAndSnapshot()
    }

    package func stop() {
        _ = self.stopAndSnapshot()
    }

    package var reachedEOF: Bool {
        self.condition.lock()
        defer { self.condition.unlock() }
        return self.didReachEOF
    }

    /// Snapshot of the bytes captured so far, without stopping the capture. Lets a caller
    /// poll for interactive output (e.g. a device-flow URL/code) while the process is still running.
    package func currentSnapshot() -> Data {
        self.condition.lock()
        defer { self.condition.unlock() }
        return self.data
    }

    package static func decodeUTF8(_ data: Data) -> String {
        // A byte cap can split the final scalar; lossy decoding preserves the valid captured prefix.
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: data, as: UTF8.self)
    }

    private func handleReadableData(from handle: FileHandle) {
        self.condition.lock()
        guard !self.isStopping else {
            self.condition.unlock()
            return
        }
        self.activeCallbacks += 1
        self.condition.unlock()

        let chunk = handle.availableData
        var continuation: CheckedContinuation<Void, Never>?

        self.condition.lock()
        if chunk.isEmpty {
            self.isFinished = true
            self.didReachEOF = true
            continuation = self.continuation
            self.continuation = nil
        } else {
            let remainingBytes = max(0, self.maxBytes - self.data.count)
            if remainingBytes > 0 {
                self.data.append(chunk.prefix(remainingBytes))
            }
        }
        self.activeCallbacks -= 1
        if self.activeCallbacks == 0 {
            self.condition.broadcast()
        }
        self.condition.unlock()

        if chunk.isEmpty {
            handle.readabilityHandler = nil
        } else {
            self.onData?()
        }
        continuation?.resume()
    }

    private func installReadabilityHandler() {
        self.handle.readabilityHandler = { [weak self] handle in
            self?.handleReadableData(from: handle)
        }
    }

    private func waitUntilFinished() async {
        await withCheckedContinuation { continuation in
            self.condition.lock()
            if self.isFinished || self.isStopping {
                self.condition.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            self.condition.unlock()
        }
    }

    private func stopAndSnapshot() -> Data {
        let continuation: CheckedContinuation<Void, Never>?
        let snapshot: Data
        self.handle.readabilityHandler = nil

        self.condition.lock()
        self.isStopping = true
        while self.activeCallbacks > 0 {
            self.condition.wait()
        }
        self.isFinished = true
        continuation = self.continuation
        self.continuation = nil
        snapshot = self.data
        self.condition.unlock()

        // Linux closes from the reader's single exit path (or the never-started path above). On Darwin,
        // clearing readabilityHandler does not release its duplicated monitor descriptor immediately.
        try? self.handle.close()

        continuation?.resume()
        return snapshot
    }
}
