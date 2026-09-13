// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The durable result of importing user-owned Windows 98 installation media.
/// This is deliberately media only: an imported CD does not mean Windows has
/// been installed, booted, or is ready to run.
struct ClassicWindowsSetupMedia: Codable, Sendable, Equatable {
    let relativeImagePath: String
    let importedAt: Date

    func imageURL(storageRoot: URL) -> URL {
        storageRoot.appendingPathComponent(relativeImagePath)
    }
}

enum ClassicWindowsSetupError: LocalizedError, Equatable {
    case cancelled
    case notAnISO
    case notWindows98Media
    case sourceUnavailable
    case sourceTooLarge
    case copyFailed
    case importInProgress
    case clearFailed
    case noImportedMedia

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Import cancelled."
        case .notAnISO: return "Choose an ISO 9660 CD image."
        case .notWindows98Media: return "This ISO does not contain the Windows 98 setup files."
        case .sourceUnavailable: return "Flashback could not read that ISO image."
        case .sourceTooLarge: return "This ISO is too large to import."
        case .copyFailed: return "Flashback could not make its private copy of that ISO."
        case .importInProgress: return "Another Windows 98 ISO import is already in progress."
        case .clearFailed: return "Flashback could not remove the imported setup media."
        case .noImportedMedia: return "No Windows 98 setup media has been imported yet."
        }
    }
}

/// Imports a user-supplied Windows 98 ISO into the large external game
/// storage volume. It never mounts the ISO and it never downloads or bundles
/// Windows. The caller receives the validated private copy for guest setup.
actor ClassicWindowsSetup {
    private let storageRoot: URL
    private let fileManager: FileManager
    private let maximumImageBytes: Int64
    private let mediaDirectoryName = "ClassicWindowsSetup"
    private let mediaFilename = "Windows98-install.iso"
    private let stateFilename = "media.json"
    private var isImporting = false

    init(storageRoot: URL, fileManager: FileManager = .default,
         maximumImageBytes: Int64 = 4 * 1024 * 1024 * 1024) {
        self.storageRoot = storageRoot.standardizedFileURL
        self.fileManager = fileManager
        self.maximumImageBytes = maximumImageBytes
    }

    func importedMedia() throws -> ClassicWindowsSetupMedia? {
        let directory = mediaDirectory
        guard let directoryValues = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else { return nil }
        let stateURL = directory.appendingPathComponent(stateFilename)
        guard let values = try? stateURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 16 * 1024,
              let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(ClassicWindowsSetupMedia.self, from: data),
              state.relativeImagePath == expectedRelativeImagePath else {
            return nil
        }
        let image = state.imageURL(storageRoot: storageRoot)
        guard let imageValues = try? image.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              imageValues.isRegularFile == true, imageValues.isSymbolicLink != true,
              fileManager.isReadableFile(atPath: image.path) else { return nil }
        return state
    }

    func selectedValidatedImage() throws -> URL {
        guard let media = try importedMedia() else { throw ClassicWindowsSetupError.noImportedMedia }
        let image = media.imageURL(storageRoot: storageRoot)
        try ISO9660Windows98Validator.validate(image)
        return image
    }

    /// Validates first, then makes an atomic private copy. Cancellation leaves
    /// any previous successful import untouched.
    func importISO(at source: URL) async throws -> ClassicWindowsSetupMedia {
        guard !isImporting else { throw ClassicWindowsSetupError.importInProgress }
        isImporting = true
        defer { isImporting = false }
        guard source.isFileURL, source.pathExtension.lowercased() == "iso" else {
            throw ClassicWindowsSetupError.notAnISO
        }
        guard let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0 else { throw ClassicWindowsSetupError.sourceUnavailable }
        guard Int64(size) <= maximumImageBytes else { throw ClassicWindowsSetupError.sourceTooLarge }
        try Task.checkCancellation()
        try ISO9660Windows98Validator.validate(source)
        try Task.checkCancellation()

        let directory = try ensureMediaDirectory()
        let destination = directory.appendingPathComponent(mediaFilename)
        let staging = directory.appendingPathComponent(".import-" + UUID().uuidString)
        do {
            try await copyAtomically(from: source, to: staging, maximumBytes: maximumImageBytes)
            try Task.checkCancellation()
            // The source can change after its first validation, so only a
            // freshly validated staging copy is ever made durable.
            try ISO9660Windows98Validator.validate(staging)
            try Task.checkCancellation()
            if fileManager.fileExists(atPath: destination.path) {
                guard isPrivateRegularFile(destination) else { throw ClassicWindowsSetupError.copyFailed }
            }
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staging, backupItemName: nil, options: [])
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
            let stateURL = directory.appendingPathComponent(stateFilename)
            if fileManager.fileExists(atPath: stateURL.path), !isPrivateRegularFile(stateURL) {
                throw ClassicWindowsSetupError.copyFailed
            }
            let media = ClassicWindowsSetupMedia(relativeImagePath: expectedRelativeImagePath,
                                                  importedAt: Date())
            let encoded = try JSONEncoder().encode(media)
            try encoded.write(to: stateURL, options: .atomic)
            return media
        } catch is CancellationError {
            try? fileManager.removeItem(at: staging)
            throw ClassicWindowsSetupError.cancelled
        } catch let error as ClassicWindowsSetupError {
            try? fileManager.removeItem(at: staging)
            throw error
        } catch {
            try? fileManager.removeItem(at: staging)
            throw ClassicWindowsSetupError.copyFailed
        }
    }

    func clearImportedMedia() throws {
        let directory = mediaDirectory
        guard fileManager.fileExists(atPath: directory.path) else { return }
        guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { throw ClassicWindowsSetupError.clearFailed }
        for name in [stateFilename, mediaFilename] {
            let item = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: item.path) else { continue }
            guard isPrivateRegularFile(item) else { throw ClassicWindowsSetupError.clearFailed }
            do { try fileManager.removeItem(at: item) }
            catch { throw ClassicWindowsSetupError.clearFailed }
        }
    }

    private var mediaDirectory: URL { storageRoot.appendingPathComponent(mediaDirectoryName, isDirectory: true) }
    private var expectedRelativeImagePath: String { mediaDirectoryName + "/" + mediaFilename }

    private func ensureMediaDirectory() throws -> URL {
        let directory = mediaDirectory
        if fileManager.fileExists(atPath: directory.path) {
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { throw ClassicWindowsSetupError.copyFailed }
        } else {
            do { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { throw ClassicWindowsSetupError.copyFailed }
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { throw ClassicWindowsSetupError.copyFailed }
        }
        return directory
    }

    private func isPrivateRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private func copyAtomically(from source: URL, to staging: URL, maximumBytes: Int64) async throws {
        guard fileManager.createFile(atPath: staging.path, contents: nil) else { throw ClassicWindowsSetupError.copyFailed }
        let input: FileHandle
        let output: FileHandle
        do { input = try FileHandle(forReadingFrom: source); output = try FileHandle(forWritingTo: staging) }
        catch { throw ClassicWindowsSetupError.copyFailed }
        defer { try? input.close(); try? output.close() }
        var copiedBytes: Int64 = 0
        while true {
            try Task.checkCancellation()
            let chunk = try input.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            copiedBytes += Int64(chunk.count)
            guard copiedBytes <= maximumBytes else { throw ClassicWindowsSetupError.sourceTooLarge }
            try output.write(contentsOf: chunk)
        }
    }
}

