// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Snapshots only the writable DOS C: drive. Call only while the game is closed.
enum DOSGameData {
    static func validateTree(_ root: URL) throws {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let info = try root.resourceValues(forKeys: keys)
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw LibraryError("Choose a real game data folder.") }
        var failure: Error?, count = 0, bytes: Int64 = 0
        guard let scan = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in failure = error; return false }) else { throw LibraryError("The game data folder could not be read.") }
        for case let item as URL in scan {
            let values = try item.resourceValues(forKeys: keys)
            count += 1
            guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else { throw LibraryError("Game data contains a link or unsupported file. No files were replaced.") }
            bytes += Int64(values.fileSize ?? 0)
            guard count <= 30_000, bytes <= 4_294_967_296 else { throw LibraryError("This game data is too large for a snapshot (4 GB or 30,000 entries).") }
        }
        if let failure { throw failure }
    }

    static func backups(in saves: URL) throws -> [URL] {
        let root = try child("Backups", in: saves)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey,.isSymbolicLinkKey]).filter {
            let info = try $0.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey])
            return info.isDirectory == true && info.isSymbolicLink != true
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    @discardableResult static func backup(in saves: URL) throws -> URL {
        let source = try child("Files", in: saves)
        try validateTree(source)
        let destination = try newBackup(in: saves)
        let staging = try child(".snapshot-" + UUID().uuidString, in: saves)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        try validateTree(staging)
        try FileManager.default.moveItem(at: staging, to: destination)
        return destination
    }

    /// Stage replacement before moving the current drive into its recoverable backup.
    @discardableResult static func replace(in saves: URL, with source: URL) throws -> URL? {
        try validateTree(source)
        let working = try child("Files", in: saves)
        let canonical = source.standardizedFileURL.resolvingSymlinksInPath()
        guard canonical != working, !saves.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(canonical.path + "/") else { throw LibraryError("Choose an original game folder or a saved backup.") }
        let staging = try child(".restore-" + UUID().uuidString, in: saves)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        try validateTree(staging)
        var previous: URL?
        if FileManager.default.fileExists(atPath: working.path) {
            try validateTree(working)
            let destination = try newBackup(in: saves)
            try FileManager.default.moveItem(at: working, to: destination)
            previous = destination
        }
        do { try FileManager.default.moveItem(at: staging, to: working) }
        catch {
            if let previous { try FileManager.default.moveItem(at: previous, to: working) }
            throw error
        }
        return previous
    }

    private static func newBackup(in saves: URL) throws -> URL {
        let root = try child("Backups", in: saves)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return root.appendingPathComponent(date + "-" + UUID().uuidString.prefix(8))
    }
    private static func child(_ name: String, in saves: URL) throws -> URL {
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        guard try saves.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw LibraryError("The save folder must not be a symbolic link.") }
        let raw = saves.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: raw.path) {
            guard try raw.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw LibraryError("The save folder contains a symbolic link.") }
        }
        return try GameLibrary.contained(name, in: saves)
    }
}
