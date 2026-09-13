// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@main struct ClassicWindowsSetupChecks {
    static func main() async throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("ClassicWindowsSetupChecks-" + UUID().uuidString)
        defer { try? fm.removeItem(at: scratch) }
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let valid = scratch.appendingPathComponent("Windows 98 SE.iso")
        try fixtureISO(win98: true).write(to: valid)
        let service = ClassicWindowsSetup(storageRoot: scratch.appendingPathComponent("External Library"))
        let media = try await service.importISO(at: valid)
        let copied = media.imageURL(storageRoot: scratch.appendingPathComponent("External Library"))
        guard copied != valid, fm.fileExists(atPath: copied.path), try await service.selectedValidatedImage() == copied else { throw Failure("valid ISO was not retained") }
        guard (try await service.importedMedia()) != nil else { throw Failure("import state was not persisted") }
        let stateURL = copied.deletingLastPathComponent().appendingPathComponent("media.json")
        let traversal = ClassicWindowsSetupMedia(relativeImagePath: "../outside.iso", importedAt: Date())
        try JSONEncoder().encode(traversal).write(to: stateURL, options: .atomic)
        guard try await service.importedMedia() == nil else { throw Failure("manifest path traversal was accepted") }
        let restored = try await service.importISO(at: valid)
        guard restored.relativeImagePath == "ClassicWindowsSetup/Windows98-install.iso",
              try await service.selectedValidatedImage() == copied,
              (try await service.importedMedia()) != nil else { throw Failure("re-import did not restore persistent state") }
        let noSetup = scratch.appendingPathComponent("not-windows.iso"); try fixtureISO(win98: false).write(to: noSetup)
        try await expect(.notWindows98Media) { _ = try await service.importISO(at: noSetup) }
        let broken = scratch.appendingPathComponent("broken.iso"); try Data(repeating: 0, count: 40_000).write(to: broken)
        try await expect(.notAnISO) { _ = try await service.importISO(at: broken) }
        let linkedStore = scratch.appendingPathComponent("Linked Library")
        try fm.createDirectory(at: linkedStore, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: linkedStore.appendingPathComponent("ClassicWindowsSetup"), withDestinationURL: scratch)
        let linkedService = ClassicWindowsSetup(storageRoot: linkedStore)
        try await expect(.copyFailed) { _ = try await linkedService.importISO(at: valid) }
        try await service.clearImportedMedia()
        try await expect(.noImportedMedia) { _ = try await service.selectedValidatedImage() }
        print("ClassicWindowsSetupChecks passed")
    }

    private static func expect(_ expected: ClassicWindowsSetupError, _ body: () async throws -> Void) async throws {
        do { try await body() }
        catch let error as ClassicWindowsSetupError where error == expected { return }
        catch { throw Failure("wrong error: \(error)") }
        throw Failure("expected \(expected)")
    }

    private static func fixtureISO(win98: Bool) -> Data {
        let sector = 2048, rootSector = 20, setupSector = 21
        var image = Data(repeating: 0, count: 24 * sector)
        image[16 * sector] = 1; image.replaceSubrange((16 * sector + 1)..<(16 * sector + 6), with: Data("CD001".utf8)); image[16 * sector + 6] = 1
        writeRecord(&image, at: 16 * sector + 156, extent: rootSector, length: sector, flags: 2, name: [0])
        var offset = rootSector * sector
        offset += writeRecord(&image, at: offset, extent: rootSector, length: sector, flags: 2, name: [0])
        offset += writeRecord(&image, at: offset, extent: rootSector, length: sector, flags: 2, name: [1])
        let folder = Array((win98 ? "WIN98" : "OTHER").utf8)
        _ = writeRecord(&image, at: offset, extent: setupSector, length: sector, flags: 2, name: folder)
        offset = setupSector * sector
        offset += writeRecord(&image, at: offset, extent: setupSector, length: sector, flags: 2, name: [0])
        offset += writeRecord(&image, at: offset, extent: setupSector, length: sector, flags: 2, name: [1])
        _ = writeRecord(&image, at: offset, extent: 22, length: 10, flags: 0, name: Array("SETUP.EXE;1".utf8))
        return image
    }

    @discardableResult private static func writeRecord(_ data: inout Data, at offset: Int, extent: Int, length: Int, flags: UInt8, name: [UInt8]) -> Int {
        let recordLength = 33 + name.count + ((name.count & 1) == 0 ? 1 : 0)
        data[offset] = UInt8(recordLength); put32(&data, offset + 2, extent); put32(&data, offset + 10, length)
        data[offset + 25] = flags; data[offset + 28] = 1; data[offset + 32] = UInt8(name.count)
        data.replaceSubrange((offset + 33)..<(offset + 33 + name.count), with: name)
        return recordLength
    }
    private static func put32(_ data: inout Data, _ offset: Int, _ value: Int) { for index in 0..<4 { data[offset + index] = UInt8((value >> (index * 8)) & 255) } }
}

private struct Failure: Error { let message: String; init(_ message: String) { self.message = message } }
