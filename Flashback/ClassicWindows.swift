// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Describes user-supplied Windows 98 media.  The paths deliberately remain
/// outside the game library: the hard disk is copied before it is ever mounted.
struct ClassicWindowsDescriptor: Codable, Sendable, Equatable {
    enum InstallState: String, Codable, Sendable {
        /// Windows still needs to be installed from the supplied CD image.
        case setupRequired
        /// The copied disk contains a user-completed installation.
        case installed
    }

    let identifier: String
    let diskImagePath: String
    let mediaImagePath: String?
    let installState: InstallState

    init(identifier: String, diskImage: URL, mediaImage: URL? = nil,
         installState: InstallState = .setupRequired) {
        self.identifier = identifier
        diskImagePath = diskImage.path
        mediaImagePath = mediaImage?.path
        self.installState = installState
    }
}

enum ClassicWindowsError: LocalizedError, Equatable {
    case invalidIdentifier
    case invalidPath(String)
    case missingDiskImage
    case unsupportedDiskImage
    case missingMediaImage
    case unsupportedMediaImage
    case unsafeCueSheet
    case unconfirmedGuestShutdown
    case invalidDiskLayout
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .invalidIdentifier: return "Classic Windows game identifiers may contain only letters, numbers, underscores, and hyphens."
        case .invalidPath(let path): return "This Classic Windows path cannot be placed in a DOSBox-X configuration: \(path)"
        case .missingDiskImage: return "The Windows hard disk image is missing or unreadable."
        case .unsupportedDiskImage: return "Choose a raw Windows hard disk image (.img, .ima, .hdd, or .raw)."
        case .missingMediaImage: return "The Windows CD image is missing or unreadable."
        case .unsupportedMediaImage: return "Choose an ISO image or a CUE sheet for the Windows CD."
        case .unsafeCueSheet: return "The CUE sheet refers to media outside its folder or has an unsupported FILE entry."
        case .unconfirmedGuestShutdown: return "Windows shutdown was not confirmed, so its session disk was not saved."
        case .invalidDiskLayout: return "The raw Windows disk must be at least one sector and have a whole-sector size. Installed disks also need a boot signature."
        case .copyFailed: return "Flashback could not create the private Windows hard disk copy."
        }
    }
}

/// A prepared DOSBox-X launch.  `installState` reports only the chosen setup
/// stage; it is intentionally not a claim that Windows or a game is runnable.
struct ClassicWindowsLaunch: Sendable {
    /// The last explicitly checkpointed Windows disk. Never mount this file.
    let checkpointDisk: URL
    /// A disposable disk used by exactly one DOSBox-X process.
    let writableDisk: URL
    /// Private, validated CD media mounted for this session, when required.
    /// The user-selected source image is never mounted by DOSBox-X.
    let mediaImage: URL?
    /// Host-visible state written through the guest E: mount. This is the
    /// only state file considered for checkpoint promotion.
    let guestState: URL
    let config: URL
    let installState: ClassicWindowsDescriptor.InstallState
}

/// The durable state of the shared Windows 98 base installation. This is
/// separate from an individual game's disposable checkpoint: a ready base is
/// only a prerequisite for a game profile, never a compatibility claim.
enum ClassicWindowsBaseInstallState: String, Codable, Sendable, Equatable {
    case notStarted
    case installing
    case ready
    case repairNeeded
}

/// Stored below the active Flashback library, so changing the app's storage
/// location carries the Windows setup state with the games it supports.
struct ClassicWindowsBaseInstallation: Codable, Sendable, Equatable {
    let state: ClassicWindowsBaseInstallState
    let mediaImageRelativePath: String?
    let diskImageRelativePath: String?
    let updatedAt: Date
    let issue: String?

    static func notStarted(at date: Date = Date()) -> Self {
        Self(state: .notStarted, mediaImageRelativePath: nil,
             diskImageRelativePath: nil, updatedAt: date, issue: nil)
    }
}

/// Resolved, validated paths for resuming the guided setup. The caller can
/// display `installation.state` directly and never needs to consult a
/// separate UserDefaults storage location.
struct ClassicWindowsBaseInstallationResume: Sendable, Equatable {
    let installation: ClassicWindowsBaseInstallation
    let mediaImage: URL?
    let diskImage: URL?
}

