// SPDX-License-Identifier: GPL-3.0-only
import Foundation
@main struct DOSLaunchChecks {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("pass a built app") }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DOS-launch-" + UUID().uuidString)
        defer { try? fm.removeItem(at:root) }
        let source = root.appendingPathComponent("Original"), library = GameLibrary(root:root.appendingPathComponent("Library"))
        try fm.createDirectory(at:source,withIntermediateDirectories:true)
        let payload = Data([0xcd,0x20])
        try payload.write(to:source.appendingPathComponent("PLAY.COM")); try payload.write(to:source.appendingPathComponent("SETUP.COM"))
        var game = try library.importGame(library.inspect(source),entry:"PLAY.COM")
        game.volume = 0.35
        let resources = URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("Contents/Resources")
        let first = try NativeLaunch.prepare(game:game,library:library,resources:resources)
        var options = DOSOptions(speed:.fixed(4000),launchEntry:"SETUP.COM",launchArguments:["/level:2"])
        try options.save(to:first.saves)
        let play = try NativeLaunch.prepare(game:game,library:library,resources:resources)
        guard play.arguments.contains("call SETUP.COM /level:2"),
              play.arguments.contains("mixer master 35 /noshow") else { fatalError("override, arguments, or volume ignored") }
        let setup = try NativeLaunch.prepare(game:game,library:library,resources:resources,dosMode:.program("SETUP.COM"))
        guard setup.arguments.contains("call SETUP.COM"), !setup.arguments.contains("call SETUP.COM /level:2") else { fatalError("setup received game arguments") }
        let prompt = try NativeLaunch.prepare(game:game,library:library,resources:resources,dosMode:.prompt)
        guard !prompt.arguments.contains(where:{$0.hasPrefix("call ")}), prompt.arguments.contains("config -securemode") else { fatalError("prompt launched game or lost isolation") }
        options.launchEntry = "MISSING.COM"; try options.save(to:first.saves)
        do { _ = try NativeLaunch.prepare(game:game,library:library,resources:resources); fatalError("missing executable accepted") } catch { }
        guard try Data(contentsOf:source.appendingPathComponent("PLAY.COM")) == payload else { fatalError("source changed") }
        print("PASS: launch overrides/arguments, per-game volume, setup arguments isolation, DOS prompt without autolaunch, missing program failure, original preservation")
    }
}
