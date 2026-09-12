// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import SwiftUI
import WebKit

@MainActor func saveWindowCapture(_ window: NSWindow, to url: URL) throws {
    if ProcessInfo.processInfo.environment["FLASHBACK_CAPTURE_WINDOWS"] == "1" {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath:"/usr/sbin/screencapture")
        capture.arguments = ["-x","-o","-l",String(window.windowNumber),url.path]
        try capture.run(); capture.waitUntilExit()
        guard capture.terminationStatus == 0 else { throw LibraryError("Native window capture failed") }
    } else {
        let view = window.contentView!
        let bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
        view.cacheDisplay(in:view.bounds,to:bitmap)
        try bitmap.representation(using:.png,properties:[:])!.write(to:url)
    }
}

/// Geometry is collected only in --layout-check runs, never during ordinary play.
struct LayoutFrames: PreferenceKey {
    static var defaultValue: [String:CGRect] { [:] }
    static func reduce(value: inout [String:CGRect], nextValue: () -> [String:CGRect]) { value.merge(nextValue(),uniquingKeysWith:{ _, new in new }) }
}

extension View {
    func auditFrame(_ id: String, model: LibraryModel) -> some View {
        background {
            if model.auditsLayout {
                GeometryReader { geometry in Color.clear.preference(key:LayoutFrames.self,value:[id:geometry.frame(in:.named("library"))]) }
            }
        }
    }
}

/// Audits the real library view in an isolated library.
@MainActor final class LayoutCheck {
    let model: LibraryModel
    let window: NSWindow
    let output: URL
    var report: [String] = []
    var fixtures: [Game] = []
    init(model: LibraryModel, window: NSWindow, output: URL) { self.model = model; self.window = window; self.output = output }

