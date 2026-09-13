// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@main struct DOSDiscChecks {
    static func main() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("Flashback-DOSDiscChecks-" + UUID().uuidString,isDirectory:true)
        defer { try? fm.removeItem(at:scratch) }
        try fm.createDirectory(at:scratch,withIntermediateDirectories:true)
        let source = scratch.appendingPathComponent("Original Media",isDirectory:true)
        let saves = scratch.appendingPathComponent("Native Saves/game",isDirectory:true)
        try fm.createDirectory(at:source,withIntermediateDirectories:true)

        let iso = source.appendingPathComponent("Disc One.iso")
        try makeISO(at:iso,workspace:scratch)
        let track = source.appendingPathComponent("Track  01.bin")
        try fm.copyItem(at:iso,to:track)
        let cue = source.appendingPathComponent("Disc Two.cue")
        try Data("FILE \"Track  01.bin\" BINARY\n  TRACK 01 MODE1/2048\n".utf8).write(to:cue)
        let floppy = source.appendingPathComponent("Install.ima")
        try floppyImage().write(to:floppy)
        let original = [iso:try Data(contentsOf:iso), cue:try Data(contentsOf:cue), track:try Data(contentsOf:track), floppy:try Data(contentsOf:floppy)]

        let cds = try DOSDiscs.importMedia(urls:[iso,cue],into:saves,kind:.cd)
        let floppies = try DOSDiscs.importMedia(urls:[floppy],into:saves,kind:.floppy)
        try DOSDiscs.save([cds,floppies],to:saves)
        guard try DOSDiscs.load(from:saves) == [cds,floppies] else { throw CheckFailure("saved media did not round-trip") }
        let commands = try DOSDiscs.commands(from:saves)
        guard commands.count == 2, commands[0].hasPrefix("mount d "), commands[0].contains("Disc One.iso"), commands[0].contains("Disc Two.cue"), commands[0].hasSuffix(" -t cdrom"),
              commands[1].hasPrefix("mount a "), commands[1].contains("Install.ima"), commands[1].hasSuffix(" -t floppy") else { throw CheckFailure("mount commands lost media order or type") }
        for (url,data) in original { guard try Data(contentsOf:url) == data else { throw CheckFailure("import changed an original media file") } }
        let copiedCue = saves.appendingPathComponent("Media/") .appendingPathComponent(cds.files[1])
        guard fm.fileExists(atPath:copiedCue.path), fm.fileExists(atPath:copiedCue.deletingLastPathComponent().appendingPathComponent("Track  01.bin").path) else { throw CheckFailure("CUE sibling was not copied privately") }

        try expectFailure("CUE traversal") {
            let bad = source.appendingPathComponent("escape.cue")
            try Data("FILE \"../outside.bin\" BINARY\n".utf8).write(to:bad)
            _ = try DOSDiscs.importMedia(urls:[bad],into:saves,kind:.cd)
        }
        try expectFailure("CUE symlink") {
            let linked = source.appendingPathComponent("linked.bin")
            try fm.createSymbolicLink(at:linked,withDestinationURL:track)
            let bad = source.appendingPathComponent("symlink.cue")
            try Data("FILE \"linked.bin\" BINARY\n".utf8).write(to:bad)
            _ = try DOSDiscs.importMedia(urls:[bad],into:saves,kind:.cd)
        }
        try expectFailure("command injection filename") {
            let bad = source.appendingPathComponent("bad\nmount z evil.iso")
            try Data([1]).write(to:bad)
            _ = try DOSDiscs.importMedia(urls:[bad],into:saves,kind:.cd)
        }
        try expectFailure("raw MDF") {
            let mdf = source.appendingPathComponent("disc.mdf")
            try Data([1]).write(to:mdf)
            _ = try DOSDiscs.importMedia(urls:[mdf],into:saves,kind:.cd)
        }

        guard CommandLine.arguments.count == 2 else { throw CheckFailure("pass the DOSBox Staging executable as the only argument") }
        try runtimeMountCheck(URL(fileURLWithPath:CommandLine.arguments[1]),commands:commands)
        print("PASS: private ISO/CUE/BIN and floppy import preserves sources, rejects unsafe media, persists stable swap order, and DOSBox Staging mounts CD and floppy images.")
    }

    private static func floppyImage() -> Data {
        var image = Data(repeating:0,count:1_474_560)
        image[0] = 0xeb; image[1] = 0x3c; image[2] = 0x90
        image.replaceSubrange(3..<11,with:Data("MSDOS5.0".utf8))
        image[11] = 0; image[12] = 2 // 512-byte sectors
        image[13] = 1; image[14] = 1; image[16] = 2; image[17] = 224
        image[19] = 0x40; image[20] = 0x0b; image[21] = 0xf0; image[22] = 9
        image[24] = 18; image[26] = 2; image[510] = 0x55; image[511] = 0xaa
        return image
    }

    private static func makeISO(at output: URL, workspace: URL) throws {
        let contents = workspace.appendingPathComponent("ISO Contents",isDirectory:true)
        try FileManager.default.createDirectory(at:contents,withIntermediateDirectories:true)
        try Data("DOSBox Staging mount check\n".utf8).write(to:contents.appendingPathComponent("README.TXT"))
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath:"/usr/bin/hdiutil")
        task.arguments = ["makehybrid","-iso","-o",output.path,contents.path]
        task.standardOutput = pipe; task.standardError = pipe
        try task.run(); task.waitUntilExit()
        guard task.terminationStatus == 0, FileManager.default.fileExists(atPath:output.path) else {
            throw CheckFailure("could not create an ISO test image: " + String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self))
        }
    }

    private static func runtimeMountCheck(_ runtime: URL, commands: [String]) throws {
        guard FileManager.default.isExecutableFile(atPath:runtime.path) else { throw CheckFailure("DOSBox Staging 0.83 executable is missing") }
        let task = Process(), output = Pipe()
        task.executableURL = runtime
        task.arguments = ["--noprimaryconf","--nolocalconf","--noautoexec"] + commands.flatMap { ["-c",$0] } + ["-c","mount","--exit"]
        task.environment = ["PATH":"/usr/bin:/bin","LANG":"en_US.UTF-8","SDL_VIDEODRIVER":"dummy"]
        task.standardOutput = output; task.standardError = output
        try task.run(); task.waitUntilExit()
        let text = String(decoding:output.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self)
        guard task.terminationStatus == 0, text.contains("MSCDEX installed"),
              !text.contains("Can't create drive from file"), !text.contains("Failure:") else { throw CheckFailure("DOSBox Staging did not mount generated media: \(text.suffix(1800))") }
    }

    private static func expectFailure(_ name: String, _ body: () throws -> Void) throws {
        do { try body() }
        catch { return }
        throw CheckFailure("expected failure: \(name)")
    }
}

private struct CheckFailure: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
