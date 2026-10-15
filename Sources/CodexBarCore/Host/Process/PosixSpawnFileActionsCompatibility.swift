import Darwin

typealias PosixSpawnFileActionsHandle = posix_spawn_file_actions_t?

enum PosixSpawnFileActionsCompatibility {
    static func addChangeDirectory(
        _ fileActions: inout PosixSpawnFileActionsHandle,
        path: UnsafePointer<CChar>) -> Int32
    {
        posix_spawn_file_actions_addchdir_np(&fileActions, path)
    }
}
