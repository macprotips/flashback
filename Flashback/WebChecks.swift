// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@main struct WebsiteChecks {
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws { if try !condition() { throw LibraryError(message) } }
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data(("FAIL: " + error.localizedDescription + "\n").utf8)); exit(1) }
    }
    static func run() async throws {
        let base = URL(string:CommandLine.arguments[1])!, fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("Flashback-web-check-" + UUID().uuidString)
        try fm.createDirectory(at:temp,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:temp) }
        let publicURL = URL(string:"https://games.example/play/index.html")!
        let html = """
        <!doctype html><html><head><title>One &amp; Two</title><base href="/game/"></head><body>
        <object><param name="movie" value="Main.SWF?x=1&amp;y=two"><param name="flashvars" value="lang=en&amp;token=a%3Db"></object>
        <iframe src="nested/play.html"></iframe><script src="loader.js"></script>
        <applet codebase="java" archive="game.jar, support.jar"></applet></body></html>
        """
        var page = WebPage.parse(html,url:publicURL)
        try require(page.title == "One & Two" && page.base.absoluteString == "https://games.example/game/","Legacy HTML title/base parsing: \(page.title), \(page.base)")
        let flash = page.candidates.first { $0.kind == "swf" }!
        try require(flash.url.path == "/game/Main.SWF" && flash.parameters["token"] == "a=b" && flash.parameters["y"] == "two","Embed URL and FlashVars")
        try require(page.candidates.filter { $0.kind == "jar" }.count == 2 && page.candidates.first { $0.kind == "jar" }?.companions.count == 1,"Applet archive/codebase discovery")
        page.addScript("const root='level/'; var flashvars={language:'fr'}; swfobject.embedSWF(root+'start.swf', 'game'); AC_FL_RunContent('movie','old');")
        try require(page.candidates.contains { $0.url.path == "/game/level/start.swf" && $0.parameters["language"] == "fr" },"SWFObject concatenated URL and parameters")
        try require(page.candidates.contains { $0.url.path == "/game/old.swf" },"AC_FL_RunContent movie extension")
        try require(WebPage.parse("<canvas></canvas>",url:publicURL).candidates.first?.kind == "html","HTML canvas discovery")
        let pageBase = WebPage.parse("<object data='/download?id=1' type='application/x-shockwave-flash'></object>",url:publicURL).candidates.first!
        try require(pageBase.kind == "swf" && pageBase.baseURL?.absoluteString == "https://games.example/play/","Extensionless embed or HTML document base was lost")
        let explicitBase = WebPage.parse("<embed src='game.swf' base='/media'>",url:publicURL).candidates.first!
        try require(explicitBase.baseURL?.absoluteString == "https://games.example/media/","Explicit Flash base must be a directory")
        let director = WebPage.parse("""
        <object classid="clsid:166B1BCA-3F9C-11CF-8075-444553540000"><param name="src" value="/movie?id=7"><param name="sw1" value="one &amp; two"><param name="PlayerVersion" value="12"></object>
        <embed src="other.dcr" type="application/x-director" sw2="three" bgcolor="#112233" data-sw-language="fr" width="640" onclick="window.unwanted=true">
        """,url:publicURL).candidates
        try require(director.count == 2 && director[0].kind == "dcr" && director[0].parameters["sw1"] == "one & two" && director[0].parameters["PlayerVersion"] == "12","Director object parameters or extensionless movie were lost")
        try require(director[1].parameters["sw2"] == "three" && director[1].parameters["bgcolor"] == "#112233" && director[1].parameters["language"] == "fr" && director[1].parameters["width"] == nil,"Director embed parameters were lost or mixed with layout")
        let listing = WebPage.parse("<title>Index of /flash/</title><a href=\"levels/\">levels/</a>",url:base.appendingPathComponent("flash",isDirectory:true))
        try require(listing.isDirectory && listing.folders.count == 1,"Directory parser: \(listing.title), \(listing.folders), \(listing.base)")
        try require(WebPage.queryParameters("broken=%ZZ&eq=a=b&space=a+b")["eq"] == "a=b","Malformed percent escapes must not crash")
        try require(WebPage.stringLiterals(#"{"name.png":"value.png"}"#,valuesOnly:true) == ["value.png"],"JSON property names became file references")
        try require(WebPage.assetDirectories(in:"Platform.soundPathPrefix='sound';",from:publicURL).contains { $0.path == "/play/sound" },"Configured asset directories were missed")
        let privateAddresses = ["file:///etc/passwd","http://localhost/x","http://127.0.0.1/x","http://10.1.2.3/x","http://192.168.1.2/x","http://[::1]/x","http://[::ffff:127.0.0.1]/x","http://[fe80::1%25en0]/x","https://user:pass@example.com/"]
        for raw in privateAddresses {
            do { _ = try WebAddress.checked(URL(string:raw)!); throw LibraryError("Accepted unsafe URL " + raw) }
            catch let error as LibraryError { if error.message.hasPrefix("Accepted") { throw error } }
        }
        let external = WebPage.parse("<!DOCTYPE x [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><html><title>&secret;</title></html>",url:publicURL)
        try require(!external.title.contains("root:"),"External XML entities were read")
        let related = WebsiteCollector(allowLocal:true,progress:{ _ in })
        let ranked = try await related.scan(base.appendingPathComponent("related-start"))
        try require(ranked.count == 2 && ranked.first?.url.path == "/flash/main.swf","A related game's embed outranked the requested page after a redirect")
        try await related.addRenderedPage(html:"<embed src='/flash/main.swf' flashvars='language=updated'>",url:base.appendingPathComponent("related/primary.html"),resources:[])
        let updated = await related.results()
        try require(updated.first?.parameters["language"] == "updated","Rendered launch parameters were discarded for an existing candidate")
        let collector = WebsiteCollector(allowLocal:true,progress:{ _ in })
        let found = try await collector.scan(base.appendingPathComponent("portal"))
        try require(found.contains { $0.url.path == "/flash/main.swf" },"Nested frames and external loader were not followed")
        let candidate = found.first { $0.url.path == "/flash/main.swf" }!
        let recovered = try await collector.recover(candidate,title:"Recovered Flash")
        try require(recovered.record.files.contains { $0.urls.contains { $0.path == "/flash/soundLibrary.swf" } },"Compressed SWF asset reference recovery")
        try require(recovered.record.files.contains { $0.urls.contains { $0.path == "/flash/levels/one.json" } },"Public directory traversal: \(recovered.record.report)")
        try require(recovered.record.issues.contains { $0.url.path == "/flash/missing.png" },"Missing asset was not reported")
        let library = GameLibrary(root:temp.appendingPathComponent("Library"))
        let localDirector = Game(id:String(repeating:"a",count:64),title:"Local Director",entry:"movies/Game #1.dcr",bytes:12,added:Date())
        let localFolder = library.folder(for:localDirector)
        try fm.createDirectory(at:localFolder.appendingPathComponent("movies"),withIntermediateDirectories:true)
        try Data("<embed src='other.dcr' sw1='wrong'>".utf8).write(to:localFolder.appendingPathComponent("movies/other.html"))
        try Data("<object><param name='src' value='movies/Game%20%231.dcr'><param name='sw1' value='bluecrab'><param name='sw2' value=''></object><script>throw Error('never run');</script>".utf8).write(to:localFolder.appendingPathComponent("Launcher.html"))
        let localSettings = library.localShockwaveParameters(localDirector)
        try require(localSettings["sw1"] == "bluecrab" && localSettings["sw2"] == "","Local folder launch parameters or empty values were lost")
        try Data("<embed src='https://different.example/movies/Game%20%231.dcr' sw1='wrong'>".utf8).write(to:localFolder.appendingPathComponent("Launcher.html"))
        try require(library.localShockwaveParameters(localDirector).isEmpty,"An unrelated remote game supplied local launch settings")
        var plan = try library.inspect(recovered.source); plan.suggestedTitle = "Recovered Flash"
        let game = try library.importGame(plan,entry:recovered.entry!)
        try library.save([game]); try library.saveWebRecord(recovered.record,for:game)
        try require(library.webRecord(game)?.parameters["language"] == "en","Launch settings did not survive library import")
        let routing = WebRouting(record:recovered.record,origin:URL(string:"flashback://\(game.id)/")!,isHTML:false)
        for file in recovered.record.files {
            try require(routing.path(for:routing.local(file.urls[0])) == file.path,"Offline route lookup failed")
            let imported = try GameLibrary.contained(file.path,in:library.folder(for:game))
            try require(try WebImportRecord.hashFile(imported) == file.sha256,"Original asset bytes changed")
        }
        let repeated = try library.importGame(plan,entry:recovered.entry!)
        try require(game.id == repeated.id,"Duplicate recovery changed game identity")
        await collector.clean()
        let htmlCollector = WebsiteCollector(allowLocal:true,progress:{ _ in })
        let htmlGames = try await htmlCollector.scan(base.appendingPathComponent("html/play.html"))
        let htmlGame = try await htmlCollector.recover(htmlGames.first { $0.kind == "html" }!,title:"Offline Web Check")
        let variantFiles = htmlGame.record.files.filter { $0.urls.contains { $0.path == "/html/data.json" } }
        try require(variantFiles.count == 2 && Set(variantFiles.map(\.path)).count == 2,"Query variants collided")
        try require(htmlGame.record.files.contains { $0.urls.contains { $0.path == "/html/js/palette.mjs" } },"Module import resolution")
        try require(htmlGame.record.files.contains { $0.urls.contains { $0.host == "localhost" && $0.path == "/remote/shared.png" } },"Cross-host asset recovery")
        try require(htmlGame.record.files.contains { $0.urls.contains { $0.path == "/api/level" } },"Extensionless fetch recovery")
        let htmlRouting = WebRouting(record:htmlGame.record,origin:URL(string:"flashback://test/")!,isHTML:true)
        for file in variantFiles {
            let raw = URL(string:htmlRouting.prefixes.first { $0[0].contains("127.0.0.1") }![1] + "html/data.json?" + file.urls[0].query!)!
            try require(htmlRouting.path(for:raw) == file.path,"Runtime query variant route failed")
        }
        let source = WebPage.text(try Data(contentsOf:GameLibrary.contained(htmlGame.entry!,in:htmlGame.source)))
        let rewritten = htmlRouting.text(source,path:htmlGame.entry!,mime:"text/html")
        try require(rewritten.contains("<base href=\"flashback://test/") && !rewritten.contains("src=\"/remote"),"Offline HTML URL rewriting")
        let scriptFile = htmlGame.record.files.first { $0.path.hasSuffix("game.js") }!
        let composedPath = "const language='en'; fetch(language+'/strings.json');"
        try require(htmlRouting.text(composedPath,path:scriptFile.path,mime:"application/javascript") == composedPath,"Offline routing rewrote a JS path fragment")
        await htmlCollector.clean()
        let attachmentCollector = WebsiteCollector(allowLocal:true,progress:{ _ in })
        let attachment = try await attachmentCollector.scan(base.appendingPathComponent("attachment"))
        try require(attachment.first?.kind == "swf","Content-Disposition game discovery")
        let transferred = try await attachmentCollector.recover(attachment[0],title:"Download")
        try require(transferred.entry?.hasSuffix(".swf") == true,"Extensionless game filename")
        await attachmentCollector.clean()
        for endpoint in ["large-known","large-streamed","denied","redirect-private"] {
            let transfer = WebTransfer(url:base.appendingPathComponent(endpoint),directory:temp,limit:1024,scanOnly:false,allowLocal:endpoint != "redirect-private",progress:{ _,_ in })
            do { _ = try await transfer.start(); throw LibraryError("Accepted bad transfer " + endpoint) }
            catch let error as LibraryError { if error.message.hasPrefix("Accepted") { throw error } }
            try require(!fm.fileExists(atPath:transfer.file.path),"Failed transfer left partial file")
        }
        let transfer = WebTransfer(url:base.appendingPathComponent("slow"),directory:temp,limit:1024*1024,scanOnly:false,allowLocal:true,progress:{ _,_ in })
        let task = Task { try await transfer.start() }
        try await Task.sleep(nanoseconds:250_000_000); task.cancel()
        do { _ = try await task.value; throw LibraryError("Cancellation did not stop download") } catch is CancellationError {}
        try require(!fm.fileExists(atPath:transfer.file.path),"Cancelled download left partial file")
        print("PASS: website parsing, discovery, recovery, routing, provenance, limits, and cancellation")
    }
}