enum ClassicWindowsBaseInstallationError: LocalizedError, Equatable {
    case invalidStorage
    case invalidState
    case mediaOutsideLibrary
    case diskOutsideLibrary
    case mediaUnavailable
    case diskUnavailable
    case invalidTransition
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .invalidStorage: return "Flashback could not use the Classic Windows folder in this library."
        case .invalidState: return "The saved Classic Windows setup state needs repair."
        case .mediaOutsideLibrary: return "Windows setup media must be Flashback's private copy in this library."
        case .diskOutsideLibrary: return "The Windows disk must be Flashback's private copy in this library."
        case .mediaUnavailable: return "The saved Windows setup media is missing or unreadable."
        case .diskUnavailable: return "The saved Windows disk is missing or unreadable."
        case .invalidTransition: return "This Windows setup step is no longer valid. Start or repair setup before continuing."
        case .saveFailed: return "Flashback could not save the Windows setup state."
        }
    }
}

/// Owns the shared Windows 98 setup record. All paths written to the record
/// are relative to the active `GameLibrary.root`; this intentionally replaces
/// the old idea of a second Classic Windows storage preference.
actor ClassicWindowsBaseInstallationStore {
    private let storageRoot: URL
    private let fileManager: FileManager
    private let directoryName = "ClassicWindows"
    private let stateFilename = "base-installation.json"

    init(storageRoot: URL, fileManager: FileManager = .default) {
        self.storageRoot = storageRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.fileManager = fileManager
    }

    /// The one canonical Classic Windows directory for an active library.
    static func directory(in storageRoot: URL) -> URL {
        storageRoot.standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent("ClassicWindows", isDirectory: true)
    }

    func installation() throws -> ClassicWindowsBaseInstallation {
        let directory = try stateDirectory(create: false)
        let stateURL = directory.appendingPathComponent(stateFilename)
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return .notStarted()
        }
        guard isPrivateRegularFile(stateURL),
              let data = try? Data(contentsOf: stateURL), data.count <= 16 * 1024,
              let saved = try? JSONDecoder().decode(ClassicWindowsBaseInstallation.self, from: data) else {
            throw ClassicWindowsBaseInstallationError.invalidState
        }
        try validate(saved)
        return saved
    }

    /// Begins a new or resumed Windows setup after the ISO importer has made
    /// its private copy. `resumeDisk` is optional until the installer creates
    /// its initial hard disk image.
    func beginSetup(mediaImage: URL, resumeDisk: URL? = nil) throws -> ClassicWindowsBaseInstallation {
        let media = try relativePath(for: mediaImage, missing: .mediaUnavailable, outside: .mediaOutsideLibrary)
        let disk = try resumeDisk.map {
            try relativePath(for: $0, missing: .diskUnavailable, outside: .diskOutsideLibrary)
        }
        let next = ClassicWindowsBaseInstallation(state: .installing,
                                                   mediaImageRelativePath: media,
                                                   diskImageRelativePath: disk,
                                                   updatedAt: Date(), issue: nil)
        try save(next)
        return next
    }

    /// Records the verified private disk only after the guest installer has
    /// completed its own handoff. This method does not infer readiness from a
    /// DOSBox-X process exit.
    func markReady(installedDisk: URL) throws -> ClassicWindowsBaseInstallation {
        let current = try installation()
        guard current.state == .installing, current.mediaImageRelativePath != nil else {
            throw ClassicWindowsBaseInstallationError.invalidTransition
        }
        let disk = try relativePath(for: installedDisk, missing: .diskUnavailable, outside: .diskOutsideLibrary)
        let next = ClassicWindowsBaseInstallation(state: .ready,
                                                   mediaImageRelativePath: current.mediaImageRelativePath,
                                                   diskImageRelativePath: disk,
                                                   updatedAt: Date(), issue: nil)
        try save(next)
        return next
    }

    /// Preserve the last known private paths so a repair UI can offer Resume
    /// when the media and disk are still available.
    func markRepairNeeded(_ issue: String) throws -> ClassicWindowsBaseInstallation {
        let current = try installation()
        let safeIssue = String(issue.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 }.prefix(240))
        let next = ClassicWindowsBaseInstallation(state: .repairNeeded,
                                                   mediaImageRelativePath: current.mediaImageRelativePath,
                                                   diskImageRelativePath: current.diskImageRelativePath,
                                                   updatedAt: Date(), issue: safeIssue.isEmpty ? nil : safeIssue)
        try save(next)
        return next
    }

    /// Clears only the state record. It deliberately retains private media and
    /// disks so a future recovery flow never destroys a user's installation.
    func reset() throws -> ClassicWindowsBaseInstallation {
        let next = ClassicWindowsBaseInstallation.notStarted()
        try save(next)
        return next
    }

    /// Resolves state-relative paths only after validating that they remain
    /// private regular files below this library root.
    func resume() throws -> ClassicWindowsBaseInstallationResume {
        let saved = try installation()
        let media = try saved.mediaImageRelativePath.map {
            try resolve($0, missing: .mediaUnavailable)
        }
        let disk = try saved.diskImageRelativePath.map {
            try resolve($0, missing: .diskUnavailable)
        }
        return ClassicWindowsBaseInstallationResume(installation: saved, mediaImage: media, diskImage: disk)
    }

    private var stateDirectoryURL: URL {
        storageRoot.appendingPathComponent(directoryName, isDirectory: true)
    }

    private func stateDirectory(create: Bool) throws -> URL {
        let directory = stateDirectoryURL
        if fileManager.fileExists(atPath: directory.path) {
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else {
                throw ClassicWindowsBaseInstallationError.invalidStorage
            }
        } else if create {
            do { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { throw ClassicWindowsBaseInstallationError.saveFailed }
            guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else {
                throw ClassicWindowsBaseInstallationError.invalidStorage
            }
        } else {
            return directory
        }
        return directory
    }

    private func save(_ installation: ClassicWindowsBaseInstallation) throws {
        try validate(installation)
        let stateURL = try stateDirectory(create: true).appendingPathComponent(stateFilename)
        if fileManager.fileExists(atPath: stateURL.path), !isPrivateRegularFile(stateURL) {
            throw ClassicWindowsBaseInstallationError.invalidStorage
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(installation).write(to: stateURL, options: .atomic)
        } catch {
            throw ClassicWindowsBaseInstallationError.saveFailed
        }
    }

    private func validate(_ installation: ClassicWindowsBaseInstallation) throws {
        if let media = installation.mediaImageRelativePath { _ = try relativeComponents(media) }
        if let disk = installation.diskImageRelativePath { _ = try relativeComponents(disk) }
        switch installation.state {
        case .notStarted:
            guard installation.mediaImageRelativePath == nil, installation.diskImageRelativePath == nil else {
                throw ClassicWindowsBaseInstallationError.invalidState
            }
        case .installing:
            guard installation.mediaImageRelativePath != nil else { throw ClassicWindowsBaseInstallationError.invalidState }
        case .ready:
            guard installation.mediaImageRelativePath != nil, installation.diskImageRelativePath != nil else {
                throw ClassicWindowsBaseInstallationError.invalidState
            }
        case .repairNeeded:
            break
        }
    }

    private func relativePath(for url: URL, missing: ClassicWindowsBaseInstallationError,
                              outside: ClassicWindowsBaseInstallationError) throws -> String {
        let requested = url.standardizedFileURL
        guard isPrivateRegularFile(requested) else { throw missing }
        let resolved = requested.resolvingSymlinksInPath()
        let root = storageRoot.path + "/"
        guard resolved.path.hasPrefix(root) else { throw outside }
        let relative = String(resolved.path.dropFirst(root.count))
        _ = try relativeComponents(relative)
        return relative
    }

    private func resolve(_ relative: String, missing: ClassicWindowsBaseInstallationError) throws -> URL {
        _ = try relativeComponents(relative)
        let requested = storageRoot.appendingPathComponent(relative)
        guard isPrivateRegularFile(requested) else { throw missing }
        let resolved = requested.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(storageRoot.path + "/") else { throw missing }
        return resolved
    }

    private func relativeComponents(_ relative: String) throws -> [Substring] {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.isEmpty, !relative.contains("\\"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ClassicWindowsBaseInstallationError.invalidState
        }
        return components
    }

    private func isPrivateRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true && fileManager.isReadableFile(atPath: url.path)
    }
}

