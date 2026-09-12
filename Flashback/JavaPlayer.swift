// SPDX-License-Identifier: GPL-3.0-only
import Cocoa

@MainActor final class JavaSession {
    let process = Process()
    let output = Pipe()
    let keepAlive = Pipe()
    let game: Game
    private var buffer = Data()
    private var detail = ""
    private var ready = false
    private var stopping = false
    private var j2me = false
    private var timeout: Task<Void, Never>?
    var onReady: (() -> Void)?
    var onExit: ((String?) -> Void)?

    init(game: Game) { self.game = game }

    func start(library: GameLibrary, resources: URL) async throws {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let runtime = resources.appendingPathComponent("Java/\(architecture)")
        let executable = runtime.appendingPathComponent("bin/java")
        guard FileManager.default.isExecutableFile(atPath:executable.path) else {
            throw LibraryError("The Java player is missing. Reinstall the complete Flashback app.")
        }
        let runner = resources.appendingPathComponent("JavaRunner.jar")
        let saves = library.root.appendingPathComponent("Java Saves/\(game.id)")
        let temp = saves.appendingPathComponent("Temp")
        try FileManager.default.createDirectory(at:temp, withIntermediateDirectories:true)
        let working = saves.appendingPathComponent("Files")
        let source = library.folder(for:game)
        try await Task.detached(priority:.userInitiated) {
            if !FileManager.default.fileExists(atPath:working.path) {
                let staging = saves.appendingPathComponent(".setup-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at:staging) }
                try FileManager.default.copyItem(at:source, to:staging)
                try FileManager.default.moveItem(at:staging, to:working)
            }
        }.value
        guard !stopping else { onExit?(nil); return }
        let movie = try library.movie(for:game)
        try GameLibrary.validateGame(movie)
        let kind = try Self.inspectKind(executable:executable, runner:runner, movie:movie)
        j2me = kind == "J2ME"
        let j2mePlayer = resources.appendingPathComponent("J2ME/freej2me.jar")
        if j2me { guard FileManager.default.isReadableFile(atPath:j2mePlayer.path) else {
            throw LibraryError("The Java ME player is missing. Reinstall the complete Flashback app.")
        } }
        let j2meData = saves.appendingPathComponent("J2ME", isDirectory:true)
        if j2me { try FileManager.default.createDirectory(at:j2meData, withIntermediateDirectories:true) }
        let j2meMovie = j2me ? try GameLibrary.contained(game.entry,in:working) : movie
        process.executableURL = executable
        // Saved files stay writable even when the app is installed in Applications.
        let entryParent = (game.entry as NSString).deletingLastPathComponent
        process.currentDirectoryURL = j2me ? j2meData : (library.webRecord(game) != nil && !entryParent.isEmpty
            ? try GameLibrary.contained(entryParent,in:working) : working
            )
        process.environment = ["TMPDIR":temp.path, "LANG":"en_US.UTF-8", "PATH":"/usr/bin:/bin"]
        if j2me {
            process.arguments = ["-Xmx512m", "-Dfile.encoding=ISO_8859_1", "-Dflashback.title=\(game.title)",
                "-Duser.home=\(saves.path)", "-Djava.io.tmpdir=\(temp.path)", "-jar", j2mePlayer.path,
                j2meMovie.absoluteURL.absoluteString, "0", "240", "320", "2"]
        } else {
            process.arguments = ["-Xmx512m", "-Xdock:name=\(game.title)", "-Xdock:icon=\(resources.appendingPathComponent("AppIcon.icns").path)",
                "-Djava.security.manager", "-Djava.security.policy==\(resources.appendingPathComponent("Java.policy").path)",
                "-Dflashback.runner=\(runner.absoluteString)", "-Dflashback.game=\(library.folder(for:game).path)",
                "-Duser.home=\(saves.path)", "-Djava.io.tmpdir=\(temp.path)",
                "-cp", runner.path, "JavaRunner", "--play", movie.path]
        }
        process.standardOutput = output
        process.standardError = output
        process.standardInput = keepAlive
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            else { Task { @MainActor in self?.receive(data) } }
        }
        process.terminationHandler = { [weak self] child in
            Task { @MainActor in self?.finished(status:child.terminationStatus) }
        }
        do { try process.run() }
        catch { output.fileHandleForReading.readabilityHandler = nil; throw error }
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds:35_000_000_000)
            guard !Task.isCancelled, let self, !self.ready, self.process.isRunning else { return }
            self.detail = "The game did not open a window. It may need missing files or a different Java version."
            self.stop(reportFailure:true)
        }
    }

    private static func inspectKind(executable: URL, runner: URL, movie: URL) throws -> String {
        let probe = Process(), output = Pipe()
        probe.executableURL = executable
        probe.arguments = ["-Xmx128m", "-Djava.awt.headless=true", "-cp", runner.path, "JavaRunner", "--inspect", movie.path]
        probe.environment = ["PATH":"/usr/bin:/bin", "LANG":"en_US.UTF-8"]
        probe.standardOutput = output; probe.standardError = output
        try probe.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        probe.waitUntilExit()
        let text = String(decoding:data, as:UTF8.self)
        guard probe.terminationStatus == 0, let kind = text.split(whereSeparator:\.isNewline).last,
              kind == "J2ME" || kind.hasPrefix("DESKTOP:") else {
            throw LibraryError("This JAR cannot launch as a desktop or Java ME game. \(String(text.prefix(400)))")
        }
        return String(kind)
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of:10) {
            let line = String(decoding:buffer[..<end], as:UTF8.self)
            buffer.removeSubrange(...end)
            if line == "FLASHBACK_READY", !ready {
                ready = true; timeout?.cancel(); onReady?()
            } else if !line.isEmpty { detail = String((detail + "\n" + line).suffix(6000)) }
        }
        if buffer.count > 6000 { buffer = Data(buffer.suffix(6000)) }
    }

    private func finished(status: Int32) {
        timeout?.cancel()
        output.fileHandleForReading.readabilityHandler = nil
        let error: String?
        if stopping || (status == 0 && ready) { error = nil }
        else if detail.contains("not a standalone Java game") {
            error = "This JAR is an applet or a library. Add a standalone game JAR with a Main-Class or a Java ME JAR with a MIDlet manifest."
        } else if detail.contains("AccessControlException") {
            error = "This game requested access outside its game and save folders, or a feature the local Java player doesn’t support."
        } else if detail.contains("UnsupportedClassVersionError") {
            error = "This game needs a newer Java version. Flashback’s Java player supports classic Java 8 and earlier desktop games."
        } else {
            error = "“\(game.title)” couldn’t run. Add its whole folder if it needs other JARs or game files.\n\n" + String(detail.suffix(900))
        }
        onExit?(error)
    }

    func activate() {
        guard process.isRunning else { return }
        NSRunningApplication(processIdentifier:process.processIdentifier)?.activate(options:[.activateIgnoringOtherApps])
    }

    func stop(reportFailure: Bool = false) {
        stopping = !reportFailure
        timeout?.cancel()
        try? keepAlive.fileHandleForWriting.close()
        guard process.isRunning else { return }
        process.terminate()
        let child = process
        Task {
            try? await Task.sleep(nanoseconds:2_000_000_000)
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }
}
