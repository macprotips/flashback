// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit
import ImageIO

struct Game: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    let entry: String
    let bytes: Int64
    let added: Date
    var lastPlayed: Date?
    var favorite = false
    /// A nil value is the backward-compatible default for libraries written
    /// before per-game volume was added. Persist values in the normalized
    /// 0...1 range so every runtime adapter receives the same setting.
    var volume: Double? = nil
    var playbackVolume: Double { min(max(volume ?? 1, 0), 1) }
    var isJava: Bool { ["jar", "jnlp"].contains((entry as NSString).pathExtension.lowercased()) }
    var isDOS: Bool { ["exe", "com", "bat"].contains((entry as NSString).pathExtension.lowercased()) }
    var isScummVM: Bool { (entry as NSString).pathExtension.lowercased() == "scummvm" }
    var isClassicWindows: Bool { (entry as NSString).pathExtension.lowercased() == "win98" }
    var isNative: Bool { isDOS || isScummVM }
    var isHTML: Bool { ["html", "htm"].contains((entry as NSString).pathExtension.lowercased()) }
    var isShockwave: Bool { ["dcr", "dir", "dxr"].contains((entry as NSString).pathExtension.lowercased()) }
    var isFlash: Bool { (entry as NSString).pathExtension.lowercased() == "swf" }
    var format: String { isClassicWindows ? "WINDOWS 98" : isDOS ? "DOS" : isScummVM ? "DIRECTOR · SCUMMVM" : isJava ? "JAVA" : (isHTML ? "HTML5" : (isShockwave ? "SHOCKWAVE" : "SWF")) }
}

struct ClassicWindowsGameManifest: Codable, Sendable, Equatable {
    let version: Int
    let kind: String
    let payload: String
    let originalName: String
}

struct ImportPlan: Sendable {
    let source: URL
    let files: [String]
    var movies: [String]
    let bytes: Int64
    let isFolder: Bool
    var temporaryDirectory: URL? = nil
    var suggestedTitle: String? = nil
}

struct LibraryError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct GameLibrary: Sendable {
    let root: URL
    private var index: URL { root.appendingPathComponent("Library.json") }
    var gamesDirectory: URL { root.appendingPathComponent("Games", isDirectory:true) }

    func load() throws -> [Game] {
        guard FileManager.default.fileExists(atPath:index.path) else { return [] }
        let games = try JSONDecoder().decode([Game].self, from:Data(contentsOf:index))
        guard Set(games.map(\.id)).count == games.count else { throw LibraryError("The library contains duplicate entries.") }
        for game in games {
            guard game.id.count == 64, game.id.allSatisfy({ "0123456789abcdef".contains($0) }),
                  !game.title.isEmpty, game.bytes >= 0,
                  game.volume.map({ $0.isFinite && (0...1).contains($0) }) ?? true else {
                throw LibraryError("The saved library could not be read safely.")
            }
            _ = try Self.contained(game.entry, in:folder(for:game))
        }
        return games
    }

