// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import WebKit

@MainActor final class WebsiteUICheck {
    let model: LibraryModel
    let output: URL
    var window: WebsiteImportWindow?
    init(model: LibraryModel, output: URL) { self.model = model; self.output = output }
    func run(url: URL) {
        Task {
            do {
                try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
                model.playerDataStore = .nonPersistent()
                let local = ["127.0.0.1","localhost"].contains(url.host ?? "")
                let controller = WebsiteImportWindow(libraryModel:model,allowLocal:local)
                controller.model.address = url.absoluteString
                window = controller; controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
                try await snapshot("Website-address-light.png",dark:false)
                try await snapshot("Website-address-dark.png",dark:true)
                guard controller.model.address == url.absoluteString else { throw LibraryError("The address was edited during the UI check") }
                try await activatePrimary(); await controller.model.operation?.value
                guard controller.model.phase == .results, !controller.model.candidates.isEmpty else { throw LibraryError(controller.model.error ?? "Website discovery returned no game") }
                try await snapshot("Website-results-light.png",dark:false)
                try await snapshot("Website-results-dark.png",dark:true)
                try await activatePrimary(keyboard:true); await controller.model.operation?.value
                guard controller.model.phase == .review, let recovery = controller.model.recovery else { throw LibraryError(controller.model.error ?? "Recovery did not finish") }
                try recovery.record.report.write(to:output.appendingPathComponent("Recovery.txt"),atomically:true,encoding:.utf8)
                try await snapshot("Website-review-light.png",dark:false)
                try await snapshot("Website-review-dark.png",dark:true)
                try await activatePrimary(keyboard:true); await controller.model.operation?.value
                guard controller.model.phase == .done, let game = controller.model.added else { throw LibraryError(controller.model.error ?? "Recovered game was not added") }
                guard try model.library.load().contains(where:{ $0.id == game.id }), model.library.webRecord(game) != nil else { throw LibraryError("Game or provenance did not persist") }
                try await snapshot("Website-complete.png",dark:false)
                model.play(game)
                if game.isJava {
                    try await Task.sleep(nanoseconds:8_000_000_000)
                    guard let session = model.javaSessions[game.id], session.process.isRunning else { throw LibraryError("Recovered Java game did not launch") }
                    session.stop()
                } else {
                    guard let session = model.windows[game.id]?.session else { throw LibraryError("Recovered game player was not created") }
                    for _ in 0..<80 {
                        if !session.loading { break }
                        try await Task.sleep(nanoseconds:500_000_000)
                    }
                    try await Task.sleep(nanoseconds:5_000_000_000)
                    if let failure = session.failure { throw LibraryError(failure) }
                    guard !session.loading else { throw LibraryError("Recovered game did not finish loading") }
                    if local && game.isHTML {
                        let ready = try await session.web.evaluateJavaScript("window.websiteCheckReady === true")
                        if ready as? Bool != true {
                            let detail = try await session.web.evaluateJavaScript("document.body.innerText")
                            throw LibraryError("Recovered HTML modules or data failed: \(detail as? String ?? "No page content")")
                        }
                        try await session.web.evaluateJavaScript("document.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true})); void 0;")
                        let moves = try await session.web.evaluateJavaScript("window.websiteMoves")
                        guard (moves as? NSNumber)?.intValue == 1 else { throw LibraryError("Recovered HTML game did not accept input") }
                    }
                    if game.isFlash {
                        guard try await session.web.evaluateJavaScript("player.ruffle().metadata") is [String:Any] else { throw LibraryError("Recovered Flash game did not load") }
                    }
                    if session.missingFiles {
                        let image = try await session.web.takeSnapshot(configuration:nil)
                        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) { try png.write(to:output.appendingPathComponent("Website-player-missing.png")) }
                        throw LibraryError("Recovered game requested missing assets during launch: " + session.missingResources.joined(separator:"\n"))
                    }
                    let blocked = try await session.web.callAsyncJavaScript("try { await fetch('https://example.com/not-recovered'); return false; } catch { return true; }",arguments:[:],in:nil,contentWorld:.page)
                    guard blocked as? Bool == true else { throw LibraryError("Playback contacted an unrecovered website") }
                    let image = try await session.web.takeSnapshot(configuration:nil)
                    if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) { try png.write(to:output.appendingPathComponent("Website-player.png")) }
                    model.windows[game.id]?.close()
                }
                if local {
                    let dynamic = url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("dynamic")
                    let snapshots = try await WebPageScanner(allowLocal:true).scan(dynamic)
                    guard snapshots.contains(where:{ WebPage.parse($0.html,url:$0.url).candidates.contains { $0.url.path == "/flash/main.swf" && $0.parameters["language"] == "dynamic" } }) else { throw LibraryError("Dynamic scan did not capture the plug-in-gated loader and its launch parameters") }
                    try await inspectStates()
                }
                finish(nil)
            } catch { finish(error.localizedDescription) }
        }
    }
    func activatePrimary(keyboard: Bool = false) async throws {
        guard let window = window?.window, let view = window.contentView else { throw LibraryError("Import window is missing") }
        window.makeKeyAndOrderFront(nil)
        if keyboard {
            let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                windowNumber:window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
            guard window.performKeyEquivalent(with:event) else { throw LibraryError("The import window did not handle its Return shortcut") }
        } else {
            let point = view.convert(NSPoint(x:view.bounds.width-80,y:view.isFlipped ? view.bounds.height-30 : 30),to:nil)
            for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
                let event = NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                    windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
                NSApp.postEvent(event,atStart:false)
            }
        }
        try await Task.sleep(nanoseconds:250_000_000)
    }
    func inspectStates() async throws {
        guard let controller = window, let recovery = controller.model.recovery else { throw LibraryError("Recovery state unavailable for visual checks") }
        let model = controller.model
        controller.window?.setContentSize(NSSize(width:640,height:530))
        for dark in [false,true] {
            model.phase = .scanning; model.error = nil
            model.progress = WebProgress(message:"Finding games…",detail:"Checking embedded players and game files")
            try await snapshot("Website-scanning-\(dark).png",dark:dark)
            model.phase = .recovering
            model.progress = WebProgress(message:"Recovering game files…",detail:"https://example.com/" + String(repeating:"long-asset-folder/",count:12),files:125,bytes:15_728_640)
            try await snapshot("Website-recovering-\(dark).png",dark:dark)
            model.phase = .results; model.candidates = []; model.selection = nil; model.deeper = false
            try await snapshot("Website-no-results-\(dark).png",dark:dark)
            model.candidates = (1...12).map { index in
                let url = URL(string:"https://example.com/" + String(repeating:"long-asset-folder/",count:8) + "game-\(index).swf")!
                return WebCandidate(url:url,pageURL:url,title:"A game with a long title \(index)",kind:"swf",evidence:"Embedded Flash game",score:100)
            }
            model.selection = model.candidates.first?.id
            try await snapshot("Website-many-results-\(dark).png",dark:dark)
            var record = recovery.record
            record.issues = [WebImportRecord.Issue(url:URL(string:"https://example.com/sounds/level1.mp3")!,reason:"The server returned 404",evidence:"Referenced by the game")]
            model.recovery = WebRecovery(source:recovery.source,entry:recovery.entry,record:record)
            model.phase = .review; model.title = String(repeating:"A long game title ",count:8)
            try await snapshot("Website-partial-review-\(dark).png",dark:dark)
            model.phase = .adding
            try await snapshot("Website-adding-\(dark).png",dark:dark)
            model.phase = .address
            model.error = "The website could not be reached. Check the address and try again. " + String(repeating:"A detailed server response. ",count:8)
            try await snapshot("Website-error-\(dark).png",dark:dark)
        }
        model.error = nil; model.phase = .done; model.recovery = recovery
    }
    func snapshot(_ name: String, dark: Bool) async throws {
        guard let view = window?.window?.contentView else { throw LibraryError("Import window is missing") }
        window?.window?.makeKeyAndOrderFront(nil)
        window?.window?.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        try await Task.sleep(nanoseconds:500_000_000)
        try saveWindowCapture(window!.window!,to:output.appendingPathComponent(name))
    }
    func finish(_ error: String?) {
        let text = error.map { "FAIL: " + $0 } ?? "PASS: website import UI, persistent library, and offline playback"
        try? text.write(to:output.appendingPathComponent("Result.txt"),atomically:true,encoding:.utf8)
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
        for window in Array(model.windows.values) { window.close() }
        for session in Array(model.javaSessions.values) { session.stop() }
        exit(error == nil ? 0 : 1)
    }
}
