// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import SwiftUI
import WebKit
import UniformTypeIdentifiers

/// Exercises the shipped importer and player in an isolated test library.
/// Run the app binary with --self-check SOURCE ENTRY OUTPUT_DIRECTORY.
@MainActor final class SmokeCheck {
    let model: LibraryModel
    let output: URL
    var phase = 0
    var finished = false
    var htmlIs2048 = false
    var htmlSavedState: String?
    var probesShockwave = false
    var probeOptions: [String:Any] = [:]
    private let shockwavePreference = UUID().uuidString
    private var sendsGameInput = false
    private var inputMonitor: Any?
    init(model: LibraryModel, output: URL) { self.model = model; self.output = output }

    func run(source: URL, entry: String) {
        Task { await begin(source:source,entry:entry) }
    }

    /// Open the library created by the previously installed release, without reimporting it.
    func runInstallation(delegate: AppDelegate) {
        Task {
            do {
                if #available(macOS 14.0, *) {
                    model.playerDataStore = WKWebsiteDataStore(forIdentifier:UUID(uuidString:"20EE358F-0D7E-4C56-B93E-1848957091DF")!)
                } else { throw LibraryError("The isolated cross-launch storage check requires macOS 14 or later") }
                let expected = try JSONDecoder().decode([String:String].self,from:Data(contentsOf:output.appendingPathComponent("Installation-files.json")))
                func verifyFiles(skipIndex: Bool = false) throws {
                    for (path, hash) in expected where !skipIndex || path != "Library.json" {
                        let file = try GameLibrary.contained(path,in:model.library.root)
                        guard try WebImportRecord.hashFile(file) == hash else { throw LibraryError("Installing the update changed \(path)") }
                    }
                }
                try verifyFiles()
                let before = model.games
                guard let game = before.first, before.count == 1, game.isFlash, game.favorite, game.title == "My Saved Game", game.lastPlayed != nil else {
                    throw LibraryError("The previous installation's library metadata was not restored")
                }
                guard delegate.applicationShouldTerminate(NSApp) == .terminateNow else { throw LibraryError("An empty player session asked for quit confirmation") }
                model.play(game)
                guard let session = model.windows[game.id]?.session else { throw LibraryError("The installed game did not open") }
                for _ in 0..<150 {
                    if !session.loading { break }
                    try await Task.sleep(nanoseconds:100_000_000)
                }
                guard !session.loading, session.failure == nil, !session.missingFiles else { throw LibraryError("The updated player could not load the existing game") }
                let saved = try await session.web.evaluateJavaScript("localStorage.getItem('flashback-self-check')")
                guard saved as? String == "saved" else { throw LibraryError("Per-game storage was not restored from the previous app launch") }
                for paused in [false,true] {
                    if session.paused != paused { session.togglePause() }
                    try await Task.sleep(nanoseconds:200_000_000)
                    let reply = try checkQuitDialog(delegate:delegate,name:paused ? "Quit-paused" : "Quit-playing",quit:false,escape:paused)
                    guard reply == .terminateCancel, model.windows[game.id]?.session === session, session.paused == paused else {
                        throw LibraryError("Canceling quit changed or closed the game session")
                    }
                    let suspended = try await session.web.evaluateJavaScript("player.ruffle().suspended")
                    guard suspended as? Bool == paused else { throw LibraryError("Canceling quit did not preserve the player's pause state") }
                }
                guard try checkQuitDialog(delegate:delegate,name:"Quit-confirm",quit:true) == .terminateNow else {
                    throw LibraryError("Confirming quit did not allow termination")
                }
                for window in Array(model.windows.values) { window.close() }
                // A Java session can still be starting before it has a process/window.
                // It must also be protected by the app-wide termination delegate.
                let java = JavaSession(game:game)
                model.javaSessions[game.id] = java
                guard try checkQuitDialog(delegate:delegate,name:"Quit-java",quit:false) == .terminateCancel else {
                    throw LibraryError("A Java session did not prevent an unconfirmed quit")
                }
                model.javaSessions.removeAll()
                guard delegate.applicationShouldTerminate(NSApp) == .terminateNow else { throw LibraryError("Quit still prompted after all games closed") }
                try verifyFiles(skipIndex:true)
                let after = try model.library.load()
                guard after.count == before.count, after[0].id == game.id, after[0].title == game.title,
                      after[0].favorite == game.favorite, after[0].added == game.added, after[0].lastPlayed != nil else {
                    throw LibraryError("Opening the updated game lost library metadata")
                }
                let message = "PASS: existing installed library, renamed favorite, game assets, cover, saved files, and per-game WebKit storage survive app replacement; quit confirmation protects playing, paused, and Java sessions; Cancel and Escape preserve pause state; confirmed/empty quit succeeds.\n"
                try Data(message.utf8).write(to:output.appendingPathComponent("Installation-result.txt"))
                FileHandle.standardOutput.write(Data(message.utf8))
                NSApp.terminate(nil)
            } catch { finish(error.localizedDescription) }
        }
    }

    func checkQuitDialog(delegate: AppDelegate, name: String, quit: Bool, escape: Bool = false) throws -> NSApplication.TerminateReply {
        var failure: String?
        let timer = Timer(timeInterval:0.6,repeats:false) { [self] _ in
            guard let window = NSApp.modalWindow, let view = window.contentView else {
                failure = "Quit confirmation did not appear"; NSApp.abortModal(); return
            }
            func buttons(_ view: NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
            let controls = buttons(view)
            guard let keep = controls.first(where:{ $0.title == "Cancel" }), let close = controls.first(where:{ $0.title == "Quit Flashback" }),
                  window.defaultButtonCell !== close.cell else {
                failure = "Quit confirmation allowed an accidental default quit"; NSApp.abortModal(); return
            }
            MainActor.assumeIsolated { try? saveWindowCapture(window,to:output.appendingPathComponent(name + ".png")) }
            if escape {
                let key = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                    windowNumber:window.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!
                NSApp.sendEvent(key)
            } else { (quit ? close : keep).performClick(nil) }
        }
        let watchdog = Timer(timeInterval:2,repeats:false) { _ in
            failure = "The quit dialog did not respond to its button or Escape"; NSApp.abortModal()
        }
        RunLoop.main.add(timer,forMode:.modalPanel)
        RunLoop.main.add(watchdog,forMode:.modalPanel)
        defer { timer.invalidate(); watchdog.invalidate() }
        let reply = delegate.applicationShouldTerminate(NSApp)
        if let failure { throw LibraryError(failure) }
        return reply
    }

    func begin(source: URL, entry: String) async {
        do {
            if #available(macOS 14.0, *) {
                model.playerDataStore = WKWebsiteDataStore(forIdentifier:UUID(uuidString:"20EE358F-0D7E-4C56-B93E-1848957091DF")!)
            } else { model.playerDataStore = .nonPersistent() }
            try FileManager.default.createDirectory(at:output, withIntermediateDirectories:true)
            if probesShockwave, let data = try? Data(contentsOf:output.appendingPathComponent("Probe.json")) {
                probeOptions = try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:]
            }
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier:UTType.fileURL.identifier, visibility:.all) { completion in
                completion(source.dataRepresentation,nil); return nil
            }
            let dropped = await LibraryModel.droppedURLs([provider])
            guard dropped.count == 1, dropped[0].path == source.path else { throw LibraryError("Dropped file URL was not decoded correctly") }
            try await renderLibrary("Library-empty-light.png", scheme:.light)
            try await renderLibrary("Library-empty-dark.png", scheme:.dark)
            try await renderLibrary("Library-compact.png", scheme:.light, compact:true)
            let plan = try model.library.prepare(source, resources:Bundle.main.resourceURL!)
            defer { if let temp = plan.temporaryDirectory { try? FileManager.default.removeItem(at:temp) } }
            var game = try model.library.importGame(plan, entry:entry)
            let duplicate = try model.library.importGame(plan, entry:entry)
            guard duplicate.id == game.id else { throw LibraryError("Repeated import changed game identity") }
            game.title = game.isJava ? "Wiz 3" : (game.isHTML ? "HTML Game Check" : (game.isShockwave ? "Shockwave Game Check" : "TextTwist 2"))
            try model.library.save([game]); model.games = [game]
            if game.isShockwave && (game.entry.contains("rapunzel") || game.entry == "Merlin.dcr") {
                let rapunzel = game.entry.contains("rapunzel")
                let page = URL(string:rapunzel ? "https://games.example/shockwave.html" : "https://themetalbox.com/index.php?page=merlin_1")!
                let markup = rapunzel ? "<object><param name='src' value='game.dcr'><param name='flashbackProbe' value='preserved-value'><param name='onclick' value='window.unwanted=true'></object>" :
                    "<embed src='dcr/games/merlin_1.dcr' sw1='#merlinBonus' sw2='http://www.themetalbox.com/?page=merlin_2' sw3='' bgcolor='#000000'>"
                let candidate = WebPage.parse(markup,url:page).candidates[0]
                let movie = try GameLibrary.contained(game.entry,in:model.library.folder(for:game))
                let record = WebImportRecord(page:page,entryURL:candidate.url,title:game.title,parameters:candidate.parameters,
                    files:[.init(urls:[candidate.url],path:game.entry,mime:"application/x-director",bytes:Int64(try Data(contentsOf:movie).count),sha256:try WebImportRecord.hashFile(movie))])
                try model.library.saveWebRecord(record,for:game)
            }
            if probesShockwave, let parameters = probeOptions["parameters"] as? [String:String] {
                let page = URL(string:probeOptions["page"] as? String ?? "https://games.example/game.html")!
                let entryURL = page.deletingLastPathComponent().appendingPathComponent(game.entry)
                let files = try plan.files.map { path -> WebImportRecord.File in
                    let file = try GameLibrary.contained(path,in:model.library.folder(for:game))
                    return .init(urls:[page.deletingLastPathComponent().appendingPathComponent(path)],path:path,mime:"",bytes:Int64(try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0),sha256:try WebImportRecord.hashFile(file))
                }
                let record = WebImportRecord(page:page,entryURL:entryURL,title:game.title,parameters:parameters,files:files)
                try model.library.saveWebRecord(record,for:game)
            }
            model.play(game)
            if game.isJava {
                guard let session = model.javaSessions[game.id] else { throw LibraryError("Java session was not created") }
                let onReady = session.onReady
                session.onReady = { [weak self, weak session] in
                    onReady?()
                    guard let self, let session else { return }
                    Task { do { try await self.checkJava(session) } catch { self.finish(error.localizedDescription) } }
                }
                let onExit = session.onExit
                session.onExit = { [weak self] error in
                    onExit?(error)
                    guard let self, !self.finished else { return }
                    self.finish(error ?? (self.phase == 3 ? nil : "Java player exited before completing its checks"))
                }
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds:45_000_000_000)
                    guard let self, !self.finished else { return }
                    self.finish("Java player check timed out")
                }
                return
            }
            guard let session = model.windows[game.id]?.session else { throw LibraryError("Player window was not created") }
            if game.isShockwave {
                // Isolate only this temporary test window from unrelated live input.
                inputMonitor = NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp,.leftMouseDown,.leftMouseUp,.mouseMoved,.rightMouseDown,.rightMouseUp,.scrollWheel]) { [weak self, weak session] event in
                    guard event.windowNumber == session?.web.window?.windowNumber else { return event }
                    return self?.sendsGameInput == true ? event : nil
                }
                session.web.configuration.userContentController.addUserScript(WKUserScript(source:"""
                window.shockwaveAudioCheck={started:0,nonSilent:0};
                window.shockwaveInputCheck=[];
                for(const type of ['pointerdown','pointerup','pointercancel','mousedown','mouseup','keydown','keyup'])document.addEventListener(type,e=>{
                  if(shockwaveInputCheck.length<20)shockwaveInputCheck.push({type,x:e.clientX,y:e.clientY,key:e.key,code:e.keyCode,target:e.target.id});
                },true);
                const start=AudioBufferSourceNode.prototype.start;
                AudioBufferSourceNode.prototype.start=function(...args){
                  const result=start.apply(this,args);
                  shockwaveAudioCheck.started++;
                  if(this.buffer){
                    const data=this.buffer.getChannelData(0);
                    if(data.some(value=>Math.abs(value)>0.001))shockwaveAudioCheck.nonSilent++;
                  }
                  return result;
                };
                """, injectionTime:.atDocumentStart, forMainFrameOnly:true))
                session.start()
            }
            if probesShockwave, probeOptions["interactive"] as? Bool == true {
                await interactiveShockwave(session)
                return
            }
            let onReady = session.onReady
            session.onReady = { [weak self, weak session] in
                onReady?()
                guard let self, let session else { return }
                Task { do { try await self.check(session) } catch { self.finish(error.localizedDescription) } }
            }
            Task { [weak self] in
                for _ in 0..<180 {
                    try? await Task.sleep(nanoseconds:500_000_000)
                    guard let self, !self.finished else { return }
                    if session.failure != nil { break }
                }
                guard let self, !self.finished else { return }
                let detail = try? await session.web.evaluateJavaScript("JSON.stringify({errors:window.shockwaveErrors,diagnostics:window.shockwaveDiagnostics,body:document.body.innerText,console:window.__vm?.mcp_get_console_output?.(100),vm:window.__vm?.mcp_get_execution_state?.(),stack:window.__vm?.mcp_get_call_stack?.(12,true),sources:window.__vm?JSON.parse(__vm.mcp_get_call_stack(12,false)).scopes.map(s=>({cast:s.cast_lib,member:s.cast_member,handler:s.handler_name,source:JSON.parse(__vm.mcp_decompile_handler(s.cast_lib,s.cast_member,s.handler_name))})):[],scripts:window.__vm?.mcp_list_scripts?.(-1,500,0),globals:window.__vm?.mcp_get_globals?.(),members:window.__vm?.mcp_list_cast_members?.(-1)})")
                if let detail { try? Data(String(describing:detail).utf8).write(to:self.output.appendingPathComponent("Timeout-details.txt")) }
                if let view = session.web.window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
                    view.cacheDisplay(in:view.bounds,to:bitmap)
                    try? bitmap.representation(using:.png,properties:[:])?.write(to:self.output.appendingPathComponent("Player-failure.png"))
                }
                self.finish(session.failure ?? "Player check timed out")
            }
        } catch { finish(error.localizedDescription) }
    }

    func checkJava(_ session: JavaSession) async throws {
        try await Task.sleep(nanoseconds:3_000_000_000)
        guard session.process.isRunning else { throw LibraryError("Java game was not running") }
        let pid = session.process.processIdentifier
        model.play(session.game)
        guard model.javaSessions.count == 1, model.javaSessions[session.game.id]?.process.processIdentifier == pid else {
            throw LibraryError("Playing an open Java game created a duplicate process")
        }
        try await renderLibrary("Library-java-light.png", scheme:.light)
        try await renderLibrary("Library-java-dark.png", scheme:.dark)
        let restored = try model.library.load()
        guard restored.first?.lastPlayed != nil else { throw LibraryError("Java recent-play history was not saved") }
        phase = 3
        session.stop()
    }

    func check(_ session: PlayerSession) async throws {
        if session.game.isHTML { try await checkHTML(session); return }
        if session.game.isShockwave { try await checkShockwave(session); return }
        if phase == 0 {
            phase = 1
            try await Task.sleep(nanoseconds:5_000_000_000)
            guard !session.missingFiles, session.failure == nil else { throw LibraryError("The game reported missing assets or a player failure") }
            let metadata = try await session.web.evaluateJavaScript("player.ruffle().metadata")
            guard metadata is [String:Any] else { throw LibraryError("Flash metadata was unavailable") }
            session.togglePause()
            let paused = try await session.web.evaluateJavaScript("player.ruffle().isPlaying")
            guard paused as? Bool == false else { throw LibraryError("Pause failed") }
            session.togglePause()
            let resumed = try await session.web.evaluateJavaScript("player.ruffle().isPlaying")
            guard resumed as? Bool == true else { throw LibraryError("Resume failed") }
            session.toggleMute()
            let volume = try await session.web.evaluateJavaScript("player.ruffle().volume")
            guard (volume as? NSNumber)?.doubleValue == 0 else { throw LibraryError("Mute failed") }
            session.toggleMute()
            let blocked = try await session.web.callAsyncJavaScript("try { await fetch('https://example.com/'); return false; } catch { return true; }", arguments:[:], in:nil, contentWorld:.page)
            guard blocked as? Bool == true else { throw LibraryError("The offline content policy did not block a remote request") }
            let previous = try await session.web.evaluateJavaScript("localStorage.getItem('flashback-self-check')")
            FileHandle.standardOutput.write(Data("Save from previous launch: \(previous as? String ?? "none")\n".utf8))
            try await session.web.evaluateJavaScript("localStorage.setItem('flashback-self-check','saved'); void 0;")
            session.start()
        } else if phase == 1 {
            phase = 2
            try await Task.sleep(nanoseconds:5_000_000_000)
            let saved = try await session.web.evaluateJavaScript("localStorage.getItem('flashback-self-check')")
            guard saved as? String == "saved" else { throw LibraryError("Save storage did not survive restarting") }
            let image = try await session.web.takeSnapshot(configuration:nil)
            if let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) {
                try png.write(to:output.appendingPathComponent("Player.png"))
            } else { throw LibraryError("Could not render the player") }
            try await renderLibrary("Library-game-light.png", scheme:.light)
            try await renderLibrary("Library-game-dark.png", scheme:.dark)
            let restored = try model.library.load()
            guard restored.count == 1, restored[0].lastPlayed != nil else { throw LibraryError("Recent play history was not saved") }
            finish(nil)
        }
    }

    func checkShockwave(_ session: PlayerSession) async throws {
        if probesShockwave { try await checkShockwaveProbe(session); return }
        if phase == 7 {
            phase = 8
            try await Task.sleep(nanoseconds:3_000_000_000)
            let saved = try await lingo(session, "getPref(\"flashback-check\")")
            guard saved == "\"\(shockwavePreference)\"" else { throw LibraryError("Director preferences did not survive restart: \(saved)") }
            try await shockwaveSnapshot(session, "Restarted")
            try await renderLibrary("Library-shockwave-light.png", scheme:.light)
            try await renderLibrary("Library-shockwave-dark.png", scheme:.dark)
            guard try model.library.load().first?.lastPlayed != nil else { throw LibraryError("Shockwave recent history missing") }
            finish(nil)
            return
        }
        guard phase == 0 else { return }
        phase = 6
        try await Task.sleep(nanoseconds:5_000_000_000)
        try await shockwaveSnapshot(session, "Title")
        if session.game.entry.contains("rapunzel") {
            guard try await lingo(session,"externalParamValue(\"flashbackProbe\")") == "\"preserved-value\"" else { throw LibraryError("Recovered Director parameter did not reach the VM") }
            guard try await session.web.evaluateJavaScript("window.unwanted !== true") as? Bool == true else { throw LibraryError("A plug-in parameter executed as a DOM event handler") }
            try await session.web.evaluateJavaScript("console.error('Failed to resume AudioContext:', 'recoverable diagnostic check'); void 0;")
            try await Task.sleep(nanoseconds:300_000_000)
            guard session.failure == nil else { throw LibraryError("A recoverable Director diagnostic stopped playback") }
            try await clickMovie(session, x:256, y:202)
        } else if session.game.entry == "game.dcr" {
            try await clickMovie(session, x:320, y:460)
        } else if session.game.entry.hasPrefix("merlin_3_") {
            try await clickMovie(session, x:320, y:204)
            try await Task.sleep(nanoseconds:2_000_000_000)
            try await shockwaveSnapshot(session, "Intro")
            try await clickMovie(session, x:320, y:241)
        } else if session.game.entry == "Merlin.dcr" {
            for y in [204.0,204,219,219] {
                try await clickMovie(session,x:320,y:y)
                try await Task.sleep(nanoseconds:1_500_000_000)
            }
        }
        try await Task.sleep(nanoseconds:2_000_000_000)
        try await shockwaveSnapshot(session, "Started")
        if session.game.entry == "Merlin.dcr" {
            let mode = try await lingo(session,"g.merlinMain.pMode")
            guard mode == "#game" else { throw LibraryError("Merlin 1 loaded, but its Start button did not enter gameplay") }
        }
        if session.game.entry.contains("rapunzel") || session.game.entry.hasPrefix("merlin_3_") {
            let playing = try await session.web.evaluateJavaScript("(()=>{const g=JSON.parse(__vm.mcp_get_globals()).globals.g;const a=JSON.parse(__vm.mcp_inspect_datum(g.datum_id)).properties['#actorMaster'];return JSON.parse(__vm.mcp_inspect_datum(a.datum_id)).properties.pPlayer.type_name==='script_instance';})()")
            guard playing as? Bool == true else { throw LibraryError("The Shockwave game did not create its playable character") }
        }
        if session.game.entry == "game.dcr" {
            // Follow the actual menu state. The original movie disables controls
            // while its animated transitions run; synthetic input can arrive early.
            for _ in 0..<8 {
                let frame = try await session.web.evaluateJavaScript("JSON.parse(__vm.mcp_get_execution_state()).current_frame") as? Int
                if frame == 70 || session.failure != nil { break }
                if frame == 80 { try await clickMovie(session,x:175,y:95) }
                else if frame == 90 || frame == 95 { try await clickMovie(session,x:320,y:460) }
                try await Task.sleep(nanoseconds:6_000_000_000)
            }
            try await shockwaveSnapshot(session, "Driving")
            guard (try await session.web.evaluateJavaScript("JSON.parse(__vm.mcp_get_execution_state()).current_frame")) as? Int == 70 else {
                throw LibraryError("Supersonic RC did not enter its 3D driving level")
            }
        }
        try await shockwaveSnapshot(session, "Playing")
        let key = session.game.entry.contains("rapunzel") ? "\u{f702}" : "\u{f700}"
        let code: UInt16 = session.game.entry.contains("rapunzel") ? 123 : 126
        let window = session.web.window!
        NSApp.activate(ignoringOtherApps:true)
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(session.web)
        try await Task.sleep(nanoseconds:200_000_000)
        for type in [NSEvent.EventType.keyDown,.keyUp] {
            let event = NSEvent.keyEvent(with:type,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                windowNumber:window.windowNumber,context:nil,characters:key,charactersIgnoringModifiers:key,isARepeat:false,keyCode:code)!
            sendGameEvent(event)
            if type == .keyDown {
                try await Task.sleep(nanoseconds:1_500_000_000)
                try await shockwaveSnapshot(session, "Key-held")
                let held = try await lingo(session,"keyPressed(\(code))")
                guard held == "1" else { throw LibraryError("Native key was not pressed in the Director VM: \(held)") }
            }
        }
        try await Task.sleep(nanoseconds:300_000_000)
        try await shockwaveSnapshot(session, "Moved")
        guard try await lingo(session,"keyPressed(\(code))") == "0" else { throw LibraryError("Native key release did not reach the Director VM") }
        guard try await session.web.evaluateJavaScript("getAudioContext().state === 'running'") as? Bool == true else { throw LibraryError("Shockwave audio backend is suspended") }
        let audio = try await session.web.evaluateJavaScript("window.shockwaveAudioCheck.nonSilent > 0")
        if session.game.entry == "game.dcr" || session.game.entry.hasPrefix("merlin_3_") {
            guard audio as? Bool == true else { throw LibraryError("Game audio did not start a non-silent Web Audio buffer") }
        }
        _ = try await lingo(session,"setPref(\"flashback-check\",\"\(shockwavePreference)\")")
        for size in [NSSize(width:640,height:500), NSSize(width:1200,height:800)] {
            window.setContentSize(size)
            try await Task.sleep(nanoseconds:600_000_000)
            let fits = try await session.web.evaluateJavaScript("(()=>{const c=document.querySelector('#stage_canvas_container canvas'),r=c.getBoundingClientRect();return r.x>=-1&&r.y>=-1&&r.right<=innerWidth+1&&r.bottom<=innerHeight+1&&Math.abs(r.width/r.height-c.width/c.height)<0.01;})()")
            guard fits as? Bool == true else { throw LibraryError("Resized Shockwave canvas overflowed or changed proportions") }
        }
        try await shockwaveSnapshot(session, "Resized")
        window.toggleFullScreen(nil)
        try await Task.sleep(nanoseconds:2_000_000_000)
        guard window.styleMask.contains(.fullScreen) else { throw LibraryError("Shockwave did not enter full screen") }
        try await shockwaveSnapshot(session, "Fullscreen")
        window.toggleFullScreen(nil)
        try await Task.sleep(nanoseconds:2_000_000_000)
        window.miniaturize(nil)
        try await Task.sleep(nanoseconds:500_000_000)
        window.deminiaturize(nil); window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds:1_000_000_000)
        try await shockwaveSnapshot(session, "Restored")
        guard session.failure == nil else { throw LibraryError(session.failure!) }
        guard !session.missingFiles else { throw LibraryError("Shockwave reported missing files: " + session.missingResources.joined(separator:", ")) }
        // Recovered remote URLs map to local missing files. Probe only after
        // checking the game's own requests, then restart to clear the probe.
        let blocked = try await session.web.callAsyncJavaScript("try{await fetch('https://example.com/');return false;}catch{return true;}", arguments:[:],in:nil,contentWorld:.page)
        guard blocked as? Bool == true else { throw LibraryError("Shockwave offline policy allowed remote access") }
        phase = 7
        session.start()
    }

    func checkShockwaveProbe(_ session: PlayerSession) async throws {
        guard phase == 0 else { return }; phase = 9
        try await Task.sleep(nanoseconds:UInt64(probeOptions["wait"] as? Double ?? 5) * 1_000_000_000)
        try await shockwaveSnapshot(session,"Title")
        let scripts = try await session.web.evaluateJavaScript("__vm.mcp_list_scripts(-1,500,0)") as? String ?? ""
        try Data(scripts.utf8).write(to:output.appendingPathComponent("Scripts.json"))
        var observations: [String:Any] = [:]
        for (index, step) in (probeOptions["steps"] as? [[String:Any]] ?? []).enumerated() {
            observations[String(index)] = try await shockwaveStep(session, step)
            try await shockwaveSnapshot(session,"Step-\(index)")
        }
        if !observations.isEmpty {
            try JSONSerialization.data(withJSONObject:observations,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("Observations.json"))
        }
        let expectedMissing = Set(probeOptions["expectedMissing"] as? [String] ?? [])
        let unexpectedMissing = session.missingResources.filter { resource in
            guard let path = URL(string:resource)?.path, path.hasPrefix("/game/") else { return true }
            return !expectedMissing.contains(String(path.dropFirst("/game/".count)))
        }
        try JSONSerialization.data(withJSONObject:["observed":session.missingResources,"expected":Array(expectedMissing).sorted()],options:[.prettyPrinted,.sortedKeys])
            .write(to:output.appendingPathComponent("MissingResources.json"))
        guard session.failure == nil, unexpectedMissing.isEmpty else { throw LibraryError(session.failure ?? "Missing game files: " + unexpectedMissing.joined(separator:", ")) }
        if let expression = probeOptions["expect"] as? String {
            guard try await session.web.callAsyncJavaScript("return \(expression);",arguments:[:],in:nil,contentWorld:.page) as? Bool == true else { throw LibraryError("The recorded gameplay condition was not reached") }
            phase = 10
        }
        finish(nil)
    }

    /// Local test-only command loop. Keep a failed VM inspectable and record the
    /// exact native input/read sequence for conversion into a replayable probe.
    func interactiveShockwave(_ session: PlayerSession) async {
        var lastID = -1
        var commands: [[String:Any]] = []
        while !finished {
            try? await Task.sleep(nanoseconds:100_000_000)
            guard let data = try? Data(contentsOf:output.appendingPathComponent("Command.json")),
                  let command = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let id = command["id"] as? Int, id > lastID else { continue }
            lastID = id
            commands.append(command)
            var reply: [String:Any] = ["id":id,"success":true]
            do {
                if command["restart"] as? Bool == true { session.start() }
                reply["result"] = try await shockwaveStep(session, command) ?? NSNull()
                if command["snapshot"] as? Bool == true { try await shockwaveSnapshot(session,"Live-\(id)") }
            } catch {
                reply["success"] = false
                reply["error"] = String(describing:(error as NSError).userInfo)
            }
            reply["failure"] = session.failure ?? ""
            reply["missingResources"] = session.missingResources
            try? JSONSerialization.data(withJSONObject:commands,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("Commands.json"),options:.atomic)
            try? JSONSerialization.data(withJSONObject:reply,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("Response.json"),options:.atomic)
            if command["finish"] as? Bool == true { finish(nil); return }
        }
    }

    func shockwaveStep(_ session: PlayerSession, _ step: [String:Any]) async throws -> Any? {
        if let size = step["resize"] as? [Double], size.count == 2, let window = session.web.window {
            window.setContentSize(NSSize(width:size[0],height:size[1]))
            try await Task.sleep(nanoseconds:600_000_000)
        }
        if let point = step["move"] as? [Double], point.count == 2 { try await clickMovie(session,x:point[0],y:point[1],moveOnly:true) }
        if let point = step["click"] as? [Double], point.count == 2 { try await clickMovie(session,x:point[0],y:point[1],hover:step["hover"] as? Double ?? 0.1) }
        if let points = step["drag"] as? [Double], points.count == 4 {
            try await clickMovie(session,x:points[0],y:points[1],dragTo:NSPoint(x:points[2],y:points[3]))
        }
        if let modifier = step["modifier"] as? String, let window = session.web.window {
            let keys: [String:(NSEvent.ModifierFlags,UInt16)] = ["shift":(.shift,56),"control":(.control,59),"option":(.option,58),"command":(.command,55)]
            guard let (flags,code) = keys[modifier] else { throw LibraryError("Unknown test modifier: \(modifier)") }
            window.makeKeyAndOrderFront(nil); window.makeFirstResponder(session.web)
            for pressed in [true,false] {
                let event = NSEvent.keyEvent(with:.flagsChanged,location:.zero,modifierFlags:pressed ? flags : [],timestamp:ProcessInfo.processInfo.systemUptime,
                    windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)!
                sendGameEvent(event)
                if pressed { try await Task.sleep(nanoseconds:UInt64((step["hold"] as? Double ?? 0.2) * 1_000_000_000)) }
            }
        }
        if let key = step["key"] as? String, let code = step["keyCode"] as? UInt16, let window = session.web.window {
            window.makeKeyAndOrderFront(nil); window.makeFirstResponder(session.web)
            for type in [NSEvent.EventType.keyDown,.keyUp] {
                let event = NSEvent.keyEvent(with:type,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                    windowNumber:window.windowNumber,context:nil,characters:key,charactersIgnoringModifiers:key,isARepeat:false,keyCode:code)!
                sendGameEvent(event)
                if type == .keyDown { try await Task.sleep(nanoseconds:UInt64((step["hold"] as? Double ?? 0.2) * 1_000_000_000)) }
            }
        }
        try await Task.sleep(nanoseconds:UInt64((step["wait"] as? Double ?? 1) * 1_000_000_000))
        if let expression = step["expect"] as? String {
            guard try await session.web.callAsyncJavaScript("return \(expression);",arguments:[:],in:nil,contentWorld:.page) as? Bool == true else {
                throw LibraryError("The input step did not reach its recorded gameplay condition")
            }
        }
        if let code = step["read"] as? String { return try await session.web.callAsyncJavaScript("return \(code);",arguments:[:],in:nil,contentWorld:.page) }
        return nil
    }

    func lingo(_ session: PlayerSession, _ code: String) async throws -> String {
        do {
            return try await session.web.callAsyncJavaScript("const r=JSON.parse(await __vm.mcp_eval_lingo(code));if(!r.success)throw Error(r.error);return r.result_value;",arguments:["code":code],in:nil,contentWorld:.page) as? String ?? ""
        } catch { throw LibraryError("Lingo \(code): \((error as NSError).userInfo)") }
    }

    func shockwaveSnapshot(_ session: PlayerSession, _ name: String) async throws {
        let state = try await session.web.evaluateJavaScript("JSON.stringify({console:__vm.mcp_get_console_output(100),state:JSON.parse(__vm.mcp_get_execution_state()),globals:JSON.parse(__vm.mcp_get_globals()),audio:window.shockwaveAudioCheck,audioState:window.getAudioContext?.().state,input:window.shockwaveInputCheck,errors:window.shockwaveErrors,diagnostics:window.shockwaveDiagnostics,game:JSON.parse(__vm.mcp_get_globals()).globals.g?JSON.parse(__vm.mcp_inspect_datum(JSON.parse(__vm.mcp_get_globals()).globals.g.datum_id)):null,main:JSON.parse(__vm.mcp_get_globals()).globals.gMainManager?JSON.parse(__vm.mcp_inspect_datum(JSON.parse(__vm.mcp_get_globals()).globals.gMainManager.datum_id)):null})") as? String ?? ""
        try Data(state.utf8).write(to:output.appendingPathComponent("Shockwave-\(name).json"))
        let image = try await session.web.takeSnapshot(configuration:nil)
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) {
            try png.write(to:output.appendingPathComponent("Shockwave-\(name).png"))
        }
    }

    func sendGameEvent(_ event: NSEvent) {
        sendsGameInput = true
        NSApp.sendEvent(event)
        sendsGameInput = false
    }

    func clickMovie(_ session: PlayerSession, x: Double, y: Double, dragTo: NSPoint? = nil, hover: Double = 0.1, moveOnly: Bool = false) async throws {
        let points = try await session.web.callAsyncJavaScript("const c=document.querySelector('#stage_canvas_container canvas'),r=c.getBoundingClientRect();return [[x,y],[endX,endY]].map(([a,b])=>[r.x+a*r.width/c.width,r.y+b*r.height/c.height]);",arguments:["x":x,"y":y,"endX":dragTo?.x ?? x,"endY":dragTo?.y ?? y],in:nil,contentWorld:.page) as? [[Double]]
        guard let points, points.count == 2, points.allSatisfy({ $0.count == 2 }), let window = session.web.window else { throw LibraryError("Game canvas is unavailable for mouse input") }
        NSApp.activate(ignoringOtherApps:true)
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(session.web)
        try await Task.sleep(nanoseconds:200_000_000)
        let local = points.map { point in NSPoint(x:point[0]*session.web.pageZoom,y:session.web.isFlipped ? point[1]*session.web.pageZoom : session.web.bounds.height-point[1]*session.web.pageZoom) }
        let target = session.web.hitTest(local[0]) ?? session.web!
        var events: [(NSEvent.EventType, Int)] = [(.mouseMoved,0)]
        if !moveOnly { events.append((.leftMouseDown,0)) }
        if dragTo != nil { events.append((.leftMouseDragged,1)) }
        if !moveOnly { events.append((.leftMouseUp,1)) }
        for (type,index) in events {
            let location = session.web.convert(local[index],to:nil)
            let event = NSEvent.mouseEvent(with:type, location:location, modifierFlags:[], timestamp:ProcessInfo.processInfo.systemUptime,
                windowNumber:window.windowNumber, context:nil, eventNumber:0, clickCount:1, pressure:type == .leftMouseDown ? 1 : 0)!
            sendsGameInput = true
            if type == .mouseMoved {
                // WKWebView receives hover through its tracking-area owner,
                // not NSResponder.mouseMoved. Follow the native AppKit route.
                let selector = #selector(NSResponder.mouseMoved(with:))
                guard let receiver = session.web.trackingAreas.first(where:{ $0.options.contains(.mouseMoved) })?.owner as? NSObject,
                      receiver.responds(to:selector) else { throw LibraryError("The game’s native mouse tracking is unavailable") }
                receiver.perform(selector,with:event)
            }
            else if type == .leftMouseDown { target.mouseDown(with:event) }
            else if type == .leftMouseDragged { target.mouseDragged(with:event) }
            else { target.mouseUp(with:event) }
            sendsGameInput = false
            try await Task.sleep(nanoseconds:UInt64((type == .mouseMoved ? hover : 0.1) * 1_000_000_000))
        }
    }

    func checkHTML(_ session: PlayerSession) async throws {
        if phase == 0 {
            phase = 4
            try await Task.sleep(nanoseconds:2_000_000_000)
            htmlIs2048 = (try await session.web.evaluateJavaScript("typeof GameManager === 'function' && document.querySelectorAll('.tile').length >= 2")) as? Bool == true
            let state = try await session.web.evaluateJavaScript(htmlIs2048 ? "true" : "window.checkReady === true && getComputedStyle(document.body).backgroundColor === 'rgb(23, 28, 48)'")
            guard state as? Bool == true, !session.missingFiles, session.failure == nil else {
                throw LibraryError("HTML scripts, modules, assets, fetch, or CSS failed")
            }
            let blocked = try await session.web.callAsyncJavaScript("try { await fetch('https://example.com/'); return false; } catch { return true; }", arguments:[:], in:nil, contentWorld:.page)
            guard blocked as? Bool == true else { throw LibraryError("HTML offline policy did not block remote access") }
            let window = session.web.window!
            window.makeKeyAndOrderFront(nil); window.makeFirstResponder(session.web)
            let before = try await session.web.evaluateJavaScript("localStorage.getItem('gameState')") as? String
            for (key,code) in [("\u{f703}",UInt16(124)),("\u{f701}",125),("\u{f702}",123)] {
                let event = NSEvent.keyEvent(with:.keyDown, location:.zero, modifierFlags:[], timestamp:ProcessInfo.processInfo.systemUptime,
                    windowNumber:window.windowNumber, context:nil, characters:key, charactersIgnoringModifiers:key, isARepeat:false, keyCode:code)!
                NSApp.sendEvent(event)
                try await Task.sleep(nanoseconds:150_000_000)
            }
            try await Task.sleep(nanoseconds:500_000_000)
            if htmlIs2048 {
                htmlSavedState = try await session.web.evaluateJavaScript("localStorage.getItem('gameState')") as? String
                guard htmlSavedState != nil, htmlSavedState != before else { throw LibraryError("2048 board did not respond to keyboard input") }
            } else {
                let moved = try await session.web.evaluateJavaScript("window.moves !== undefined && window.checkReady")
                // Right then left returns to zero; the fixture also counts delivered key events.
                guard moved as? Bool == true,
                      (try await session.web.evaluateJavaScript("window.keyCount >= 2")) as? Bool == true else { throw LibraryError("HTML keyboard input did not reach the game") }
            }
            try await session.web.evaluateJavaScript("localStorage.setItem('flashback-html-check','saved'); void 0;")
            session.start()
        } else if phase == 4 {
            phase = 5
            try await Task.sleep(nanoseconds:2_000_000_000)
            let saved = try await session.web.evaluateJavaScript("localStorage.getItem('flashback-html-check')")
            guard saved as? String == "saved" else { throw LibraryError("HTML saves did not survive restart") }
            if htmlIs2048 {
                let state = try await session.web.evaluateJavaScript("localStorage.getItem('gameState')") as? String
                guard state == htmlSavedState else { throw LibraryError("2048 did not restore its saved board") }
            }
            let image = try await session.web.takeSnapshot(configuration:nil)
            guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) else {
                throw LibraryError("HTML player snapshot failed")
            }
            try png.write(to:output.appendingPathComponent("HTML-player.png"))
            try await renderLibrary("Library-html-light.png", scheme:.light)
            try await renderLibrary("Library-html-dark.png", scheme:.dark)
            guard try model.library.load().first?.lastPlayed != nil else { throw LibraryError("HTML recent history missing") }
            finish(nil)
        }
    }

    func renderLibrary(_ name: String, scheme: ColorScheme, compact: Bool = false) async throws {
        guard let window = NSApp.windows.first(where:{ $0.title == "Flashback" }), let view = window.contentView else {
            throw LibraryError("Library window is unavailable")
        }
        window.appearance = NSAppearance(named:scheme == .dark ? .darkAqua : .aqua)
        window.setContentSize(compact ? NSSize(width:800,height:600) : NSSize(width:1080,height:720))
        window.orderFront(nil)
        try await Task.sleep(nanoseconds:400_000_000)
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw LibraryError("Could not render the library") }
        view.cacheDisplay(in:view.bounds, to:bitmap)
        guard let png = bitmap.representation(using:.png,properties:[:]) else { throw LibraryError("Could not encode the library render") }
        try png.write(to:output.appendingPathComponent(name))
    }

    func finish(_ error: String?) {
        guard !finished else { return }; finished = true
        let passed = phase == 10 ? "PASS: Shockwave recorded gameplay condition, native input sequence, and game assets"
            : phase == 9 ? "OBSERVED: Shockwave opened; screenshots and runtime state captured; gameplay has not been asserted"
            : phase == 8 ? "PASS: Shockwave import, original game playback, native mouse/keyboard input, audio backend, offline policy, resizing/fullscreen/restore, Director preference persistence across restart, recent history, and player/library rendering"
            : phase == 5 && htmlIs2048
            ? "PASS: original 2048 ZIP import, rendered tiles, native keyboard moves, board persistence across restart, offline policy, recent history, and player/library rendering"
            : phase == 5
            ? "PASS: ZIP drop decoding, extraction, HTML import, duplicate detection, CSS, script modules, local fetch, assets, keyboard input, offline policy, restart, local storage, recent history, and native library/player rendering"
            : phase == 3
            ? "PASS: Java dropped-file decoding, complete JAR import, bundled runtime launch, visible game window, duplicate-process prevention, recent history, process cleanup, and light/dark/compact library rendering"
            : "PASS: dropped-file decoding, embedded Flash playback, complete TextTwist assets, pause/resume, mute, restart, persistent local storage, offline network policy, recent history, and light/dark/compact library rendering"
        let message = error.map { "FAIL: \($0)" } ?? passed
        try? Data((message + "\n").utf8).write(to:output.appendingPathComponent("Result.txt"))
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
        for window in Array(model.windows.values) { window.close() }
        for session in Array(model.javaSessions.values) { session.stop() }
        exit(error == nil ? 0 : 1)
    }
}
