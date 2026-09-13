// SPDX-License-Identifier: GPL-3.0-only
// A supervisor outside the child's sandbox. Closing its stdin terminates the
// native engine even when Flashback crashed or was killed. Never exec an engine
// directly: sandbox-exec failure is a launch failure, not a fallback condition.
import Foundation
import CoreGraphics
import Darwin

private func report(_ line: String) {
    let bytes = Array((line + "\n").utf8)
    _ = bytes.withUnsafeBytes { write(STDOUT_FILENO, $0.baseAddress, $0.count) }
}

private func canonical(_ path: String) -> URL {
    // Foundation can normalize /private/var back to its /var symlink. Seatbelt
    // parameters need the kernel's real path, so use realpath directly.
    if let resolved = realpath(path, nil) {
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard url.path != "/" else { return url }
    return canonical(url.deletingLastPathComponent().path).appendingPathComponent(url.lastPathComponent)
}

private func contains(_ parent: URL, _ child: URL) -> Bool {
    child.path == parent.path || child.path.hasPrefix(parent.path + "/")
}

private func fail(_ message: String) -> Never {
    report("ERROR\t" + message.replacingOccurrences(of: "\n", with: " "))
    exit(1)
}

var options: [String: String] = [:]
var engineArguments: [String] = []
let arguments = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < arguments.count {
    if arguments[index] == "--" {
        engineArguments = Array(arguments.dropFirst(index + 1))
        break
    }
    let key = arguments[index]
    guard ["--profile", "--runtime", "--executable", "--game", "--saves"].contains(key),
          options[key] == nil, index + 1 < arguments.count else {
        fail("Invalid NativeHost arguments")
    }
    options[key] = arguments[index + 1]
    index += 2
}
guard let profilePath = options["--profile"], let runtimePath = options["--runtime"],
      let executablePath = options["--executable"], let gamePath = options["--game"],
      let savesPath = options["--saves"] else {
    fail("Missing NativeHost path arguments")
}

let manager = FileManager.default
let profile = canonical(profilePath)
let runtime = canonical(runtimePath)
let executable = canonical(executablePath)
let game = canonical(gamePath)
let saves = canonical(savesPath)
// A quarantined nested runtime can trigger an AppKit translocation relaunch
// through LaunchServices. The build removes quarantine from verified runtime
// copies before signing; refuse unexpected copies instead of risking relaunch.
for path in [runtime.path, executable.path] {
    if getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0 {
        fail("The bundled runtime is quarantined; rebuild Flashback with its verified runtimes")
    }
}
guard game.path != "/", saves.path != "/", runtime.pathExtension == "app",
      !contains(game, saves), !contains(saves, game),
      !contains(runtime, saves), !contains(saves, runtime),
      contains(runtime, executable),
      ["dosbox", "scummvm", "dosbox-x"].contains(executable.lastPathComponent),
      executable.deletingLastPathComponent().path == runtime.appendingPathComponent("Contents/MacOS").path,
      manager.isExecutableFile(atPath: executable.path),
      manager.isReadableFile(atPath: profile.path),
      manager.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
    fail("Invalid runtime, overlapping data directories, or unavailable macOS sandbox")
}
var isDirectory: ObjCBool = false
guard manager.fileExists(atPath: game.path, isDirectory: &isDirectory), isDirectory.boolValue else {
    fail("The game's source directory is unavailable")
}

do {
    for relative in ["", "Temporary", "Library/Preferences/DOSBox", "Library/Caches"] {
        try manager.createDirectory(at: saves.appendingPathComponent(relative), withIntermediateDirectories: true)
    }
} catch {
    fail("Cannot create this game's private save directories: \(error.localizedDescription)")
}

let child = Process()
child.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
child.arguments = ["-D", "RUNTIME=\(runtime.path)", "-D", "EXECUTABLE=\(executable.path)",
    "-D", "GAME=\(game.path)", "-D", "SAVES=\(saves.path)", "-f", profile.path,
    executable.path] + engineArguments
child.currentDirectoryURL = saves
// Do not inherit DYLD_*, SDL_* or engine configuration variables from callers.
child.environment = ["HOME": saves.path, "CFFIXED_USER_HOME": saves.path,
    "TMPDIR": saves.appendingPathComponent("Temporary").path + "/",
    "PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8",
    "USER": NSUserName(), "LOGNAME": NSUserName(),
    "SDL_JOYSTICK_HIDAPI": "0"]
child.standardInput = FileHandle.nullDevice
child.standardOutput = FileHandle.standardError
child.standardError = FileHandle.standardError

var stopping = false
var ready = false
func stopChild() {
    guard !stopping, child.isRunning else { return }
    stopping = true
    child.terminate()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
    }
}

// Ignore SIGPIPE: if Flashback has gone away, reporting must not kill the
// supervisor before it has reaped the engine.
signal(SIGPIPE, SIG_IGN)
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
termSource.setEventHandler { stopChild() }
intSource.setEventHandler { stopChild() }
termSource.resume()
intSource.resume()

child.terminationHandler = { process in
    DispatchQueue.main.async {
        let status = process.terminationReason == .exit
            ? process.terminationStatus : 128 + process.terminationStatus
        report("EXIT\t\(status)")
        exit(status)
    }
}
do { try child.run() }
catch { fail("Cannot start the sandboxed native runtime: \(error.localizedDescription)") }
report("STARTED\t\(child.processIdentifier)")

DispatchQueue.global(qos: .utility).async {
    var buffer = [UInt8](repeating: 0, count: 256)
    while true {
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        if count > 0 { continue }
        if count < 0 && errno == EINTR { continue }
        DispatchQueue.main.async { stopChild() }
        break
    }
}

let windowTimer = DispatchSource.makeTimerSource(queue: .main)
windowTimer.schedule(deadline: .now(), repeating: .milliseconds(150))
windowTimer.setEventHandler {
    guard !ready, !stopping, child.isRunning,
          let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]] else { return }
    // Window metadata needs no Screen Recording permission. Never infer
    // readiness from elapsed time or the mere existence of the process.
    if windows.contains(where: {
        ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == child.processIdentifier &&
        ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 &&
        ($0[kCGWindowIsOnscreen as String] as? Bool) == true
    }) {
        ready = true
        report("READY\t\(child.processIdentifier)")
    }
}
windowTimer.resume()
dispatchMain()
