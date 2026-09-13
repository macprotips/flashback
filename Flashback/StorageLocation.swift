// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

struct StorageLocationError: LocalizedError { let message: String; var errorDescription: String? { message } }

/// Resolves the single durable root containing the library, imported games,
/// covers, DOS/ScummVM/native saves, and their runtime files. App preferences
/// remain in UserDefaults, and Flash/HTML browser storage remains in WebKit's
/// macOS-managed data store; neither is migrated with game data.
struct StorageLocation {
    static let bookmarkKey = "FlashbackStorageBookmark"
    static let pathKey = "FlashbackStoragePath"
    static let promptCompletedKey = "FlashbackStoragePromptCompleted"
    let defaults: UserDefaults
    let fileManager: FileManager

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults; self.fileManager = fileManager
    }

    var defaultRoot: URL { fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Flashback", isDirectory: true) }

    func resolvedRoot() -> URL {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return defaultRoot }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return defaultRoot }
        if stale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) { defaults.set(refreshed, forKey: Self.bookmarkKey) }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    /// Returns the chosen root only when its bookmark resolves to a readable
    /// directory. Callers must present recovery rather than silently falling
    /// back, because a disconnected volume must not become an empty library.
    func selectedRootPreflight() -> URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData:data, options:[.withSecurityScope], relativeTo:nil, bookmarkDataIsStale:&stale),
              !stale, (try? url.resourceValues(forKeys:[.isDirectoryKey]))?.isDirectory == true,
              fileManager.isReadableFile(atPath:url.path) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    func useExisting(_ root: URL) throws {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        guard (try? root.resourceValues(forKeys:[.isDirectoryKey]))?.isDirectory == true,
              fileManager.isReadableFile(atPath:root.path) else { throw StorageLocationError(message:"Choose an existing readable Flashback library folder.") }
        defaults.set(try root.bookmarkData(options:[.withSecurityScope], includingResourceValuesForKeys:nil, relativeTo:nil), forKey:Self.bookmarkKey)
        defaults.set(root.path, forKey:Self.pathKey)
    }

    func select(_ root: URL, movingFrom source: URL?) throws -> URL {
        let destination = root.standardizedFileURL.resolvingSymlinksInPath()
        guard destination.isFileURL else { throw StorageLocationError(message:"Choose a folder on this Mac.") }
        let app = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL.resolvingSymlinksInPath()
        guard !contains(destination, app), !contains(destination, cwd) else { throw StorageLocationError(message:"Choose a folder outside the Flashback app and its source folder.") }
        if let source {
            let canonicalSource = source.standardizedFileURL.resolvingSymlinksInPath()
            guard destination != canonicalSource, !contains(destination, canonicalSource), !contains(canonicalSource, destination) else { throw StorageLocationError(message:"The new storage folder cannot be inside the current library or contain it.") }
            try migrate(canonicalSource, to: destination)
        } else { try fileManager.createDirectory(at: destination, withIntermediateDirectories: true) }
        let bookmark = try destination.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: Self.bookmarkKey); defaults.set(destination.path, forKey: Self.pathKey)
        return destination
    }

    private func migrate(_ source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else { try fileManager.createDirectory(at: destination, withIntermediateDirectories: true); return }
        guard !fileManager.fileExists(atPath: destination.path) else { throw StorageLocationError(message:"The chosen storage folder already exists. Choose an empty new folder.") }
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".Flashback-migration-" + UUID().uuidString)
        do {
            try fileManager.copyItem(at: source, to: stage)
            guard try identical(source, stage) else { throw StorageLocationError(message:"Flashback could not verify the copied library. Your existing library was left unchanged.") }
            try fileManager.moveItem(at: stage, to: destination)
        } catch { try? fileManager.removeItem(at: stage); throw error }
    }

    private func identical(_ a: URL, _ b: URL) throws -> Bool {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var entries: [(String, Int, String)] = []
        for root in [a, b] {
            var current: [(String, Int, String)] = []
            let base = root.path + "/"
            guard let scan = fileManager.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: []) else { return false }
            for case let item as URL in scan {
                let values = try item.resourceValues(forKeys: keys)
                if values.isDirectory == true { continue }
                guard values.isRegularFile == true, values.isSymbolicLink != true else { return false }
                let stream = try FileHandle(forReadingFrom: item)
                var hash = SHA256()
                while let block = try stream.read(upToCount: 1_048_576), !block.isEmpty { hash.update(data:block) }
                try? stream.close()
                let canonicalItem = item.standardizedFileURL.resolvingSymlinksInPath().path
                guard canonicalItem.hasPrefix(base) else { return false }
                current.append((String(canonicalItem.dropFirst(base.count)), values.fileSize ?? -1, Data(hash.finalize()).base64EncodedString()))
            }
            current.sort { $0.0 < $1.0 }
            if entries.isEmpty { entries = current }
            else if entries.count != current.count || zip(entries, current).contains(where: { left, right in left.0 != right.0 || left.1 != right.1 || left.2 != right.2 }) { return false }
        }
        return true
    }
    private func contains(_ parent: URL, _ child: URL) -> Bool { child.path == parent.path || child.path.hasPrefix(parent.path + "/") }
}
