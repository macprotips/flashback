// SPDX-License-Identifier: GPL-3.0-only
import Cocoa

struct NativeLaunch: Sendable {
    let helper: URL
    let arguments: [String]
    let saves: URL

    static func prepare(game: Game, library: GameLibrary, resources: URL, dosMode: DOSLaunchMode = .game) throws -> Self {
        let fm = FileManager.default
        let source = library.folder(for:game).standardizedFileURL.resolvingSymlinksInPath()
        let saves = library.root.appendingPathComponent("Native Saves/\(game.id)")
        try fm.createDirectory(at:saves,withIntermediateDirectories:true)
        let canonicalSaves = saves.standardizedFileURL.resolvingSymlinksInPath()
        let helper = resources.deletingLastPathComponent().appendingPathComponent("MacOS/NativeHost")
        let policy = resources.appendingPathComponent("Native.policy")
        guard fm.isExecutableFile(atPath:helper.path), fm.isReadableFile(atPath:policy.path) else { throw LibraryError("The native game host is missing. Reinstall the complete Flashback app.") }
        let runtime: URL, executable: URL, engineArguments: [String]
        if game.isDOS {
            runtime = resources.appendingPathComponent("DOS/DOSBox Staging.app")
            executable = runtime.appendingPathComponent("Contents/MacOS/dosbox")
            let working = canonicalSaves.appendingPathComponent("Files")
            if !fm.fileExists(atPath:working.path) {
                let staging = canonicalSaves.appendingPathComponent(".setup-" + UUID().uuidString)
                defer { try? fm.removeItem(at:staging) }
                try fm.copyItem(at:source,to:staging); try fm.moveItem(at:staging,to:working)
            }
            _ = try GameLibrary.contained("Files/" + game.entry,in:canonicalSaves)
            let options = try DOSOptions.load(from:canonicalSaves)
            guard working.path.rangeOfCharacter(from:CharacterSet(charactersIn:"\"\n\r")) == nil else { throw LibraryError("The save folder path contains characters DOSBox cannot mount. Choose a different library location.") }
            let requestedEntry: String?
            switch dosMode {
            case .game: requestedEntry = options.launchEntry ?? game.entry
            case .prompt: requestedEntry = nil
            case .program(let program): requestedEntry = program
            }
            let parts: [String]
            if let requestedEntry {
                guard DOSOptions.isDOSPath(requestedEntry) else {
                    throw LibraryError("Flashback requires DOS 8.3 executable paths without percent signs or a leading @.")
                }
                let program = try GameLibrary.contained(requestedEntry,in:working)
                guard try LegacyImport.isDOS(program) else {
                    throw LibraryError("The selected DOS program is missing or is not a supported DOS executable.")
                }
                parts = requestedEntry.split(separator:"/").map(String.init)
            } else { parts = [] }
            let config = canonicalSaves.appendingPathComponent("dosbox.conf")
            try fm.createDirectory(at:canonicalSaves.appendingPathComponent("Captures"),withIntermediateDirectories:true)
            try Data(try options.configText(saves:canonicalSaves).utf8).write(to:config,options:.atomic)
            // Do not queue exit: DOSBox can process it before the program runs.
            // Games return to the DOS prompt; Quit Game closes the supervised host.
            var commands = ["mount c \"\(working.path)\"", "c:"]
            commands += try DOSDiscs.commands(from:canonicalSaves)
            // DOSBox's mixer uses a 0...100 percentage. Apply this before
            // secure mode so the imported program cannot replace the command.
            commands.append("mixer master \(Int((game.playbackVolume * 100).rounded())) /noshow")
            commands.append("config -securemode")
            if let executable = parts.last {
                let directory = parts.dropLast().joined(separator:"\\")
                if !directory.isEmpty { commands.append("cd " + directory) }
                // Paths and arguments are independently constrained before they
                // are placed in DOSBox's command interpreter.
                let arguments = dosMode == .game ? options.launchArguments : []
                commands.append("call " + executable + (arguments.isEmpty ? "" : " " + arguments.joined(separator:" ")))
            }
            engineArguments = ["--noprimaryconf","--nolocalconf","--noautoexec","--conf",config.path] + commands.flatMap { ["-c",$0] }
        } else {
            runtime = resources.appendingPathComponent("ScummVM/ScummVM.app")
            executable = runtime.appendingPathComponent("Contents/MacOS/scummvm")
            let descriptor = try DirectorLaunch.read(library.movie(for:game))
            let directory = descriptor.directory == "." ? source : try GameLibrary.contained(descriptor.directory,in:source)
            guard try LegacyImport.detectDirector(in:directory,resources:resources).contains(descriptor.gameID) else { throw LibraryError("ScummVM no longer detects this Director game. Add its complete original data folder.") }
            let volume = Int((game.playbackVolume * 255).rounded())
            engineArguments = ["--config=" + canonicalSaves.appendingPathComponent("scummvm.ini").path,
                "--savepath=" + canonicalSaves.path,"--screenshotpath=" + canonicalSaves.path,
                "--logfile=" + canonicalSaves.appendingPathComponent("scummvm.log").path,
                "--path=" + directory.path,"--no-fullscreen",
                "--music-volume=\(volume)","--sfx-volume=\(volume)","--speech-volume=\(volume)",descriptor.gameID]
        }
        guard fm.isExecutableFile(atPath:executable.path) else { throw LibraryError("The \(game.isDOS ? "DOS" : "Director") runtime is missing. Reinstall the complete app.") }
        return Self(helper:helper,arguments:["--profile",policy.path,"--runtime",runtime.path,"--executable",executable.path,
            "--game",source.path,"--saves",canonicalSaves.path,"--"] + engineArguments,saves:canonicalSaves)
    }
}

