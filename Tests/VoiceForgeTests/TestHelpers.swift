import Foundation
#if canImport(VoiceForgeCore)
@testable import VoiceForgeCore
#else
@testable import VoiceForge
#endif

// MARK: - Belt-and-suspenders path guards

/// Returns the temporary directory root used by every helper in this file.
/// All destructive operations are constrained to paths under this root.
private let testTempPrefix = FileManager.default.temporaryDirectory.path

/// Refuses any path that is not under the system temporary directory.
/// Uses component-boundary containment (exact match or root + "/") after
/// symlink resolution and standardization so sibling names like `/tmp-evil`
/// are rejected.
func assertSafeTestPath(_ url: URL, file: StaticString = #file, line: UInt = #line) throws {
    let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
    let root = URL(fileURLWithPath: testTempPrefix).resolvingSymlinksInPath().standardizedFileURL.path
    let isContained = resolved == root || resolved.hasPrefix(root + "/")
    guard isContained else {
        throw TestSafetyError.unsafePath(resolved, allowedRoot: root)
    }
}

enum TestSafetyError: Error, CustomStringConvertible {
    case unsafePath(String, allowedRoot: String)

    var description: String {
        switch self {
        case let .unsafePath(path, allowedRoot):
            return "Test attempted to touch a path outside the temporary directory: \(path)\nAllowed root: \(allowedRoot)"
        }
    }
}

// MARK: - Isolated HistoryStore factory

/// Creates a temporary directory structure mirroring the production layout:
/// `<temp>/VoiceForge-Test-<uuid>/VoiceForge/history.json`
/// The returned `HistoryStore` has its `storageRoot` pinned inside the temp tree
/// and will never enumerate or mutate the real Application Support folder.
///
/// Callers **must** `defer { cleanup() }` so the temp directory is removed even
/// if a test assertion fails.
func makeIsolatedHistoryStore(
    fileManager: FileManager = .default,
    file: StaticString = #file,
    line: UInt = #line
) throws -> (store: HistoryStore, cleanup: () -> Void) {
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("VoiceForge-Test-\(UUID().uuidString)", isDirectory: true)
    try assertSafeTestPath(root, file: file, line: line)

    let vfDir = root.appendingPathComponent("VoiceForge", isDirectory: true)
    try fileManager.createDirectory(at: vfDir, withIntermediateDirectories: true)

    let outputsDir = vfDir.appendingPathComponent("outputs", isDirectory: true)
    try fileManager.createDirectory(at: outputsDir, withIntermediateDirectories: true)

    let historyURL = vfDir.appendingPathComponent("history.json")
    let store = HistoryStore(fileURL: historyURL, fileManager: fileManager)
    return (store, { try? fileManager.removeItem(at: root) })
}