    func checkWelcome(delegate: AppDelegate) {
        Task {
            let suite = "local.flashback.welcome-check." + UUID().uuidString
            let preferences = UserDefaults(suiteName:suite)!
            delegate.preferences = preferences
            var failure: String?
            do {
                try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
                delegate.showWelcomeIfNeeded()
                guard let controller = delegate.welcomeWindow, let welcome = controller.window,
                      welcome.isVisible, !preferences.bool(forKey:WelcomeWindow.completedKey) else { throw LibraryError("Welcome did not appear on first launch") }
                delegate.showWelcome()
                guard delegate.welcomeWindow === controller else { throw LibraryError("Welcome opened duplicate windows") }
                for dark in [false,true] {
                    welcome.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
                    try await Task.sleep(nanoseconds:300_000_000)
                    let view = welcome.contentView!
                    view.layoutSubtreeIfNeeded(); welcome.displayIfNeeded()
                    guard view.bounds.width == 620, view.bounds.height >= view.fittingSize.height - 1,
                          welcome.frame.height <= (welcome.screen?.visibleFrame.height ?? 800) else { throw LibraryError("Welcome content does not fit its window or screen") }
                    try saveWindowCapture(welcome,to:output.appendingPathComponent("Welcome-\(dark ? "dark" : "light").png"))
                }
                let event = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                    windowNumber:welcome.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!
                _ = welcome.performKeyEquivalent(with:event)
                try await Task.sleep(nanoseconds:200_000_000)
                guard delegate.welcomeWindow == nil, preferences.bool(forKey:WelcomeWindow.completedKey), window.isVisible else { throw LibraryError("Open Library did not open the library and remember dismissal") }
                delegate.showWelcomeIfNeeded()
                guard delegate.welcomeWindow == nil else { throw LibraryError("Welcome reappeared after completion") }
                guard let help = NSApp.helpMenu, let item = help.items.firstIndex(where:{ $0.action == #selector(AppDelegate.showWelcome) }) else { throw LibraryError("Welcome menu item is missing") }
                help.performActionForItem(at:item)
                try await Task.sleep(nanoseconds:200_000_000)
                guard let reopened = delegate.welcomeWindow?.window, reopened.isVisible else { throw LibraryError("Help did not reopen Welcome") }
                let bounds = reopened.contentView!.bounds
                try await click(CGRect(x:bounds.width-220,y:bounds.height-46,width:1,height:1),in:reopened)
                guard delegate.welcomeWindow == nil, model.websiteWindow?.window?.isVisible == true else { throw LibraryError("Website shortcut did not open the extractor") }
                model.websiteWindow?.close()
                preferences.removeObject(forKey:WelcomeWindow.completedKey)
                delegate.showWelcomeIfNeeded(); delegate.welcomeWindow?.window?.performClose(nil)
                guard delegate.welcomeWindow == nil, preferences.bool(forKey:WelcomeWindow.completedKey) else { throw LibraryError("Closing Welcome did not remember dismissal") }
                report.append("PASS: first-launch welcome, single window, light/dark rendering, Return key, persistent dismissal, Help reopening, native website button click, and close button")
            } catch { failure = error.localizedDescription }
            preferences.removePersistentDomain(forName:suite); delegate.preferences = .standard
            finish(failure)
        }
    }

    func run(secondaryOnly: Bool = false) {
        Task {
            do {
                try FileManager.default.createDirectory(at:output, withIntermediateDirectories:true)
                try makeGames()
                try await checkArtwork()
                if secondaryOnly { try await checkSecondarySurfaces(); try await checkPlayerLayouts(); finish(nil); return }
                try await inspect("two-games-dark", size:NSSize(width:1080,height:720), dark:true, count:2)
                try await inspect("two-games-light", size:NSSize(width:1080,height:720), dark:false, count:2)
                for dark in [false,true] {
                    for size in [NSSize(width:800,height:600),NSSize(width:930,height:660),NSSize(width:950,height:660),NSSize(width:1080,height:720),NSSize(width:1440,height:900)] {
                        let name = "many-\(Int(size.width))-\(dark ? "dark" : "light")"
                        try await inspect(name, size:size, dark:dark, count:24)
                        try await inspect(name + "-bottom", size:size, dark:dark, count:24, bottom:true)
                    }
                    try await inspect("empty-\(dark)", size:NSSize(width:800,height:600), dark:dark, count:0)
                    try await inspect("favorites-\(dark)", size:NSSize(width:800,height:600), dark:dark, count:24, filter:.favorites)
                    try await inspect("recent-\(dark)", size:NSSize(width:800,height:600), dark:dark, count:24, filter:.recent)
                    try await inspect("search-\(dark)", size:NSSize(width:800,height:600), dark:dark, count:24, query:"Portrait")
                    try await inspect("no-results-\(dark)", size:NSSize(width:800,height:600), dark:dark, count:24, query:String(repeating:"No match ",count:30))
                    try await inspect("importing-\(dark)", size:NSSize(width:800,height:600), dark:dark, count:24, importing:true)
                }
                try await checkClicks()
                try await checkSecondarySurfaces()
                try await checkPlayerLayouts()
                finish(nil)
            } catch { finish(error.localizedDescription) }
        }
    }

    func makeGames() throws {
        let fm = FileManager.default
        let covers = model.library.root.appendingPathComponent("Covers")
        try fm.createDirectory(at:covers, withIntermediateDirectories:true)
        let titles = ["Wiz 3", "TextTwist 2", "A Very Long Game Title With Several Words That Should Stay Inside Its Own Card",
                      String(repeating:"W",count:120), "小さな冒険 · مغامرة · 🎮", "Portrait Quest", "No artwork", "Another round"]
        let original = GameLibrary(root:fm.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Flashback"))
        let personalGames = (try? original.load()) ?? []
        for i in 0..<24 {
            let game = Game(id:String(format:"%064x",i+1),title:titles[i % titles.count],entry:["game.jar","game.swf","index.html","game.dcr"][i % 4],bytes:1,added:Date(timeIntervalSince1970:1_600_000_000-Double(i)*3600),lastPlayed:i.isMultiple(of:2) ? Date(timeIntervalSince1970:1_600_000_000-Double(i)*3600) : nil,favorite:i.isMultiple(of:3))
            fixtures.append(game)
            let destination = covers.appendingPathComponent("\(game.id).png")
            if i < 2, let personal = personalGames.first(where:{ $0.title == game.title }),
               let data = try? Data(contentsOf:original.root.appendingPathComponent("Covers/\(personal.id).png")) {
                try data.write(to:destination); continue
            }
            if i % 8 == 6 { continue }
            let size = [NSSize(width:496,height:256),NSSize(width:1120,height:838),NSSize(width:1800,height:180),NSSize(width:180,height:1600)][i % 4]
            let image = NSImage(size:size)
            image.lockFocus()
            NSColor(calibratedHue:CGFloat(i % 8)/8,saturation:0.65,brightness:0.65,alpha:1).setFill()
            NSBezierPath(rect:NSRect(origin:.zero,size:size)).fill()
            let text = "\(i+1)"
            text.draw(at:NSPoint(x:12,y:12),withAttributes:[.font:NSFont.boldSystemFont(ofSize:48),.foregroundColor:NSColor.white])
            image.unlockFocus()
            let png = NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
            try png.write(to:destination)
        }
    }

    func capture(_ window: NSWindow, name: String) async throws {
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds:250_000_000)
        let view = window.contentView!
        view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        try saveWindowCapture(window,to:output.appendingPathComponent(name + ".png"))
    }

    func checkArtwork() async throws {
        let game = fixtures[0], library = model.library
        try await inspect("artwork-before",size:NSSize(width:1080,height:720),dark:false,count:2)
        let original = try Data(contentsOf:library.defaultArtworkURL(game))
        let image = NSImage(size:NSSize(width:1440,height:900))
        image.lockFocus()
        NSColor(srgbRed:0.04,green:0.4,blue:0.38,alpha:1).setFill()
        NSBezierPath(rect:NSRect(x:0,y:0,width:1440,height:900)).fill()
        "MY ARTWORK".draw(at:NSPoint(x:160,y:400),withAttributes:[.font:NSFont.boldSystemFont(ofSize:120),.foregroundColor:NSColor.white])
        image.unlockFocus()
        let file = library.root.appendingPathComponent("My Artwork.png")
        try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:file)
        let revision = model.coverRevision
        await model.changeArtwork(file,for:game)
        guard model.alert == nil, model.coverRevision == revision + 1,
              library.artworkURL(game) == library.customArtworkURL(game),
              GameLibrary(root:library.root).artworkURL(game) == library.customArtworkURL(game) else { throw LibraryError("Changing artwork did not refresh or persist") }
        for dark in [false,true] {
            try await inspect("artwork-custom-\(dark)",size:NSSize(width:1080,height:720),dark:dark,count:2)
        }
        model.restoreArtwork(game)
        guard model.alert == nil, library.artworkURL(game) == library.defaultArtworkURL(game),
              try Data(contentsOf:library.defaultArtworkURL(game)) == original else { throw LibraryError("Restoring artwork did not preserve the original") }
        try await inspect("artwork-restored",size:NSSize(width:1080,height:720),dark:false,count:2)

        // Dropping an image on a card is the same change without the chooser.
        // A game file dropped on a card must NOT be taken as artwork — the card
        // has to decline it so the window's import drop still sees it.
        let dropRevision = model.coverRevision
        let imageDrop = NSItemProvider(contentsOf:file)!
        guard model.receiveArtworkDrop([imageDrop],for:game) else {
            throw LibraryError("A dropped image was not accepted as artwork")
        }
        // The drop hands off to a Task, so wait for it rather than assuming.
        for _ in 0..<40 where model.coverRevision == dropRevision {
            try await Task.sleep(nanoseconds:100_000_000)
        }
        guard model.alert == nil, library.artworkURL(game) == library.customArtworkURL(game),
              try Data(contentsOf:library.customArtworkURL(game)) != original else {
            throw LibraryError("Dropping an image did not replace the card's artwork")
        }
        let gameDrop = NSItemProvider(contentsOf:library.folder(for:game).appendingPathComponent(game.entry))
        if let gameDrop, model.receiveArtworkDrop([gameDrop],for:game) {
            throw LibraryError("A dropped game file was taken as artwork")
        }
        model.restoreArtwork(game)
        guard library.artworkURL(game) == library.defaultArtworkURL(game) else {
            throw LibraryError("Restoring after a dropped image did not return the original cover")
        }
        report.append("PASS: custom artwork changes refresh library cards, persist, render in light/dark, restore the original cover, and accept an image dropped on a card while declining a dropped game")
    }

    func checkSecondarySurfaces() async throws {
        let original = fixtures
        fixtures = fixtures.map { var game = $0; game.favorite = false; game.lastPlayed = nil; return game }
        for dark in [false,true] {
            try await inspect("no-favorites-\(dark)",size:NSSize(width:800,height:600),dark:dark,count:24,filter:.favorites)
            try await inspect("no-recent-\(dark)",size:NSSize(width:800,height:600),dark:dark,count:24,filter:.recent)
        }
        fixtures = original
        try await inspect("native-dialogs",size:NSSize(width:930,height:660),dark:false,count:24)
        for appearance in [NSAppearance.Name.accessibilityHighContrastAqua,.accessibilityHighContrastDarkAqua] {
            window.appearance = NSAppearance(named:appearance)
            try await capture(window,name:"library-\(appearance.rawValue)")
        }
        for dark in [false,true] {
            window.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
            window.makeKeyAndOrderFront(nil)
            for name in ["rename","remove","choose-file","choose-artwork","choose-entry"] {
                // Let activation and the previous sheet's dismissal finish
                // before invoking a dialog directly from the audit.
                NSApp.activate(ignoringOtherApps:true)
                window.makeKeyAndOrderFront(nil)
                try await Task.sleep(nanoseconds:500_000_000)
                let before = model.games
                var selection: Task<String?,Never>?
                switch name {
                case "rename": model.rename(fixtures[2])
                case "remove": model.remove(fixtures[2])
                case "choose-file": model.chooseFiles()
                case "choose-artwork": model.chooseArtwork(fixtures[2])
                default:
                    let plan = ImportPlan(source:model.library.root,files:[],movies:["main.swf","intro.swf","assets/a-long-folder-name/another-game.swf"],bytes:0,isFolder:true)
                    selection = Task { await model.selectEntry(plan) }
                }
                for _ in 0..<30 {
                    if window.attachedSheet != nil { break }
                    try await Task.sleep(nanoseconds:100_000_000)
                }
                guard let sheet = window.attachedSheet else {
                    throw LibraryError("\(name) did not open as a window sheet; key=\(NSApp.keyWindow?.title ?? "nil"), main=\(NSApp.mainWindow?.title ?? "nil"), windows=\(NSApp.windows.map { $0.title + ":" + String($0.isVisible) + ":" + ($0.sheetParent?.title ?? "none") })")
                }
                sheet.appearance = window.appearance
                try await capture(sheet,name:"dialog-\(name)-\(dark)")
                if let panel = sheet as? NSOpenPanel { panel.cancel(nil) }
                else { window.endSheet(sheet,returnCode:.alertSecondButtonReturn) }
                sheet.orderOut(nil)
                if let selection { guard await selection.value == nil else { throw LibraryError("Cancel selected a game entry") } }
                try await Task.sleep(nanoseconds:200_000_000)
                guard model.games == before, !model.isImporting else { throw LibraryError("Cancel changed the library") }
            }
            model.help()
            guard let help = model.helpWindow?.window else { throw LibraryError("Help window did not open") }
            help.appearance = window.appearance
            help.setContentSize(NSSize(width:560,height:500))
            try await capture(help,name:"help-top-\(dark)")
            if let scroll = scrollView(in:help.contentView!), let document = scroll.documentView {
                let y = document.isFlipped ? max(0,document.bounds.height-scroll.contentSize.height) : 0
                scroll.contentView.scroll(to:NSPoint(x:0,y:y)); scroll.reflectScrolledClipView(scroll.contentView)
            }
            try await capture(help,name:"help-bottom-\(dark)")
            model.helpWindow?.close()
            NSApp.activate(ignoringOtherApps:true)
            (NSApp.delegate as? AppDelegate)?.about()
            try await Task.sleep(nanoseconds:600_000_000)
            guard let about = NSApp.windows.first(where:{ $0.isVisible && $0 !== window && $0.sheetParent == nil }) else {
                throw LibraryError("About panel did not open: \(NSApp.windows.map { $0.title + ":" + String($0.isVisible) })")
            }
            about.appearance = window.appearance
            try await capture(about,name:"about-\(dark)"); about.close()
        }
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame:.zero,configuration:config)
        let documents = NSWindow(contentRect:NSRect(x:0,y:0,width:640,height:640),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        documents.title = "Licenses and Source"; documents.isReleasedWhenClosed = false
        documents.contentView = web; documents.center(); documents.makeKeyAndOrderFront(nil)
        guard let resources = Bundle.main.resourceURL else { throw LibraryError("App resources unavailable") }
        web.loadFileURL(resources.appendingPathComponent("Licenses.html"),allowingReadAccessTo:resources)
        for _ in 0..<60 { if !web.isLoading { break }; try await Task.sleep(nanoseconds:100_000_000) }
        guard try await web.evaluateJavaScript("document.querySelector('h1')?.textContent") as? String == "Licenses and Source" else { throw LibraryError("License page did not load") }
        for dark in [false,true] {
            documents.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
            try await web.evaluateJavaScript("window.scrollTo(0,0)")
            try await capture(documents,name:"licenses-top-\(dark)")
            try await web.evaluateJavaScript("window.scrollTo(0,document.body.scrollHeight)")
            try await capture(documents,name:"licenses-bottom-\(dark)")
        }
        documents.close()
        report.append("PASS: empty filters, high contrast, native import/entry/rename/removal sheets and cancellation, Help scrolling, and About")
    }

    func inspect(_ name: String, size: NSSize, dark: Bool, count: Int, filter: LibraryFilter = .all, query: String = "", importing: Bool = false, bottom: Bool = false) async throws {
        model.games = Array(fixtures.prefix(count)); model.filter = filter; model.query = query
        model.isImporting = importing
        model.status = importing ? "Adding " + String(repeating:"A very long game archive name ",count:20) + ".zip…" : ""
        window.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds:600_000_000)
        let view = window.contentView!
        if let scroll = scrollView(in:view), let document = scroll.documentView {
            let maxY = max(0,document.bounds.height-scroll.contentSize.height)
            let y = bottom == document.isFlipped ? maxY : 0
            scroll.contentView.scroll(to:NSPoint(x:0,y:y)); scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(nanoseconds:250_000_000)
        } else if bottom { throw LibraryError("\(name): game scroll view was unavailable") }
        view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        try saveWindowCapture(window,to:output.appendingPathComponent(name + ".png"))
        let entries = model.layoutFrames.sorted { $0.key < $1.key }.map { ($0.key,$0.value) }
        let data = entries.map { "\($0.0): \($0.1)" }.joined(separator:"\n")
        try Data(data.utf8).write(to:output.appendingPathComponent(name + "-frames.txt"))
        let frames = model.layoutFrames
        let cards = entries.filter { $0.0.hasPrefix("card-") }
        let expected = model.visibleGames.count
        guard cards.count >= min(expected,4), cards.count <= expected else { throw LibraryError("\(name): expected game cards were missing") }
        guard (cards.map { $0.1.width }.max() ?? 0) - (cards.map { $0.1.width }.min() ?? 0) < 1 else { throw LibraryError("\(name): artwork makes cards wider than their grid columns") }
        for i in cards.indices {
            let id = String(cards[i].0.dropFirst(5)), card = cards[i].1
            guard card.width >= 219.5, card.width <= 320.5, let grid = frames["grid"],
                  card.minX >= grid.minX-0.5, card.maxX <= grid.maxX+0.5 else { throw LibraryError("\(name): a card escaped its grid column") }
            for part in ["play-", "caption-", "favorite-"] {
                guard let frame = frames[part + id], card.insetBy(dx:-0.5,dy:-0.5).contains(frame) else { throw LibraryError("\(name): \(part) escaped its card") }
            }
            guard let favorite = frames["favorite-" + id], favorite.width >= 27.9, favorite.height >= 27.9,
                  let caption = frames["caption-" + id], !caption.intersects(favorite) else { throw LibraryError("\(name): title and favorite button collide or the button is too small") }
            for j in cards.indices where j > i {
                if cards[i].1.intersects(cards[j].1) { throw LibraryError("\(name): game buttons overlap: \(cards[i].1), \(cards[j].1)") }
                if abs(card.minY-cards[j].1.minY) < 1 {
                    let gap = max(card.minX,cards[j].1.minX)-min(card.maxX,cards[j].1.maxX)
                    if gap < 23.5 { throw LibraryError("\(name): the gap between cards disappeared") }
                }
            }
        }
        if bottom, let last = model.visibleGames.last, let card = frames["card-" + last.id], let viewport = frames["viewport"] {
            guard viewport.insetBy(dx:-1,dy:-1).contains(card) else { throw LibraryError("\(name): the final row is not fully reachable") }
        } else if bottom { throw LibraryError("\(name): the last game could not be reached") }
        for pair in [("heading","search"),("status","count")] {
            if let first = frames[pair.0], let second = frames[pair.1], first.intersects(second) { throw LibraryError("\(name): \(pair.0) overlaps \(pair.1)") }
        }
        if let countFrame = frames["count"], countFrame.height > 16 { throw LibraryError("\(name): the game count wraps") }
        for id in ["heading","search","status","count"] {
            if let frame = frames[id], !view.bounds.insetBy(dx:-1,dy:-1).contains(frame) { throw LibraryError("\(name): \(id) goes outside the window") }
        }
        report.append("PASS: \(name), \(expected) games, \(cards.count) measured cards")
    }

