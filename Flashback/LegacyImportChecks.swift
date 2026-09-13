// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@main struct LegacyChecks {
    static func main() throws {
        func check(_ value: @autoclosure () throws -> Bool) throws { let result = try value(); assert(result) }
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("Flashback-legacy-tests-" + UUID().uuidString)
        try fm.createDirectory(at:temp,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:temp) }
        let library = GameLibrary(root:temp.appendingPathComponent("Library"))
        let resources = temp.appendingPathComponent("Resources")
        func reject(_ work: () throws -> Void) { do { try work(); fatalError("Expected rejection") } catch {} }
        let swf = Data([70,87,83,8,16,0,0,0,8,0,0,12,1,0,0,0])
        let exe = temp.appendingPathComponent("Space + café.exe")
        let projector = Data("MZtrusted-fixture-stub".utf8) + swf + Data([0x56,0x34,0x12,0xfa,16,0,0,0])
        try projector.write(to:exe)
        guard let range = LegacyImport.flashProjector(in:projector) else { fatalError("Projector missing") }
        assert(projector.subdata(in:range) == swf)
        assert(LegacyImport.flashProjector(in:projector.dropLast()) == nil)
        var corrupt = projector; corrupt[corrupt.count - 1] = 0x7f
        assert(LegacyImport.flashProjector(in:corrupt) == nil)
        let plan = try library.prepare(exe,resources:resources)
        defer { if let p = plan.temporaryDirectory { try? fm.removeItem(at:p) } }
        assert(plan.movies == ["Space + café.swf"])
        let game = try library.importGame(plan,entry:plan.movies[0])
        assert(game.isFlash)
        let imported = try Data(contentsOf:library.movie(for:game)); assert(imported == swf)
        let original = try Data(contentsOf:exe); assert(original == projector)
        assert(!fm.fileExists(atPath:exe.deletingPathExtension().appendingPathExtension("swf").path))
        let again = try library.importGame(plan,entry:plan.movies[0]); assert(again.id == game.id)
        let windows = temp.appendingPathComponent("Windows.exe")
        var pe = Data(repeating:0,count:128); pe[0] = 77; pe[1] = 90; pe[60] = 64; pe[64] = 80; pe[65] = 69
        try pe.write(to:windows); try check(try !LegacyImport.isDOS(windows))
        reject { _ = try library.prepare(windows,resources:resources) }
        let dos = temp.appendingPathComponent("DOS.exe")
        pe[64] = 0; pe[65] = 0; try pe.write(to:dos)
        try check(try LegacyImport.isDOS(dos))
        try Data().write(to:temp.appendingPathComponent("EMPTY.COM"))
        try Data().write(to:temp.appendingPathComponent("EMPTY.BAT"))
        try check(try LegacyImport.entries(["EMPTY.COM","EMPTY.BAT"],in:temp).isEmpty)
        let folder = temp.appendingPathComponent("Applet")
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        let html = folder.appendingPathComponent("play.html")
        let page = "<html><applet code='sample.Game.class' archive='game.jar,helper.jar' width='320' height='240'><param name='level' value='A &amp; B'></applet></html>"
        try Data(page.utf8).write(to:html)
        for name in ["game.jar","helper.jar"] { try Data([80,75,3,4]).write(to:folder.appendingPathComponent(name)) }
        let appletPlan = try library.prepare(html,resources:resources)
        defer { if let p = appletPlan.temporaryDirectory { try? fm.removeItem(at:p) } }
        assert(appletPlan.movies == ["play.flashback-applet-1.jnlp"])
        let desc = try LegacyImport.jnlpDocument(appletPlan.source.appendingPathComponent(appletPlan.movies[0]))
        try check(try desc.nodes(forXPath:"//applet-desc/@main-class").first?.stringValue == "sample.Game")
        try check(try desc.nodes(forXPath:"//param/@value").first?.stringValue == "A & B")
        try check(try desc.nodes(forXPath:"//jar").count == 2)
        assert(!fm.fileExists(atPath:folder.appendingPathComponent("play.flashback-applet-1.jnlp").path))
        let appletGame = try library.importGame(appletPlan,entry:appletPlan.movies[0]); assert(appletGame.isJava && !appletGame.isHTML)
        let parentArchive = folder.appendingPathComponent("parent.html")
        try fm.createDirectory(at:folder.appendingPathComponent("lib"),withIntermediateDirectories:true)
        try Data("<applet code='sample.Game' codebase='lib/' archive='../game.jar'></applet>".utf8).write(to:parentArchive)
        let parentPlan = try library.prepare(parentArchive,resources:resources)
        defer { if let p = parentPlan.temporaryDirectory { try? fm.removeItem(at:p) } }
        let parentDesc = try LegacyImport.jnlpDocument(parentPlan.source.appendingPathComponent(parentPlan.movies[0]))
        try check(try parentDesc.nodes(forXPath:"//jar/@href").first?.stringValue == "../game.jar")
        try Data("<applet code='Game' archive='../secret.jar'></applet>".utf8).write(to:html)
        reject { _ = try library.prepare(html,resources:resources) }
        let bad = folder.appendingPathComponent("bad.jnlp")
        try Data("<!DOCTYPE jnlp [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><jnlp>&x;</jnlp>".utf8).write(to:bad)
        reject { _ = try LegacyImport.jnlpDocument(bad) }
        try Data("<jnlp codebase='https://example.com/game/'><resources><jar href='game.jar'/><jar href='helper.jar'/></resources><application-desc main-class='sample.Main'><argument>one two</argument></application-desc></jnlp>".utf8).write(to:bad)
        let jnlpPlan = try library.prepare(bad,resources:resources)
        defer { if let p = jnlpPlan.temporaryDirectory { try? fm.removeItem(at:p) } }
        let local = try LegacyImport.jnlpDocument(jnlpPlan.source.appendingPathComponent("bad.jnlp"))
        assert(local.rootElement()?.attribute(forName:"codebase") == nil)
        assert(jnlpPlan.movies == ["bad.jnlp"])
        try check(try LegacyImport.jnlpDocument(bad).rootElement()?.attribute(forName:"codebase") != nil)
        print("PASS: projector extraction, malformed trailers, original preservation, duplicates, DOS/Windows detection, applet parameters/companions/relative codebases, local JNLP normalization and unsafe XML/paths")
    }
}
