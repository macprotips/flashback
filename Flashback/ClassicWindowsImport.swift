// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

struct ClassicWindowsImportRequest: Sendable, Equatable {
    enum Kind: String, Sendable { case discImage, executable, folder }
    let source: URL
    let kind: Kind
    var displayName: String {
        let value = kind == .folder ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        return value.replacingOccurrences(of:"_",with:" ").replacingOccurrences(of:"-",with:" ")
    }
}

/// Strictly recognizes inputs that the ordinary import path cannot run. This
/// never executes or mounts the selected media; it only routes it into the
/// opt-in Classic Windows setup flow.
enum ClassicWindowsImport {
    static func directRequest(_ input: URL) -> ClassicWindowsImportRequest? {
        guard input.isFileURL, input.pathExtension.lowercased() == "iso", isISO9660(input) else { return nil }
        return ClassicWindowsImportRequest(source:input,kind:.discImage)
    }

    static func isISO9660(_ file: URL) -> Bool {
        guard let info = try? file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]),
              info.isRegularFile == true, info.isSymbolicLink != true,
              let size = info.fileSize, size >= 17 * 2048,
              let handle = try? FileHandle(forReadingFrom:file) else { return false }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset:16 * 2048)) != nil,
              let descriptor = try? handle.read(upToCount:2048), descriptor.count == 2048 else { return false }
        return descriptor[0] == 1 && descriptor[1...5] == Data("CD001".utf8) && descriptor[6] == 1
    }

    static func requestAfterStandardImportFailed(_ input: URL) -> ClassicWindowsImportRequest? {
        guard input.isFileURL else { return nil }
        let values = try? input.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else { return nil }
        if values?.isRegularFile == true, input.pathExtension.lowercased() == "exe",
           isWindowsExecutable(input) {
            return ClassicWindowsImportRequest(source:input,kind:.executable)
        }
        guard values?.isDirectory == true,
              let scan = FileManager.default.enumerator(at:input,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants]) else { return nil }
        var inspected = 0
        for case let file as URL in scan where file.pathExtension.lowercased() == "exe" {
            inspected += 1
            if inspected > 256 { return nil }
            if isWindowsExecutable(file) { return ClassicWindowsImportRequest(source:input,kind:.folder) }
        }
        return nil
    }

    static func isWindowsExecutable(_ file: URL) -> Bool {
        guard let info = try? file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]),
              info.isRegularFile == true, info.isSymbolicLink != true,
              let size = info.fileSize, size >= 68, size <= 1024 * 1024 * 1024,
              let handle = try? FileHandle(forReadingFrom:file) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount:64), header.count == 64,
              header[0] == 0x4d, header[1] == 0x5a else { return false }
        let offset = (0..<4).reduce(UInt32(0)) { $0 | UInt32(header[60 + $1]) << (8 * $1) }
        guard offset >= 64, UInt64(offset) <= UInt64(size - 4),
              (try? handle.seek(toOffset:UInt64(offset))) != nil,
              let signature = try? handle.read(upToCount:4) else { return false }
        return signature.starts(with:[0x50,0x45,0,0]) || ["NE","LE","LX"].contains(String(decoding:signature.prefix(2),as:UTF8.self))
    }
}

