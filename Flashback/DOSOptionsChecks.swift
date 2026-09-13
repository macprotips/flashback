// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@main struct DOSOptionsChecks {
    static func main() throws {
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("Flashback-DOSOptions-" + UUID().uuidString)
        defer { try? fm.removeItem(at:scratch) }
        try fm.createDirectory(at:scratch,withIntermediateDirectories:true)

        guard try DOSOptions.load(from:scratch) == .defaults else { throw CheckFailure("missing DOS options did not use defaults") }
        let defaults = try DOSOptions.defaults.configText(saves:scratch)
        guard defaults.contains("fullscreen = false"), defaults.contains("nosound = false"),
              defaults.contains("mouse_capture = onclick"), defaults.contains("mididevice = coreaudio"),
              defaults.contains("mapperfile = " + scratch.appendingPathComponent("mapper.map").path),
              defaults.contains("capture_dir = " + scratch.appendingPathComponent("Captures").path),
              defaults.range(of:"[sdl]")!.lowerBound < defaults.range(of:"mapperfile =")!.lowerBound,
              defaults.range(of:"mapperfile =")!.lowerBound < defaults.range(of:"[dosbox]")!.lowerBound,
              defaults.range(of:"[capture]")!.lowerBound < defaults.range(of:"capture_dir =")!.lowerBound,
              !defaults.contains("cpu_cycles =") else { throw CheckFailure("default DOSBox config changed existing behavior") }

        let tuned = DOSOptions(speed:.fixed(25_000),fullscreen:true,soundEnabled:false,midi:.coreaudio,
                               mouseCapture:false,launchEntry:"SETUP/INSTALL.EXE",launchArguments:["-safe"])
        try tuned.save(to:scratch)
        guard try DOSOptions.load(from:scratch) == tuned else { throw CheckFailure("DOS options did not round trip") }
        let config = try tuned.configText()
        guard config.contains("cpu_cycles = 25000"), config.contains("fullscreen = true"),
              config.contains("nosound = true"), config.contains("mididevice = none"),
              config.contains("mouse_capture = seamless") else { throw CheckFailure("bounded DOS options generated the wrong config") }

        func reject(_ body: () throws -> Void) {
            do { try body(); fatalError("Expected DOS option rejection") } catch {}
        }
        reject { _ = try DOSOptions(speed:.fixed(DOSOptions.minimumCycles - 1)).configText() }
        reject { _ = try DOSOptions(launchEntry:"../SETUP.EXE").configText() }
        reject { _ = try DOSOptions(launchArguments:["&format"]).configText() }
        _ = try DOSOptions(launchArguments:["/level:2"]).configText()
        try Data("{ broken".utf8).write(to:DOSOptions.optionsURL(in:scratch),options:.atomic)
        reject { _ = try DOSOptions.load(from:scratch) }

        let files = scratch.appendingPathComponent("Files")
        try fm.createDirectory(at:files.appendingPathComponent("SETUP"),withIntermediateDirectories:true)
        var exe = Data(repeating:0,count:64); exe[0] = 0x4d; exe[1] = 0x5a
        try exe.write(to:files.appendingPathComponent("GAME.EXE"))
        try exe.write(to:files.appendingPathComponent("SETUP/INSTALL.COM"))
        try exe.write(to:files.appendingPathComponent("TOO-LONGX.EXE"))
        try Data("echo setup\n".utf8).write(to:files.appendingPathComponent("SETUP.BAT"))
        let entries = try DOSOptions.executableEntries(in:files)
        guard Set(entries) == Set(["GAME.EXE","SETUP/INSTALL.COM","SETUP.BAT"]) else { throw CheckFailure("DOS executable picker included invalid files") }
        guard DOSOptions.isDOSPath("SETUP/INSTALL.EXE"), !DOSOptions.isDOSPath("../INSTALL.EXE"),
              !DOSOptions.isDOSPath("TOO-LONGX.EXE") else { throw CheckFailure("DOS path containment failed") }
        print("DOSOptionsChecks passed")
    }
}

private struct CheckFailure: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
