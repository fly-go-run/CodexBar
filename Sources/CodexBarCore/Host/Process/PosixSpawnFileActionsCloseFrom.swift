import Darwin
import Foundation

enum PosixSpawnFileActionsCloseFrom {
    enum CloseFromError: LocalizedError {
        case descriptorEnumerationFailed(String)
        case actionFailed(Int32)

        var errorDescription: String? {
            switch self {
            case let .descriptorEnumerationFailed(details):
                "Could not enumerate /proc/self/fd: \(details)"
            case let .actionFailed(code):
                "Could not configure descriptor cleanup: \(String(cString: strerror(code))) (\(code))"
            }
        }
    }

    static func descriptorsToClose(
        startingAt minimumFileDescriptor: Int32,
        contentsOfDirectory: (String) throws -> [String] = FileManager.default.contentsOfDirectory(atPath:)) throws
        -> [Int32]
    {
        let entries: [String]
        do {
            entries = try contentsOfDirectory("/proc/self/fd")
        } catch {
            throw CloseFromError.descriptorEnumerationFailed(error.localizedDescription)
        }
        return entries.compactMap(Int32.init)
            .filter { $0 >= minimumFileDescriptor }
            .sorted()
    }
}
