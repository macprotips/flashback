// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@main struct ClassicWindowsChecks {
    static func main() async throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("ClassicWindowsChecks-" + UUID().uuidString)
        defer { try? fm.removeItem(at: scratch) }
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let source = scratch.appendingPathComponent("Windows 98.hdd")
        let iso = scratch.appendingPathComponent("Install CD.iso")
        try Data(repeating: 0, count: 512).write(to: source)
        try Data([9, 8, 7]).write(to: iso)
        let before = try Data(contentsOf: source)
        let descriptor = ClassicWindowsDescriptor(identifier: "game_98", diskImage: source, mediaImage: iso)
        let storage = scratch.appendingPathComponent("Library")
        let first = try ClassicWindows.prepare(descriptor, storageRoot: storage)
        guard first.installState == .setupRequired, try Data(contentsOf: source) == before,
              first.writableDisk != source, fm.fileExists(atPath: first.config.path),
              first.mediaImage != iso, try Data(contentsOf: first.mediaImage!) == Data(contentsOf: iso) else { throw CheckFailure("source media or disk was changed or staging failed") }
        var changed = try Data(contentsOf: first.writableDisk)
        changed[0] = 5
        try changed.write(to: first.writableDisk)
        let second = try ClassicWindows.prepare(descriptor, storageRoot: storage)
        guard second.checkpointDisk == first.checkpointDisk, try Data(contentsOf: second.writableDisk).count == 512,
              try Data(contentsOf: source) == before else { throw CheckFailure("private checkpoint was not reused safely") }
        try expectError("unconfirmed guest shutdown", .unconfirmedGuestShutdown) {
            try ClassicWindows.checkpoint(first, confirmedGuestShutdown: false)
        }
        try ClassicWindows.checkpoint(first, confirmedGuestShutdown: true)
        let third = try ClassicWindows.prepare(descriptor, storageRoot: storage)
        guard try Data(contentsOf: third.writableDisk).first == 5 else { throw CheckFailure("clean session was not checkpointed") }
        try Data("[State]\nstarted=1\nexit=0\nshutdown=requested\n".utf8).write(to: third.guestState)
        guard try !ClassicWindows.checkpointIfGuestCompleted(third) else { throw CheckFailure("shutdown request promoted a checkpoint") }
        try Data("[State]\nstarted=1\nexit=0\nshutdown=completed\n".utf8).write(to: third.guestState)
        guard try ClassicWindows.checkpointIfGuestCompleted(third) else { throw CheckFailure("completed guest marker did not promote checkpoint") }
        let config = try String(contentsOf: first.config, encoding: .utf8)
        guard config.contains("imgmount c \"" + first.writableDisk.path + "\""),
              config.contains("imgmount d \"" + first.mediaImage!.path + "\" -t iso"), config.contains("imgmount a -bootcd d"), config.contains("boot a"),
              config.contains("mount e \"" + first.guestState.deletingLastPathComponent().path + "\""),
              config.contains("autolock=true"), config.contains("usesystemcursor=false"),
              config.contains("mouse_emulation=locked"), config.contains("sensitivity=100"),
              config.contains("windowresolution=original"), config.contains("output=opengl"),
              config.contains("quit warning=false"), config.contains("startbanner=false") else { throw CheckFailure("DOSBox-X gameplay launch must retain its captured relative-input and managed-lifecycle configuration") }
        try expectError("invalid identifier", .invalidIdentifier) {
            _ = try ClassicWindows.prepare(ClassicWindowsDescriptor(identifier: "bad\n[autoexec]", diskImage: source), storageRoot: storage)
        }
        let malicious = scratch.appendingPathComponent("bad\nboot -l a.hdd")
        try Data(repeating: 1, count: 512).write(to: malicious)
        try expectError("config injection path", .invalidPath(malicious.path)) {
            _ = try ClassicWindows.prepare(ClassicWindowsDescriptor(identifier: "path-test", diskImage: malicious), storageRoot: storage)
        }
        let cue = scratch.appendingPathComponent("escape.cue")
        try Data("FILE \"../elsewhere.bin\" BINARY\n".utf8).write(to: cue)
        try expectError("unsafe cue", .unsafeCueSheet) {
            _ = try ClassicWindows.prepare(ClassicWindowsDescriptor(identifier: "cue-test", diskImage: source, mediaImage: cue), storageRoot: storage)
        }
        let mdf = scratch.appendingPathComponent("Hot Wheels.mdf")
        try Data(repeating: 0, count: 512).write(to: mdf)
        try expectError("MDF media", .unsupportedMediaImage) {
            _ = try ClassicWindows.prepare(ClassicWindowsDescriptor(identifier: "mdf-test", diskImage: source, mediaImage: mdf), storageRoot: storage)
        }
        let payload = scratch.appendingPathComponent("disc.bin")
        try Data([3]).write(to: payload)
        let validCue = scratch.appendingPathComponent("valid.cue")
        try Data("FILE \"disc.bin\" BINARY\n  TRACK 01 MODE1/2352\n".utf8).write(to: validCue)
        _ = try ClassicWindows.prepare(ClassicWindowsDescriptor(identifier: "valid-cue", diskImage: source, mediaImage: validCue), storageRoot: storage)
        var installedDisk = Data(repeating: 0, count: 512); installedDisk[510] = 0x55; installedDisk[511] = 0xaa
        let installedSource = scratch.appendingPathComponent("installed.raw"); try installedDisk.write(to: installedSource)
        let installed = ClassicWindowsDescriptor(identifier: "installed", diskImage: installedSource, installState: .installed)
        let installedLaunch = try ClassicWindows.prepare(installed, storageRoot: storage)
        let installedConfig = try String(contentsOf: installedLaunch.config, encoding: .utf8)
        guard installedLaunch.installState == .installed, installedConfig.contains("boot c") else { throw CheckFailure("install state was not preserved") }

        // Shared setup state belongs in this library, never in a second
        // user-defaults-selected folder. Its paths remain relative and are
        // rejected if a damaged manifest tries to escape the library.
        let baseStore = ClassicWindowsBaseInstallationStore(storageRoot: storage)
        guard try await baseStore.installation().state == .notStarted,
              ClassicWindowsBaseInstallationStore.directory(in: storage) == storage.appendingPathComponent("ClassicWindows", isDirectory: true) else {
            throw CheckFailure("base installation did not start in the active library")
        }
        let privateMedia = storage.appendingPathComponent("ClassicWindowsSetup/Windows98-install.iso")
        try fm.createDirectory(at: privateMedia.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([9, 8, 7]).write(to: privateMedia)
        let installing = try await baseStore.beginSetup(mediaImage: privateMedia)
        guard installing.state == .installing,
              installing.mediaImageRelativePath == "ClassicWindowsSetup/Windows98-install.iso",
              (try await baseStore.resume()).mediaImage == privateMedia else {
            throw CheckFailure("setup media could not be resumed from library storage")
        }
        let privateDisk = storage.appendingPathComponent("ClassicWindows/Windows98/Windows98.img")
        try fm.createDirectory(at: privateDisk.deletingLastPathComponent(), withIntermediateDirectories: true)
        try installedDisk.write(to: privateDisk)
        let ready = try await baseStore.markReady(installedDisk: privateDisk)
        guard ready.state == .ready,
              (try await baseStore.resume()).diskImage == privateDisk else {
            throw CheckFailure("ready base installation could not be resumed")
        }
        let stateURL = storage.appendingPathComponent("ClassicWindows/base-installation.json")
        let escaped = ClassicWindowsBaseInstallation(state: .ready, mediaImageRelativePath: "../outside.iso",
                                                      diskImageRelativePath: "ClassicWindows/Windows98/Windows98.img",
                                                      updatedAt: Date(), issue: nil)
        try JSONEncoder().encode(escaped).write(to: stateURL, options: .atomic)
        do {
            _ = try await baseStore.installation()
            throw CheckFailure("base state accepted a path outside the library")
        } catch ClassicWindowsBaseInstallationError.invalidState { }
        _ = try await baseStore.reset()
        guard try await baseStore.installation().state == .notStarted else {
            throw CheckFailure("base installation reset did not preserve a usable not-started state")
        }
        print("ClassicWindowsChecks passed")
    }

    private static func expectError(_ label: String, _ expected: ClassicWindowsError,
                                    _ body: () throws -> Void) throws {
        do { try body() }
        catch let error as ClassicWindowsError where error == expected { return }
        catch { throw CheckFailure("\(label) returned the wrong error: \(error)") }
        throw CheckFailure("expected failure: \(label)")
    }
}

private struct CheckFailure: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