extension GameLibrary {
    /// Copies recognized Classic Windows installation media into the library
    /// immediately. This makes the game a durable library item even when the
    /// shared Windows 98 setup still needs to be completed or resumed.
    func importClassicWindows(_ request: ClassicWindowsImportRequest) throws -> Game {
        let fm = FileManager.default
        let source = request.source.standardizedFileURL.resolvingSymlinksInPath()
        let sourceValues = try source.resourceValues(forKeys:[.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey])
        guard sourceValues.isSymbolicLink != true,
              request.kind == .folder ? sourceValues.isDirectory == true : sourceValues.isRegularFile == true else {
            throw LibraryError("Choose the original Windows game disc, executable, or folder.")
        }
        try fm.createDirectory(at:gamesDirectory,withIntermediateDirectories:true)
        let staging = gamesDirectory.appendingPathComponent(".classic-import-" + UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:staging,withIntermediateDirectories:false)
        defer { try? fm.removeItem(at:staging) }

        let payloadRelative: String
        var inputs: [(URL,String)] = []
        if request.kind == .folder {
            payloadRelative = "Files"
            let keys: [URLResourceKey] = [.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey,.fileSizeKey]
            guard let scan = fm.enumerator(at:source,includingPropertiesForKeys:keys,options:[.skipsHiddenFiles,.skipsPackageDescendants]) else {
                throw LibraryError("This Windows game folder could not be opened.")
            }
            for case let file as URL in scan {
                let values = try file.resourceValues(forKeys:Set(keys))
                guard values.isSymbolicLink != true else { throw LibraryError("This Windows game folder contains a symbolic link.") }
                if values.isDirectory == true { continue }
                guard values.isRegularFile == true else { throw LibraryError("This Windows game folder contains an unsupported file.") }
                let resolved = file.standardizedFileURL.resolvingSymlinksInPath()
                guard resolved.path.hasPrefix(source.path + "/") else { throw LibraryError("A Windows game file is outside its selected folder.") }
                let relative = String(resolved.path.dropFirst(source.path.count + 1))
                _ = try GameLibrary.contained(relative,in:source)
                inputs.append((resolved,"Files/" + relative))
                guard inputs.count <= 20_000 else { throw LibraryError("Choose a Windows game folder with fewer than 20,000 files.") }
            }
            guard !inputs.isEmpty else { throw LibraryError("This Windows game folder is empty.") }
            inputs.sort { $0.1 < $1.1 }
        } else {
            let safeName = source.lastPathComponent.replacingOccurrences(of:"/",with:"_")
            payloadRelative = "Media/" + safeName
            inputs = [(source,payloadRelative)]
        }

        var hash = SHA256()
        hash.update(data:Data((request.kind.rawValue + "\0").utf8))
        var total: Int64 = 0
        for (input,relative) in inputs {
            let target = try GameLibrary.contained(relative,in:staging)
            try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            guard fm.createFile(atPath:target.path,contents:nil) else { throw LibraryError("Flashback could not copy this Windows game.") }
            let reader = try FileHandle(forReadingFrom:input), writer = try FileHandle(forWritingTo:target)
            defer { try? reader.close(); try? writer.close() }
            var fileHash = SHA256()
            while let chunk = try reader.read(upToCount:1_048_576), !chunk.isEmpty {
                total += Int64(chunk.count)
                guard total <= 4 * 1024 * 1024 * 1024 else { throw LibraryError("Choose Windows game media smaller than 4 GB.") }
                try writer.write(contentsOf:chunk)
                fileHash.update(data:chunk)
            }
            hash.update(data:Data((relative + "\0").utf8))
            hash.update(data:Data(fileHash.finalize()))
        }
        let id = hash.finalize().map { String(format:"%02x",$0) }.joined()
        let entry = "ClassicWindows.win98"
        let manifest = ClassicWindowsGameManifest(version:1,kind:request.kind.rawValue,payload:payloadRelative,originalName:source.lastPathComponent)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(manifest).write(to:staging.appendingPathComponent(entry),options:.atomic)
        let destination = gamesDirectory.appendingPathComponent(id,isDirectory:true)
        if fm.fileExists(atPath:destination.path) {
            try GameLibrary.validateGame(destination.appendingPathComponent(entry))
        } else {
            try fm.moveItem(at:staging,to:destination)
        }
        let title = request.displayName.isEmpty ? "Classic Windows Game" : request.displayName
        return Game(id:id,title:title,entry:entry,bytes:total,added:Date())
    }

    func classicWindowsManifest(for game: Game) throws -> (ClassicWindowsGameManifest, URL) {
        guard game.isClassicWindows else { throw LibraryError("This is not a Classic Windows game.") }
        let entry = try movie(for:game)
        try Self.validateGame(entry)
        let manifest = try JSONDecoder().decode(ClassicWindowsGameManifest.self,from:Data(contentsOf:entry))
        return (manifest,try Self.contained(manifest.payload,in:entry.deletingLastPathComponent()))
    }
}
