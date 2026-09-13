// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@main struct JavaRecoveryChecks {
    static func main() async throws {
        let url = URL(string:CommandLine.arguments[1])!
        let output = URL(fileURLWithPath:CommandLine.arguments[2])
        let collector = WebsiteCollector(allowLocal:true,progress:{ _ in })
        let candidates = try await collector.scan(url)
        guard let candidate = candidates.first(where:{ ["applet","jnlp"].contains($0.kind) }) else { throw LibraryError("No Java candidate") }
        let recovery = try await collector.recover(candidate,title:"Authored Java recovery")
        let library = GameLibrary(root:output)
        let plan = try library.prepare(recovery.source,resources:output.appendingPathComponent("Unused"))
        defer { if let temp = plan.temporaryDirectory { try? FileManager.default.removeItem(at:temp) } }
        guard plan.movies == ["Flashback-launch.jnlp"] else { throw LibraryError("Recovered Java launch was not selected") }
        let game = try library.importGame(plan,entry:plan.movies[0])
        print(library.folder(for:game).path)
        await collector.clean()
    }
}