    func save(_ games: [Game]) throws {
        guard games.allSatisfy({ $0.volume.map({ $0.isFinite && (0...1).contains($0) }) ?? true }) else {
            throw LibraryError("Game volume must be between 0 and 100 percent.")
        }
        try FileManager.default.createDirectory(at:root, withIntermediateDirectories:true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(games).write(to:index, options:.atomic)
    }

    func folder(for game: Game) -> URL { gamesDirectory.appendingPathComponent(game.id, isDirectory:true) }
    func movie(for game: Game) throws -> URL { try Self.contained(game.entry, in:folder(for:game)) }

    func defaultArtworkURL(_ game: Game) -> URL { root.appendingPathComponent("Covers/\(game.id).png") }
    func customArtworkURL(_ game: Game) -> URL { root.appendingPathComponent("Covers/\(game.id)-custom.png") }
    func artworkURL(_ game: Game) -> URL {
        let custom = customArtworkURL(game)
        return FileManager.default.fileExists(atPath:custom.path) ? custom : defaultArtworkURL(game)
    }

    func setArtwork(_ input: URL, for game: Game, custom: Bool = true) throws {
        guard input.isFileURL else { throw LibraryError("Choose an image from your Mac.") }
        var input = input
        input.removeAllCachedResourceValues()
        let info = try input.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
        guard info.isRegularFile == true, let size = info.fileSize, size > 0, size <= 50 * 1024 * 1024 else {
            throw LibraryError("Choose an image smaller than 50 MB.")
        }
        // Decode a bounded, orientation-correct preview instead of retaining a full-size photo.
        guard let source = CGImageSourceCreateWithURL(input as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:1120
              ] as CFDictionary) else { throw LibraryError("This image couldn’t be read. Try a PNG, JPEG, or HEIC image.") }
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil) else {
            throw LibraryError("The artwork couldn’t be saved.")
        }
        CGImageDestinationAddImage(encoder,image,nil)
        guard CGImageDestinationFinalize(encoder) else { throw LibraryError("The artwork couldn’t be saved.") }
        let destination = custom ? customArtworkURL(game) : defaultArtworkURL(game)
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        try (data as Data).write(to:destination,options:.atomic)
    }

    func restoreArtwork(_ game: Game) throws {
        let custom = customArtworkURL(game)
        if FileManager.default.fileExists(atPath:custom.path) { try FileManager.default.removeItem(at:custom) }
    }

    static func resource(_ relative: String, entry: String, in folder: URL) throws -> URL {
        // Old movies concatenate directory strings that both contain a slash.
        // Normalize those separators while still rejecting absolute paths/"..".
        let relative = relative.hasPrefix("/") ? relative : relative.split(separator:"/").joined(separator:"/")
        let direct = try contained(relative, in:folder)
        if FileManager.default.fileExists(atPath:direct.path) { return direct }
        var candidates = [relative]
        // Browser archives sometimes resolve assets from the enclosing HTML page.
        let parent = (entry as NSString).deletingLastPathComponent
        if !parent.isEmpty, relative.hasPrefix(parent + "/") {
            let rootPath = String(relative.dropFirst(parent.count + 1))
            candidates.append(rootPath)
            let fromRoot = try contained(rootPath, in:folder)
            if FileManager.default.fileExists(atPath:fromRoot.path) { return fromRoot }
        }
        // Preserved Director casts may be editable (.cst) instead of their
        // published compressed form (.cct). Both use the same cast parser.
        if ["dcr", "dir", "dxr"].contains((entry as NSString).pathExtension.lowercased()) {
            for path in candidates {
                let ext = (path as NSString).pathExtension.lowercased()
                guard let alternate = ["cct":"cst", "cst":"cct"][ext] else { continue }
                let file = try contained((path as NSString).deletingPathExtension + "." + alternate, in:folder)
                if FileManager.default.fileExists(atPath:file.path) { return file }
            }
        }
        return direct
    }

    static func contained(_ relative: String, in directory: URL) throws -> URL {
        let components = relative.split(separator:"/", omittingEmptySubsequences:false)
        guard !relative.isEmpty, !relative.contains("\\"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw LibraryError("A game file points outside its folder.")
        }
        // Resolve the existing directory first. Foundation can retain /private
        // on a destination that does not exist yet while stripping it from its
        // existing parent, making an import's staging file fail this check.
        let canonicalDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let file = canonicalDirectory.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        let base = canonicalDirectory.path + "/"
        guard file.path.hasPrefix(base) else { throw LibraryError("A game file points outside its folder.") }
        return file
    }

    static func validateMovie(_ url: URL) throws {
        let handle = try FileHandle(forReadingFrom:url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount:8) ?? Data()
        guard header.count == 8,
              ["FWS", "CWS", "ZWS"].contains(String(decoding:header.prefix(3), as:UTF8.self)),
              header[3] > 0 else { throw LibraryError("“\(url.lastPathComponent)” is not a valid Flash (.swf) file.") }
        let length = (0..<4).reduce(UInt32(0)) { $0 | UInt32(header[4 + $1]) << ($1 * 8) }
        guard length >= 8, length <= 512 * 1024 * 1024 else {
            throw LibraryError("This Flash file is damaged or too large to open.")
        }
    }

    static func validateGame(_ url: URL) throws {
        if ["dcr", "dir", "dxr"].contains(url.pathExtension.lowercased()) {
            let handle = try FileHandle(forReadingFrom:url)
            defer { try? handle.close() }
            let header = try handle.read(upToCount:12) ?? Data()
            let magic = String(decoding:header.prefix(4), as:UTF8.self)
            let codec = String(decoding:header.suffix(4), as:UTF8.self)
            let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard header.count == 12, ["RIFX", "XFIR"].contains(magic),
                  size <= 512 * 1024 * 1024,
                  (magic == "RIFX" ? ["MV93", "MC95", "FGDM", "FGDC"] : ["39VM", "59CM", "MDGF", "CDGF"]).contains(codec) else {
                throw LibraryError("“\(url.lastPathComponent)” is not a supported Shockwave movie. Choose its original .dcr, .dir, or .dxr file.")
            }
        } else if ["html", "htm"].contains(url.pathExtension.lowercased()) {
            let info = try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
            guard info.isRegularFile == true, (info.fileSize ?? 0) > 0, (info.fileSize ?? 0) <= 32 * 1024 * 1024 else {
                throw LibraryError("Choose a nonempty HTML game page smaller than 32 MB.")
            }
        } else if url.pathExtension.lowercased() == "jnlp" {
            _ = try LegacyImport.jnlpDocument(url)
        } else if url.pathExtension.lowercased() == "scummvm" {
            _ = try DirectorLaunch.read(url)
        } else if url.pathExtension.lowercased() == "win98" {
            let info = try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true,
                  let size = info.fileSize, size > 0, size <= 16_384 else {
                throw LibraryError("This Classic Windows game record is damaged.")
            }
            let data = try Data(contentsOf:url)
            guard let manifest = try? JSONDecoder().decode(ClassicWindowsGameManifest.self,from:data),
                  manifest.version == 1, ["discImage","executable","folder"].contains(manifest.kind),
                  !manifest.originalName.isEmpty, manifest.originalName.utf8.count <= 1024 else {
                throw LibraryError("This Classic Windows game record is damaged.")
            }
            let payload = try contained(manifest.payload,in:url.deletingLastPathComponent())
            let values = try payload.resourceValues(forKeys:[.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey])
            guard values.isSymbolicLink != true,
                  (manifest.kind == "folder" ? values.isDirectory == true : values.isRegularFile == true) else {
                throw LibraryError("This Classic Windows game is missing its installation files.")
            }
        } else if ["exe", "com", "bat"].contains(url.pathExtension.lowercased()) {
            guard try LegacyImport.isDOS(url) else { throw LibraryError("This executable is not a supported DOS game or Flash projector. Windows applications require a different player.") }
        } else if url.pathExtension.lowercased() == "jar" {
            let handle = try FileHandle(forReadingFrom:url)
            defer { try? handle.close() }
            guard try handle.read(upToCount:4) == Data([0x50,0x4b,0x03,0x04]) else {
                throw LibraryError("“\(url.lastPathComponent)” is not a valid Java (.jar) archive.")
            }
        } else { try validateMovie(url) }
    }

    func inspect(_ input: URL, allowEmpty: Bool = false) throws -> ImportPlan {
        guard input.isFileURL else { throw LibraryError("Add a file from your Mac.") }
        let values = try input.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw LibraryError("Add the original game files instead of a symbolic link.") }
        let source = input.standardizedFileURL.resolvingSymlinksInPath()
        let folder = values.isDirectory == true
        if !folder && !LegacyImport.extensions.contains(source.pathExtension.lowercased()) {
            throw LibraryError("Add a Flash, Java, HTML, Shockwave, DOS, or Director game, JNLP file, ZIP, or game folder.")
        }
        guard !root.path.hasPrefix(source.path + "/"), source != root else {
            throw LibraryError("Choose the game's own folder, rather than a folder containing the Flashback library.")
        }
        let base = folder ? source : source.deletingLastPathComponent()
        var files: [String] = []
        var bytes: Int64 = 0
        let keys: [URLResourceKey] = [.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey]
        func include(_ file: URL) throws {
            let info = try file.resourceValues(forKeys:Set(keys))
            guard info.isSymbolicLink != true else { throw LibraryError("This game folder contains a symbolic link. Add a folder with the actual files.") }
            if info.isDirectory == true { return }
            guard info.isRegularFile == true else { throw LibraryError("This folder contains a file that cannot be imported.") }
            let canonical = file.standardizedFileURL.resolvingSymlinksInPath()
            guard canonical.path.hasPrefix(base.path + "/") else { throw LibraryError("This game file is outside the selected folder.") }
            let relative = String(canonical.path.dropFirst(base.path.count + 1))
            _ = try Self.contained(relative, in:base)
            files.append(relative)
            bytes += Int64(info.fileSize ?? 0)
            // ponytail: bounded copying; unusually large archives should use a streaming importer.
            guard files.count <= 10_000, bytes <= 1_073_741_824 else {
                throw LibraryError("Choose a game folder smaller than 1 GB with fewer than 10,000 files.")
            }
        }
        if folder {
            var scanError: Error?
            guard let scan = FileManager.default.enumerator(at:source, includingPropertiesForKeys:keys,
                options:[.skipsHiddenFiles,.skipsPackageDescendants], errorHandler:{ _, error in scanError = error; return false }) else {
                throw LibraryError("This folder could not be opened.")
            }
            for case let file as URL in scan {
                if file.lastPathComponent == "__MACOSX" { scan.skipDescendants(); continue }
                try include(file)
            }
            if let error = scanError { throw error }
        } else { try include(source) }
        files.sort()
        let movies = files.filter { LegacyImport.extensions.contains(URL(fileURLWithPath:$0).pathExtension.lowercased()) }
        guard allowEmpty || !movies.isEmpty else { throw LibraryError("There are no recognized game entries in this folder. For a classic Director CD-ROM game, add its complete data folder.") }
        return ImportPlan(source:source, files:files, movies:movies, bytes:bytes, isFolder:folder)
    }

    // Recover compressed Shockwave bootstrap movies as data. Editable projector
    // stubs may depend on Windows Xtras and must not replace the archive entry.
    // Windows projectors are never executed.
    static func projectorMovie(in data: Data) -> Range<Int>? {
        guard data.count >= 14, data.starts(with:[0x4d, 0x5a]) else { return nil }
        var movies: [Range<Int>] = []
        for (magic, codecs, littleEndian) in [("XFIR", ["MDGF"], true), ("RIFX", ["FGDM"], false)] {
            var cursor = 2
            while cursor <= data.count - 12,
                  let match = data.range(of:Data(magic.utf8), in:cursor..<data.count) {
                let offset = match.lowerBound
                cursor = offset + 4
                guard offset <= data.count - 12,
                      codecs.contains(String(decoding:data[(offset + 8)..<(offset + 12)],as:UTF8.self)) else { continue }
                let length = (0..<4).reduce(UInt32(0)) {
                    $0 | UInt32(data[offset + 4 + $1]) << ((littleEndian ? $1 : 3 - $1) * 8)
                }
                guard length > 4, Int(length) <= data.count - offset - 8 else { continue }
                movies.append(offset..<(offset + 8 + Int(length)))
                if movies.count > 1 { return nil }
            }
        }
        return movies.first
    }

    static func recoverProjectorMovies(in directory: URL) throws {
        let fm = FileManager.default
        guard let scan = fm.enumerator(at:directory,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey],
                                       options:[.skipsHiddenFiles,.skipsPackageDescendants]) else { return }
        var executables: [URL: [URL]] = [:]
        for case let file as URL in scan where file.pathExtension.lowercased() == "exe" {
            let info = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true,
                  (info.fileSize ?? 0) <= 512 * 1024 * 1024 else { continue }
            executables[file.deletingLastPathComponent(),default:[]].append(file)
            let data = try Data(contentsOf:file,options:.mappedIfSafe)
            if let range = LegacyImport.flashProjector(in:data) {
                let target = file.deletingPathExtension().appendingPathExtension("swf")
                let movie = data.subdata(in:range)
                if fm.fileExists(atPath:target.path) {
                    guard try Data(contentsOf:target) == movie else { throw LibraryError("The projector and its neighboring SWF have the same name but different contents. Rename one before importing.") }
                } else { try movie.write(to:target,options:.withoutOverwriting) }
                try validateMovie(target)
            }
        }
        for (folder, files) in executables where files.count == 1 {
            let target = folder.appendingPathComponent("projector-loader.dcr")
            guard !fm.fileExists(atPath:target.path) else { continue }
            let data = try Data(contentsOf:files[0],options:.mappedIfSafe)
            guard let range = projectorMovie(in:data) else { continue }
            try data.subdata(in:range).write(to:target,options:.withoutOverwriting)
        }
    }

    func prepare(_ input: URL, resources: URL) throws -> ImportPlan {
        guard input.pathExtension.lowercased() == "zip" else { return try LegacyImport.prepare(input, library:self, resources:resources) }
        let info = try input.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
        guard input.isFileURL, info.isRegularFile == true, info.isSymbolicLink != true else {
            throw LibraryError("Choose the original ZIP file on your Mac.")
        }
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("Flashback-import-" + UUID().uuidString)
        try fm.createDirectory(at:temp, withIntermediateDirectories:false)
        do {
            let extracted = temp.appendingPathComponent("Game")
            #if arch(arm64)
            let architecture = "arm64"
            #else
            let architecture = "x86_64"
            #endif
            let process = Process(), output = Pipe()
            process.executableURL = resources.appendingPathComponent("Java/\(architecture)/bin/java")
            process.arguments = ["-Xmx128m", "-Djava.awt.headless=true", "-cp", resources.appendingPathComponent("JavaRunner.jar").path,
                                 "GameArchive", input.path, extracted.path]
            process.environment = ["PATH":"/usr/bin:/bin", "LANG":"en_US.UTF-8"]
            process.standardOutput = output; process.standardError = output
            try process.run()
            let result = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw LibraryError("Couldn’t unpack this ZIP. " + String(String(decoding:result, as:UTF8.self).prefix(500)))
            }
            // Discard a single enclosing folder, as Finder does for common game downloads.
            let children = try fm.contentsOfDirectory(at:extracted, includingPropertiesForKeys:[.isDirectoryKey], options:.skipsHiddenFiles)
            var source = extracted
            if children.count == 1, try children[0].resourceValues(forKeys:[.isDirectoryKey]).isDirectory == true { source = children[0] }
            try Self.recoverProjectorMovies(in:source)
            try LegacyImport.normalize(in:source,resources:resources)
            var plan = try inspect(source)
            plan.movies = try LegacyImport.entries(plan.movies,in:source)
            guard !plan.movies.isEmpty else { throw LibraryError("No supported game was found in this archive.") }
            plan.temporaryDirectory = temp
            plan.suggestedTitle = input.deletingPathExtension().lastPathComponent
            return plan
        } catch { try? fm.removeItem(at:temp); throw error }
    }

    func importGame(_ plan: ImportPlan, entry: String) throws -> Game {
        guard plan.movies.contains(entry) else { throw LibraryError("Choose a game file from this folder.") }
        let base = plan.isFolder ? plan.source : plan.source.deletingLastPathComponent()
        try Self.validateGame(Self.contained(entry, in:base))
        let fm = FileManager.default
        try fm.createDirectory(at:gamesDirectory, withIntermediateDirectories:true)
        let staging = gamesDirectory.appendingPathComponent(".import-" + UUID().uuidString, isDirectory:true)
        try fm.createDirectory(at:staging, withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:staging) }
        var hash = SHA256()
        hash.update(data:Data((entry + "\0").utf8))
        var total: Int64 = 0
        for relative in plan.files {
            let source = try Self.contained(relative, in:base)
            let info = try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true else { throw LibraryError("A game file changed while it was being added. Please try again.") }
            let target = try Self.contained(relative, in:staging)
            try fm.createDirectory(at:target.deletingLastPathComponent(), withIntermediateDirectories:true)
            try fm.copyItem(at:source, to:target)
            hash.update(data:Data((relative + "\0").utf8))
            var fileHash = SHA256()
            let handle = try FileHandle(forReadingFrom:target)
            defer { try? handle.close() }
            while let chunk = try handle.read(upToCount:65_536), !chunk.isEmpty {
                total += Int64(chunk.count)
                guard total <= 1_073_741_824 else { throw LibraryError("This game folder grew too large during import.") }
                fileHash.update(data:chunk)
            }
            hash.update(data:Data(fileHash.finalize()))
        }
        let id = hash.finalize().map { String(format:"%02x", $0) }.joined()
        let destination = gamesDirectory.appendingPathComponent(id, isDirectory:true)
        if !fm.fileExists(atPath:destination.path) { try fm.moveItem(at:staging, to:destination) }
        let rawTitle = plan.suggestedTitle ?? (plan.isFolder ? plan.source : plan.source.deletingPathExtension()).lastPathComponent
        let title = rawTitle.replacingOccurrences(of:"_", with:" ").replacingOccurrences(of:"-", with:" ")
        return Game(id:id, title:title, entry:entry, bytes:total, added:Date())
    }
}