    func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, scroll.frame.width > 300, scroll.frame.height > 150 { return scroll }
        return view.subviews.compactMap { scrollView(in:$0) }.first
    }

    func click(_ frame: CGRect, in target: NSWindow? = nil) async throws {
        let window = target ?? self.window
        let view = window.contentView!
        let point = view.convert(NSPoint(x:frame.midX,y:view.isFlipped ? frame.midY : view.bounds.height-frame.midY),to:nil)
        for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
            let event = NSEvent.mouseEvent(with:type, location:point, modifierFlags:[], timestamp:ProcessInfo.processInfo.systemUptime,
                windowNumber:window.windowNumber, context:nil, eventNumber:0, clickCount:1, pressure:1)!
            NSApp.postEvent(event,atStart:false)
        }
        try await Task.sleep(nanoseconds:250_000_000)
    }

    func checkClicks() async throws {
        try await inspect("click-targets",size:NSSize(width:1080,height:720),dark:true,count:2)
        let first = model.visibleGames[0], second = model.visibleGames[1]
        guard let favorite = model.layoutFrames["favorite-" + first.id],
              let a = model.layoutFrames["play-" + first.id], let b = model.layoutFrames["play-" + second.id] else { throw LibraryError("Click targets unavailable") }
        try await click(favorite)
        guard model.games.first(where:{ $0.id == first.id })?.favorite != first.favorite,
              model.games.first(where:{ $0.id == second.id })?.favorite == second.favorite, model.alert == nil else { throw LibraryError("Favorite click reached the wrong game") }
        try await click(CGRect(x:(a.maxX+b.minX)/2,y:a.midY,width:1,height:1))
        guard model.alert == nil, model.windows.isEmpty, model.javaSessions.isEmpty else { throw LibraryError("Clicking a gap activated a game") }
        func sidebarFrame(_ row: Int) throws -> CGRect {
            func sidebarTable(_ view: NSView) -> NSTableView? {
                if let table = view as? NSTableView, table.frame.width < 300 { return table }
                return view.subviews.compactMap { sidebarTable($0) }.first
            }
            guard let table = sidebarTable(window.contentView!), table.numberOfRows > row else { throw LibraryError("Native sidebar is unavailable") }
            let view = window.contentView!
            let rect = table.convert(table.rect(ofRow:row),to:view)
            return CGRect(x:rect.minX,y:view.isFlipped ? rect.minY : view.bounds.height-rect.maxY,width:rect.width,height:rect.height)
        }
        try await click(sidebarFrame(1))
        guard model.filter == .favorites else { throw LibraryError("Favorites button did not switch the library") }
        try await click(sidebarFrame(2))
        guard model.filter == .recent else { throw LibraryError("Recently played button did not switch the library") }
        try await inspect("clear-search",size:NSSize(width:800,height:600),dark:false,count:24,query:"Portrait")
        try await click(model.layoutFrames["clear-search"]!)
        guard model.query.isEmpty, model.visibleGames.count == 24 else { throw LibraryError("Clear search did not restore the collection") }
        (NSApp.delegate as? AppDelegate)?.findGame()
        try await Task.sleep(nanoseconds:250_000_000)
        guard let editor = window.firstResponder as? NSTextView else { throw LibraryError("Find Game did not focus search") }
        editor.insertText("Wiz",replacementRange:NSRange(location:0,length:0))
        try await Task.sleep(nanoseconds:250_000_000)
        guard model.query == "Wiz", model.visibleGames.count == 3 else { throw LibraryError("Focused search did not filter games") }
        try await capture(window,name:"search-focus")
        report.append("PASS: native favorite, empty-gap, sidebar selection, clear search, and Find Game keyboard focus")
    }

    func checkPlayerLayouts() async throws {
        for entry in ["game.swf","index.html","game.dcr"] {
            let game = Game(id:String(repeating:"a",count:64),title:String(repeating:"A very long game title ",count:8),entry:entry,bytes:1,added:Date())
            let session = PlayerSession(game:game,library:model.library,resources:output,dataStore:.nonPersistent())
            let controller = GameWindow(session:session)
            let player = controller.window!
            player.setContentSize(NSSize(width:640,height:500)); player.makeKeyAndOrderFront(nil)
            for dark in [false,true] {
                player.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
                for state in ["loading","error","paused"] where game.isFlash || state != "paused" {
                    session.loading = state == "loading"; session.paused = state == "paused"
                    session.failure = state == "error" ? "The game couldn’t open. Add its complete folder, including graphics, sounds, and other game files." : nil
                    try await Task.sleep(nanoseconds:250_000_000)
                    let view = player.contentView!; view.layoutSubtreeIfNeeded(); player.displayIfNeeded()
                    guard abs(view.bounds.width-640) < 1, abs(view.bounds.height-500) < 1 else {
                        throw LibraryError("Player status enlarged the compact window: \(view.bounds.size)")
                    }
                    try saveWindowCapture(player,to:output.appendingPathComponent("player-\(game.format.lowercased())-\(state)-\(dark).png"))
                }
            }
            controller.close()
        }
        report.append("PASS: compact Flash/HTML/Shockwave player views rendered with long names in light/dark loading, error, and pause states")
    }

    func finish(_ error: String?) {
        let message = (report + [error.map { "FAIL: \($0)" } ?? "PASS: library layout audit"]).joined(separator:"\n") + "\n"
        try? Data(message.utf8).write(to:output.appendingPathComponent("Result.txt"))
        FileHandle.standardOutput.write(Data(message.utf8))
        exit(error == nil ? 0 : 1)
    }
}