enum ClassicWindows {
    private static let diskExtensions: Set<String> = ["img", "ima", "hdd", "raw"]
    private static let mediaExtensions: Set<String> = ["iso", "cue"]

    /// Creates (once) a durable private checkpoint, then makes a disposable
    /// session disk from that checkpoint. Existing checkpoints are retained.
    /// Call `checkpoint(_:confirmedGuestShutdown:)` only after the UI has
    /// explicit evidence that the Windows guest shut down. Emulator exit status
    /// alone is not such evidence.
    static func prepare(_ descriptor: ClassicWindowsDescriptor, storageRoot: URL,
                        fileManager: FileManager = .default) throws -> ClassicWindowsLaunch {
        try validate(identifier: descriptor.identifier)
        let sourceDisk = try validateDisk(URL(fileURLWithPath: descriptor.diskImagePath), installState: descriptor.installState, fileManager: fileManager)
        let sourceMedia = try descriptor.mediaImagePath.map {
            try validateMedia(URL(fileURLWithPath: $0), fileManager: fileManager)
        }
        if descriptor.installState == .setupRequired, sourceMedia == nil { throw ClassicWindowsError.missingMediaImage }

        let root = storageRoot.standardizedFileURL.resolvingSymlinksInPath()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let gameDirectory = root.appendingPathComponent(descriptor.identifier, isDirectory: true)
        try fileManager.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        let safeGameDirectory = gameDirectory.standardizedFileURL.resolvingSymlinksInPath()
        guard safeGameDirectory.path.hasPrefix(root.path + "/") else { throw ClassicWindowsError.invalidIdentifier }

        let suffix = sourceDisk.pathExtension.lowercased()
        let checkpointDisk = safeGameDirectory.appendingPathComponent("Windows98." + suffix)
        if !fileManager.fileExists(atPath: checkpointDisk.path) {
            let staging = safeGameDirectory.appendingPathComponent(".Windows98-" + UUID().uuidString + ".copy")
            do {
                try fileManager.copyItem(at: sourceDisk, to: staging)
                try fileManager.moveItem(at: staging, to: checkpointDisk)
            } catch {
                try? fileManager.removeItem(at: staging)
                throw ClassicWindowsError.copyFailed
            }
        }
        _ = try validateRegularFile(checkpointDisk, missing: .copyFailed, fileManager: fileManager)

        // Keep removable media private as well. Apart from preventing an
        // emulator from ever writing a user-owned image, this makes a resumed
        // game independent from its original Finder location. A changed disc
        // is deliberately not silently substituted for an existing copy.
        let privateMedia: URL?
        if let sourceMedia {
            let mediaDirectory = safeGameDirectory.appendingPathComponent("Media", isDirectory: true)
            try fileManager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
            let destination = mediaDirectory.appendingPathComponent("Install." + sourceMedia.pathExtension.lowercased())
            if !fileManager.fileExists(atPath: destination.path) {
                let staging = mediaDirectory.appendingPathComponent(".media-" + UUID().uuidString)
                do {
                    try fileManager.copyItem(at: sourceMedia, to: staging)
                    // A CUE is only useful with its declared sibling tracks.
                    // The validator has already constrained these to plain
                    // files below the source CUE's directory; preserve their
                    // basenames beside the private copy.
                    if sourceMedia.pathExtension.lowercased() == "cue" {
                        for payload in try cuePayloads(sourceMedia, fileManager: fileManager) {
                            try fileManager.copyItem(at: payload, to: mediaDirectory.appendingPathComponent(payload.lastPathComponent))
                        }
                    }
                    try fileManager.moveItem(at: staging, to: destination)
                } catch {
                    try? fileManager.removeItem(at: staging)
                    for payload in (try? cuePayloads(sourceMedia, fileManager: fileManager)) ?? [] {
                        try? fileManager.removeItem(at: mediaDirectory.appendingPathComponent(payload.lastPathComponent))
                    }
                    throw ClassicWindowsError.copyFailed
                }
            }
            privateMedia = try validateMedia(destination, fileManager: fileManager)
        } else {
            privateMedia = nil
        }

        let session = safeGameDirectory.appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: session, withIntermediateDirectories: true)
        let writableDisk = session.appendingPathComponent("Windows98." + suffix)
        do { try fileManager.copyItem(at: checkpointDisk, to: writableDisk) }
        catch { try? fileManager.removeItem(at: session); throw ClassicWindowsError.copyFailed }