/// A small, bounded ISO-9660 reader. It reads only the primary volume
/// descriptor and directory records needed to prove the expected setup tree.
private enum ISO9660Windows98Validator {
    private static let sectorSize: UInt64 = 2_048
    private static let descriptorOffset: UInt64 = 16 * sectorSize
    private static let maximumDirectoryBytes: UInt64 = 8 * 1024 * 1024
    private static let maximumDirectoryRecords = 12_000

    static func validate(_ url: URL) throws {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init),
              size >= descriptorOffset + sectorSize else { throw ClassicWindowsSetupError.notAnISO }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) } catch { throw ClassicWindowsSetupError.sourceUnavailable }
        defer { try? handle.close() }
        guard let pvd = try? read(handle, at: descriptorOffset, count: Int(sectorSize)),
              pvd.count == Int(sectorSize), pvd[0] == 1,
              String(data: pvd[1...5], encoding: .ascii) == "CD001", pvd[6] == 1 else {
            throw ClassicWindowsSetupError.notAnISO
        }
        guard let root = directoryRecord(pvd, offset: 156), root.length > 0 else { throw ClassicWindowsSetupError.notAnISO }
        let rootEntries = try entries(handle, directory: root, imageSize: size)
        guard let win98 = rootEntries.first(where: { $0.isDirectory && $0.name == "WIN98" }) else {
            throw ClassicWindowsSetupError.notWindows98Media
        }
        let setupEntries = try entries(handle, directory: win98, imageSize: size)
        guard setupEntries.contains(where: { !$0.isDirectory && ($0.name == "SETUP.EXE" || $0.name == "SETUP") }) else {
            throw ClassicWindowsSetupError.notWindows98Media
        }
    }

    private struct Record { let name: String; let extent: UInt64; let length: UInt64; let isDirectory: Bool }

    private static func entries(_ handle: FileHandle, directory: Record, imageSize: UInt64) throws -> [Record] {
        guard directory.length <= maximumDirectoryBytes,
              directory.extent <= UInt64.max / sectorSize else { throw ClassicWindowsSetupError.notAnISO }
        let offset = directory.extent * sectorSize
        guard offset <= imageSize, directory.length <= imageSize - offset else { throw ClassicWindowsSetupError.notAnISO }
        let data: Data
        do { data = try read(handle, at: offset, count: Int(directory.length)) } catch { throw ClassicWindowsSetupError.notAnISO }
        var result: [Record] = []
        var index = 0
        while index < data.count {
            let length = Int(data[index])
            if length == 0 { index = ((index / Int(sectorSize)) + 1) * Int(sectorSize); continue }
            guard length >= 34, index + length <= data.count, let record = directoryRecord(data, offset: index) else {
                throw ClassicWindowsSetupError.notAnISO
            }
            if record.name != "." && record.name != ".." { result.append(record) }
            guard result.count <= maximumDirectoryRecords else { throw ClassicWindowsSetupError.notAnISO }
            index += length
        }
        return result
    }

    private static func directoryRecord(_ data: Data, offset: Int) -> Record? {
        guard offset + 34 <= data.count else { return nil }
        let recordLength = Int(data[offset]), nameLength = Int(data[offset + 32])
        let minimumLength = 33 + nameLength + (nameLength.isMultiple(of: 2) ? 1 : 0)
        guard recordLength >= minimumLength, offset + recordLength <= data.count else { return nil }
        let rawName = Data(data[(offset + 33)..<(offset + 33 + nameLength)])
        let name: String
        if rawName == Data([0]) { name = "." }
        else if rawName == Data([1]) { name = ".." }
        else {
            guard let decoded = String(data: rawName, encoding: .ascii) else { return nil }
            name = decoded.split(separator: ";", maxSplits: 1).first.map(String.init)?.uppercased() ?? decoded.uppercased()
        }
        let extent = littleEndian32(data, offset + 2), bytes = littleEndian32(data, offset + 10)
        return Record(name: name, extent: UInt64(extent), length: UInt64(bytes), isDirectory: data[offset + 25] & 2 != 0)
    }

    private static func littleEndian32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }
}
