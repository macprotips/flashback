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
        process.executableURL = executable
        // Saved files stay writable even when the app is installed in Applications.
        let entryParent = (game.entry as NSString).deletingLastPathComponent
        process.currentDirectoryURL = library.webRecord(game) != nil && !entryParent.isEmpty
            ? try GameLibrary.contained(entryParent,in:working) : working
        process.environment = ["TMPDIR":temp.path, "LANG":"en_US.UTF-8", "PATH":"/usr/bin:/bin"]
        process.arguments = ["-Xmx512m", "-Xdock:name=\(game.title)", "-Xdock:icon=\(resources.appendingPathComponent("AppIcon.icns").path)",
            "-Djava.security.manager", "-Djava.security.policy==\(resources.appendingPathComponent("Java.policy").path)",
            "-Dflashback.runner=\(runner.absoluteString)", "-Dflashback.game=\(library.folder(for:game).path)",
            "-Duser.home=\(saves.path)", "-Djava.io.tmpdir=\(temp.path)",
            "-cp", runner.path, "JavaRunner", "--play", movie.path]
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
            error = "This JAR is an applet or a library. Add a standalone game JAR with a Main-Class. Applet-only web pages and Java phone games aren’t supported yet."
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
