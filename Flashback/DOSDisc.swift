// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum DOSDiscKind: String, Codable, Sendable {
    case cd, floppy

    var directoryName: String { self == .cd ? "CD" : "Floppy" }
    var drive: String { self == .cd ? "d" : "a" }
    var mountType: String { self == .cd ? "cdrom" : "floppy" }
}

/// The primary image paths for one user-selected set of media. Paths are
/// relative to `Native Saves/<game>/Media`; a CUE's referenced tracks live
/// beside its CUE and are deliberately not exposed as mount targets.
struct DOSDisc: Codable, Equatable, Sendable {
    let kind: DOSDiscKind
    let files: [String]
}

enum DOSDiscs {
    private static let indexName = "dos-discs.json"
    private static let mediaName = "Media"
    private static let maxFileBytes: Int64 = 4 * 1024 * 1024 * 1024
    private static let maxSetBytes: Int64 = 8 * 1024 * 1024 * 1024
    private static let cdExtensions: Set<String> = ["iso", "cue"]
    private static let floppyExtensions: Set<String> = ["img", "ima"]
    // CUE sheets may refer to a data BIN or an audio file. MDF/MDS is not
    // accepted because this compact importer does not claim raw MDF support.
    private static let cueTrackExtensions: Set<String> = ["bin", "wav", "mp3", "ogg", "flac"]