        let config = session.appendingPathComponent("dosbox-x.conf")
        let guestState = session.appendingPathComponent("STATE.INI")
        let contents = try configuration(disk: writableDisk, media: privateMedia, guestStateDirectory: session, installState: descriptor.installState)
        try Data(contents.utf8).write(to: config, options: .atomic)
        return ClassicWindowsLaunch(checkpointDisk: checkpointDisk, writableDisk: writableDisk, mediaImage: privateMedia, guestState: guestState, config: config, installState: descriptor.installState)
    }

    /// Atomically makes this completed session the next launch's checkpoint.
    /// `confirmedGuestShutdown` must come from an explicit guest-level signal,
    /// never merely from DOSBox-X exiting with status zero.
    static func checkpoint(_ launch: ClassicWindowsLaunch, confirmedGuestShutdown: Bool,
                           fileManager: FileManager = .default) throws {
        guard confirmedGuestShutdown else { throw ClassicWindowsError.unconfirmedGuestShutdown }
        let replacement = launch.checkpointDisk.deletingLastPathComponent()
            .appendingPathComponent(".Windows98-" + UUID().uuidString + ".checkpoint")
        do {
            try fileManager.copyItem(at: launch.writableDisk, to: replacement)
            _ = try fileManager.replaceItemAt(launch.checkpointDisk, withItemAt: replacement,
                                              backupItemName: nil, options: [])
        } catch {
            try? fileManager.removeItem(at: replacement)
            throw ClassicWindowsError.copyFailed
        }
    }

    /// Promote only a guest-written completion marker. A request marker or a
    /// clean emulator exit is intentionally insufficient.
    static func checkpointIfGuestCompleted(_ launch: ClassicWindowsLaunch,
                                           fileManager: FileManager = .default) throws -> Bool {
        guard let state = try guestState(at: launch.guestState), state.shutdown == "completed", state.exit == 0 else { return false }
        try checkpoint(launch, confirmedGuestShutdown: true, fileManager: fileManager)
        return true
    }

    struct GuestState: Equatable, Sendable { let phase: String; let exit: Int?; let shutdown: String? }
    static func guestState(at url: URL) throws -> GuestState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let text = try String(contentsOf: url, encoding: .utf8)
        guard text.utf8.count <= 4096 else { return nil }
        var values: [String:String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2, ["started", "exit", "shutdown", "error"].contains(pair[0]),
               pair[1].range(of: "^[A-Za-z0-9_-]{1,32}$", options: .regularExpression) != nil { values[pair[0]] = pair[1] }
        }
        guard !values.isEmpty else { return nil }
        return GuestState(phase: values["started"] == "1" ? "started" : values["error"] == nil ? "unknown" : "error", exit: values["exit"].flatMap(Int.init), shutdown: values["shutdown"])
    }

    /// Removes the disposable session disk after either a clean or forced exit.
    static func discard(_ launch: ClassicWindowsLaunch, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: launch.writableDisk.deletingLastPathComponent())
    }

    static func configuration(disk: URL, media: URL?, guestStateDirectory: URL? = nil, installState: ClassicWindowsDescriptor.InstallState) throws -> String {
        let diskPath = try configPath(disk)
        var autoexec = ["imgmount c \"\(diskPath)\""]
        if let media {
            let mediaPath = try configPath(media)
            let type = media.pathExtension.lowercased() == "iso" ? "iso" : "cdrom"
            autoexec.append("imgmount d \"\(mediaPath)\" -t \(type)")
        }
        if let guestStateDirectory { autoexec.append("mount e \"\(try configPath(guestStateDirectory))\"") }
        // Setup boots the CD's El Torito image. A completed installation boots
        // its HDD; neither state is presented as proof that Windows will run.
        if installState == .setupRequired {
            autoexec.append("imgmount a -bootcd d")
        }
        autoexec.append(installState == .setupRequired ? "boot a:" : "boot c:")
        return """
        [sdl]
        autolock=true
        fullscreen = false
        ; SDL1 DOSBox-X maps a captured pointer in emulator coordinates. Keep
        ; the documented default sensitivity and request emulation only while
        ; captured, so resizing the host window cannot mix a host-space
        ; absolute coordinate with a guest-space relative coordinate.
        sensitivity=100
        usesystemcursor=false
        mouse_emulation=locked
        windowresolution=original
        output=opengl
        ; Flashback owns shutdown and checkpointing for this private session.
        quit warning=false
        startbanner=false
        [dosbox]
        machine = svga_s3
        memsize = 128
        [cpu]
        core = normal
        cputype = pentium_mmx
        [sblaster]
        sbtype = sb16vibra
        [ide, primary]
        enable = true
        int13fakeio = true
        int13fakev86io = true
        [ide, secondary]
        enable = true
        int13fakeio = true
        int13fakev86io = true
        [autoexec]
        \(autoexec.joined(separator: "\n"))

        """
    }

    private static func validate(identifier: String) throws {
        guard identifier.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil else {
            throw ClassicWindowsError.invalidIdentifier
        }
    }

    private static func validateDisk(_ url: URL, installState: ClassicWindowsDescriptor.InstallState,
                                     fileManager: FileManager) throws -> URL {
        let file = try validateRegularFile(url, missing: .missingDiskImage, fileManager: fileManager)
        guard diskExtensions.contains(file.pathExtension.lowercased()) else { throw ClassicWindowsError.unsupportedDiskImage }
        let size = (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size >= 512, size % 512 == 0 else { throw ClassicWindowsError.invalidDiskLayout }
        if installState == .installed {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let bootSector = try handle.read(upToCount: 512) ?? Data()
            guard bootSector.count == 512, bootSector[510] == 0x55, bootSector[511] == 0xaa else { throw ClassicWindowsError.invalidDiskLayout }
        }
        _ = try configPath(file)
        return file
    }

    private static func validateMedia(_ url: URL, fileManager: FileManager) throws -> URL {
        let file = try validateRegularFile(url, missing: .missingMediaImage, fileManager: fileManager)
        guard mediaExtensions.contains(file.pathExtension.lowercased()) else { throw ClassicWindowsError.unsupportedMediaImage }
        _ = try configPath(file)
        if file.pathExtension.lowercased() == "cue" { try validateCue(file, fileManager: fileManager) }
        return file
    }

    private static func validateRegularFile(_ url: URL, missing: ClassicWindowsError,
                                            fileManager: FileManager) throws -> URL {
        let requested = url.standardizedFileURL
        let requestedValues = try? requested.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard requestedValues?.isRegularFile == true, requestedValues?.isSymbolicLink != true else { throw missing }
        let file = requested.resolvingSymlinksInPath()
        let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true,
              fileManager.isReadableFile(atPath: file.path), (values?.fileSize ?? 0) > 0 else { throw missing }
        return file
    }

    private static func configPath(_ url: URL) throws -> String {
        let path = url.path
        guard !path.isEmpty, path.unicodeScalars.allSatisfy({ scalar in
            scalar.value >= 32 && scalar.value != 127 && scalar.value != 34 && scalar.value != 37
        }) else { throw ClassicWindowsError.invalidPath(path) }
        return path
    }

    /// CUE sheets are parsed by DOSBox-X, so restrict referenced payloads to
    /// readable sibling files instead of allowing a sheet to escape its folder.
    private static func validateCue(_ cue: URL, fileManager: FileManager) throws {
        _ = try cuePayloads(cue, fileManager: fileManager)
    }

    private static func cuePayloads(_ cue: URL, fileManager: FileManager) throws -> [URL] {
        guard let text = try? String(contentsOf: cue, encoding: .utf8) else { throw ClassicWindowsError.unsafeCueSheet }
        let expression = try! NSRegularExpression(pattern: #"(?i)^\s*FILE\s+\"([^\"\r\n]+)\"\s+(BINARY|MOTOROLA|AIFF|WAVE|MP3)\s*$"#)
        var payloads: [URL] = []
        for line in text.components(separatedBy: .newlines) where line.uppercased().contains("FILE") {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = expression.firstMatch(in: line, range: range), let nameRange = Range(match.range(at: 1), in: line) else {
                throw ClassicWindowsError.unsafeCueSheet
            }
            let name = String(line[nameRange])
            guard !name.contains(".."), !name.hasPrefix("/"), !name.contains(":") else { throw ClassicWindowsError.unsafeCueSheet }
            let payload = cue.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL.resolvingSymlinksInPath()
            let parent = cue.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path + "/"
            guard payload.path.hasPrefix(parent) else { throw ClassicWindowsError.unsafeCueSheet }
            _ = try validateRegularFile(payload, missing: .unsafeCueSheet, fileManager: fileManager)
            payloads.append(payload)
        }
        guard !payloads.isEmpty else { throw ClassicWindowsError.unsafeCueSheet }
        return payloads
    }
}