@MainActor final class NativeSession {
    let game: Game
    private let process = Process(), output = Pipe(), errors = Pipe(), keepAlive = Pipe()
    private var buffer = Data(), detail = "", childPID: pid_t?
    private var diagnostics = "", diagnosticsURL: URL?
    private var ready = false, stopping = false
    private var timeout: Task<Void,Never>?
    var onReady: (() -> Void)?
    var onExit: ((String?) -> Void)?
    var isRunning: Bool { process.isRunning }
    var processIdentifier: pid_t? { childPID }
    init(game: Game) { self.game = game }

    func start(library: GameLibrary, resources: URL, dosMode: DOSLaunchMode = .game) async throws {
        let game = game
        let launch = try await Task.detached(priority:.userInitiated) { try NativeLaunch.prepare(game:game,library:library,resources:resources,dosMode:dosMode) }.value
        guard !stopping else { onExit?(nil); return }
        diagnosticsURL = launch.saves.appendingPathComponent("native-session.log")
        diagnostics = "Flashback native session started for \(game.title)\n"
        writeDiagnostics()
        process.executableURL = launch.helper; process.arguments = launch.arguments
        process.currentDirectoryURL = launch.saves
        process.environment = ["PATH":"/usr/bin:/bin", "LANG":"en_US.UTF-8"]
        process.standardInput = keepAlive; process.standardOutput = output; process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            else { Task { @MainActor in self?.receive(data) } }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            else { Task { @MainActor in guard let self else { return }; let text = String(decoding:data,as:UTF8.self); self.detail = String((self.detail + text).suffix(6000)); self.appendDiagnostics(text) } }
        }
        process.terminationHandler = { [weak self] child in Task { @MainActor in self?.finished(child.terminationStatus) } }
        do { try process.run() } catch {
            output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil; appendDiagnostics("Launch error: \(error.localizedDescription)\n"); throw error
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds:35_000_000_000)
            guard !Task.isCancelled, let self, !self.ready, self.process.isRunning else { return }
            self.detail = "The game did not open a window. It may need missing data files or an unsupported engine feature."
            self.stop(reportFailure:true)
        }
    }
    private func receive(_ data: Data) {
        appendDiagnostics(String(decoding:data,as:UTF8.self))
        buffer.append(data)
        while let end = buffer.firstIndex(of:10) {
            let line = String(decoding:buffer[..<end],as:UTF8.self); buffer.removeSubrange(...end)
            let fields = line.split(separator:"\t",maxSplits:1).map(String.init)
            if fields.count == 2, ["STARTED","READY"].contains(fields[0]), let pid = Int32(fields[1]) { childPID = pid }
            if fields.first == "READY", !ready { ready = true; timeout?.cancel(); onReady?() }
            if fields.first == "ERROR" { detail = String(line.suffix(900)) }
        }
        if buffer.count > 6000 { buffer = Data(buffer.suffix(6000)) }
    }
    private func finished(_ status: Int32) {
        appendDiagnostics("Native session ended with status \(status)\n")
        timeout?.cancel(); output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil
        let recovery = game.isDOS ? "\n\nOpen DOS Settings to check the starting program, run setup, or attach a missing disc. The latest log is in Show Save Files." : ""
        let message = stopping || (ready && status == 0) ? nil : "“\(game.title)” couldn’t run.\n\n" + String(detail.suffix(900)) + recovery
        onExit?(message)
    }
    func activate() { if let childPID { NSRunningApplication(processIdentifier:childPID)?.activate(options:[]) } }
    func stop(reportFailure: Bool = false) {
        stopping = !reportFailure; timeout?.cancel(); try? keepAlive.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
    private func appendDiagnostics(_ text: String) {
        let combined = diagnostics + text
        diagnostics = combined.count <= 12_000 ? combined : String(combined.prefix(4000)) + "\n[Middle of log omitted]\n" + String(combined.suffix(7900))
        writeDiagnostics()
    }
    private func writeDiagnostics() {
        guard let diagnosticsURL else { return }
        try? Data(diagnostics.utf8).write(to:diagnosticsURL,options:.atomic)
    }
}