    static func load(from saves: URL) throws -> [DOSDisc] {
        let index = saves.appendingPathComponent(indexName)
        guard FileManager.default.fileExists(atPath:index.path) else { return [] }
        let values = try index.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? 0) <= 1_048_576 else { throw LibraryError("The saved media list is invalid.") }
        let discs = try JSONDecoder().decode([DOSDisc].self, from:Data(contentsOf:index))
        try validate(discs, in:saves)
        return discs
    }

    static func save(_ discs: [DOSDisc], to saves: URL) throws {
        try FileManager.default.createDirectory(at:saves,withIntermediateDirectories:true)
        try validate(discs, in:saves)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(discs).write(to:saves.appendingPathComponent(indexName),options:.atomic)
    }

    /// Copies user-selected images into private storage. CD selection order is
    /// retained so DOSBox Staging's disk-swap shortcut advances predictably.
    static func importMedia(urls: [URL], into saves: URL, kind: DOSDiscKind) throws -> DOSDisc {
        guard !urls.isEmpty else { throw LibraryError("Choose at least one " + (kind == .cd ? "CD" : "floppy") + " image.") }
        guard urls.count <= 32 else { throw LibraryError("Choose no more than 32 images at once.") }
        let fm = FileManager.default
        try fm.createDirectory(at:saves,withIntermediateDirectories:true)
        let existing = try load(from:saves)
        guard existing.count < 8 else { throw LibraryError("Too many media sets are attached to this game.") }
        let mediaRoot = saves.appendingPathComponent(mediaName,isDirectory:true)
        try fm.createDirectory(at:mediaRoot,withIntermediateDirectories:true)
        let rootValues = try mediaRoot.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw LibraryError("The saved media folder is invalid.") }
        let destination = try uniqueDirectory(kind.directoryName, in:mediaRoot)
        let staging = mediaRoot.appendingPathComponent(".import-" + UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:staging,withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:staging) }
        var primaries: [String] = [], total = try mediaBytes(in:mediaRoot)
        for (offset, source) in urls.enumerated() {
            let checked = try regularSource(source)
            let ext = checked.pathExtension.lowercased()
            let accepted = kind == .cd ? cdExtensions : floppyExtensions
            guard accepted.contains(ext) else {
                throw LibraryError(kind == .cd ? "Choose ISO or CUE CD images. MDF and MDS images are not supported." : "Choose IMG or IMA floppy images.")
            }
            let discDirectory = staging.appendingPathComponent(String(format:"%02d",offset + 1),isDirectory:true)
            try fm.createDirectory(at:discDirectory,withIntermediateDirectories:false)
            let target = discDirectory.appendingPathComponent(try safeName(checked.lastPathComponent))
            total += try copy(checked,to:target,total:total)
            if ext == "cue" {
                for sibling in try cueSiblings(of:checked) {
                    let siblingTarget = discDirectory.appendingPathComponent(try safeName(sibling.lastPathComponent))
                    total += try copy(sibling,to:siblingTarget,total:total)
                }
            }
            guard total <= maxSetBytes else { throw LibraryError("Selected media is larger than 8 GB.") }
            let position = String(format:"%02d",offset + 1)
            primaries.append(destination.lastPathComponent + "/" + position + "/" + target.lastPathComponent)
        }
        try fm.moveItem(at:staging,to:destination)
        let disc = DOSDisc(kind:kind,files:primaries)
        try validate([disc],in:saves)
        return disc
    }

    /// Returns `mount` commands to run after C: is mounted and before secure
    /// mode. Multiple paths on one command let DOSBox Staging swap media.
    static func commands(from saves: URL) throws -> [String] {
        let root = saves.appendingPathComponent(mediaName,isDirectory:true).standardizedFileURL.resolvingSymlinksInPath()
        let discs = try load(from:saves)
        var commands: [String] = []
        for kind in [DOSDiscKind.cd,.floppy] {
            let paths = try discs.filter { $0.kind == kind }.flatMap(\.files).map { relative -> String in
                let file = try contained(relative,in:root)
                guard FileManager.default.fileExists(atPath:file.path) else { throw LibraryError("A selected " + (kind == .cd ? "CD" : "floppy") + " image is missing. Choose it again.") }
                return try quotedPath(file.path)
            }
            if !paths.isEmpty {
                let command = "mount " + kind.drive + " " + paths.joined(separator:" ") + " -t " + kind.mountType
                guard command.utf8.count < 4096 else { throw LibraryError("Too many discs or excessively long paths for one DOS drive. Attach fewer images.") }
                commands.append(command)
            }
        }
        return commands
    }

    private static func validate(_ discs: [DOSDisc], in saves: URL) throws {
        guard discs.count <= 8 else { throw LibraryError("Too many media sets are attached to this game.") }
        let media = saves.appendingPathComponent(mediaName,isDirectory:true)
        let rootValues = try media.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { throw LibraryError("The saved media folder is invalid.") }
        let root = media.standardizedFileURL.resolvingSymlinksInPath()
        var seen = Set<String>()
        for disc in discs {
            guard !disc.files.isEmpty, disc.files.count <= 32 else { throw LibraryError("A media set is empty or too large.") }
            let accepted = disc.kind == .cd ? cdExtensions : floppyExtensions
            for relative in disc.files {
                guard seen.insert(disc.kind.rawValue + "\0" + relative).inserted,
                      accepted.contains((relative as NSString).pathExtension.lowercased()) else { throw LibraryError("The saved media list is invalid.") }
                let file = try contained(relative,in:root)
                let values = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      (values.fileSize ?? 0) > 0, (values.fileSize ?? 0) <= maxFileBytes,
                      isCommandSafe(file.path) else { throw LibraryError("The saved media list is invalid.") }
                if disc.kind == .cd, file.pathExtension.lowercased() == "cue" { _ = try cueSiblings(of:file) }
            }
        }
    }

    private static func cueSiblings(of cue: URL) throws -> [URL] {
        let size = try cue.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
        guard size <= 1_048_576 else { throw LibraryError("This CUE sheet is too large.") }
        let text = try String(contentsOf:cue,encoding:.utf8)
        let pattern = try NSRegularExpression(pattern: #"^FILE\s+(?:"([^"]+)"|(\S+))\s+(?:BINARY|WAVE|MP3)\s*$"#, options:.caseInsensitive)
        var names: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let value = String(line).trimmingCharacters(in:.whitespaces)
            guard value.split(whereSeparator: { $0.isWhitespace }).first?.uppercased() == "FILE" else { continue }
            let range = NSRange(value.startIndex..<value.endIndex,in:value)
            guard let match = pattern.firstMatch(in:value,range:range),
                  let capture = Range(match.range(at:match.range(at:1).location == NSNotFound ? 2 : 1),in:value) else {
                throw LibraryError("This CUE sheet has an invalid or unsupported FILE entry.")
            }
            let name = String(value[capture])
            guard names.count < 64, name == (name as NSString).lastPathComponent,
                  !name.isEmpty, cueTrackExtensions.contains((name as NSString).pathExtension.lowercased()),
                  isCommandSafe(name) else { throw LibraryError("This CUE sheet refers to an unsafe or unsupported track.") }
            if !names.contains(name) { names.append(name) }
        }
        guard !names.isEmpty else { throw LibraryError("This CUE sheet does not name any disc tracks.") }
        return try names.map { name in
            let file = cue.deletingLastPathComponent().appendingPathComponent(name)
            let checked = try regularSource(file)
            guard checked.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath() == cue.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath() else { throw LibraryError("This CUE sheet refers outside its folder.") }
            return checked
        }
    }

    private static func regularSource(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw LibraryError("Choose media files from your Mac.") }
        let original = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
        guard original.isRegularFile == true, original.isSymbolicLink != true else {
            throw LibraryError("Choose the original media file instead of a symbolic link.")
        }
        let file = url.standardizedFileURL.resolvingSymlinksInPath()
        let values = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? 0) > 0, (values.fileSize ?? 0) <= maxFileBytes,
              isCommandSafe(file.path) else { throw LibraryError("Choose a nonempty media file smaller than 4 GB without special path characters.") }
        return file
    }

    private static func mediaBytes(in root: URL) throws -> Int64 {
        guard let scan = FileManager.default.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey],options:[.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in scan {
            let values = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard values.isSymbolicLink != true else { throw LibraryError("Saved media contains a symbolic link.") }
            if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                guard size > 0, total <= maxSetBytes - size else { throw LibraryError("Selected media is larger than 8 GB.") }
                total += size
            }
        }
        return total
    }

    private static func copy(_ source: URL, to destination: URL, total: Int64) throws -> Int64 {
        let values = try source.resourceValues(forKeys:[.fileSizeKey])
        let size = Int64(values.fileSize ?? 0)
        guard total <= maxSetBytes - size else { throw LibraryError("Selected media is larger than 8 GB.") }
        try FileManager.default.copyItem(at:source,to:destination)
        return size
    }

    private static func uniqueDirectory(_ prefix: String, in root: URL) throws -> URL {
        for number in 1...999 {
            let candidate = root.appendingPathComponent(String(format:"%@-%03d",prefix,number),isDirectory:true)
            if !FileManager.default.fileExists(atPath:candidate.path) { return candidate }
        }
        throw LibraryError("Too many imported media sets.")
    }

    private static func safeName(_ name: String) throws -> String {
        guard name == (name as NSString).lastPathComponent, !name.isEmpty, isCommandSafe(name) else { throw LibraryError("This media filename is unsafe.") }
        return name
    }

    private static func contained(_ relative: String, in root: URL) throws -> URL {
        let parts = relative.split(separator:"/",omittingEmptySubsequences:false)
        guard !relative.isEmpty, !relative.contains("\\"), parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw LibraryError("A media file points outside its folder.") }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let file = canonicalRoot.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(canonicalRoot.path + "/") else { throw LibraryError("A media file points outside its folder.") }
        return file
    }

    private static func quotedPath(_ path: String) throws -> String {
        guard isCommandSafe(path) else { throw LibraryError("A media path cannot be mounted safely.") }
        return "\"" + path + "\""
    }

    private static func isCommandSafe(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("%") && !value.contains("\\") && !value.contains("\"") && !value.contains("\n") && !value.contains("\r") && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}
