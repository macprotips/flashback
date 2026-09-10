// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import WebKit

@MainActor final class ArchiveUICheck {
    let model: LibraryModel
    let window: NSWindow
    let output: URL
    var catalog: ArchiveModel { model.archive }
    init(model: LibraryModel, window: NSWindow, output: URL) { self.model = model; self.window = window; self.output = output }
    func run(live: Bool) {
        Task {
            do {
                try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
                model.playerDataStore = .nonPersistent()
                try await pause(); try await click("discover")
                for _ in 0..<20 { if catalog.started { break }; try await pause(0.1) }
                guard model.showingDiscover, catalog.started else { throw LibraryError("Discover button did not open the catalog (visible: \(model.showingDiscover), started: \(catalog.started))") }
                await catalog.searchTask?.value
                guard !catalog.items.isEmpty else { throw LibraryError(catalog.error ?? "Discover has no games") }
                try await pause(2)
                try await snapshot("Catalog-featured-light.png",dark:false)
                try await snapshot("Catalog-featured-dark.png",dark:true)
                if live { catalog.query = "alien hominid"; try await click("archive-search-button"); await catalog.searchTask?.value }
                let item = live ? catalog.items.first(where:{ $0.id == "1100_alien_hominid" }) ?? catalog.items[0] : catalog.items[0]
                try await pause();try await click("archive-card-" + item.id);await catalog.detailTask?.value
                guard catalog.detail != nil, catalog.file != nil else { throw LibraryError(catalog.detailError ?? "Details did not load") }
                try await pause(2)
                try await snapshot("Catalog-details-light.png",dark:false,detail:true)
                try await snapshot("Catalog-details-dark.png",dark:true,detail:true)
                try await click("archive-download",detail:true);await catalog.downloadTask?.value
                guard let game = catalog.added, catalog.installed?.id == game.id else { throw LibraryError(catalog.detailError ?? "Download did not reach library") }
                guard try model.library.load().contains(where:{ $0.id == game.id }), model.library.webRecord(game) != nil,
                      FileManager.default.fileExists(atPath:model.library.defaultArtworkURL(game).path) else { throw LibraryError("Game, provenance, or Archive artwork did not persist") }
                try await snapshot("Catalog-added.png",dark:false,detail:true)
                try await click("archive-play",detail:true)
                guard let session = model.windows[game.id]?.session else { throw LibraryError("Play did not open a player") }
                for _ in 0..<80 { if !session.loading { break }; try await pause(0.5) }
                try await pause(4)
                if let error = session.failure { throw LibraryError(error) }
                guard !session.loading else { throw LibraryError("Downloaded game did not load") }
                if game.isHTML {
                    guard try await session.web.evaluateJavaScript("window.archiveReady === true") as? Bool == true else { throw LibraryError("Downloaded HTML supporting files did not load offline") }
                    let moved = try await session.web.evaluateJavaScript("(() => { const before = window.archiveMoves; document.querySelector('button').click(); return window.archiveMoves === before + 1; })()")
                    guard moved as? Bool == true else {
                        let detail = try await session.web.evaluateJavaScript("JSON.stringify({moves:window.archiveMoves,html:document.querySelector('button').outerHTML,handler:String(document.querySelector('button').onclick),text:document.body.innerText})")
                        throw LibraryError("Downloaded HTML game did not accept input: \(String(describing:detail))")
                    }
                }
                if game.isFlash { guard try await session.web.evaluateJavaScript("player.ruffle().metadata") is [String:Any] else { throw LibraryError("Downloaded Flash game did not initialize") } }
                guard !session.missingFiles else { throw LibraryError("Downloaded game requested missing files: " + session.missingResources.joined(separator:", ")) }
                let screenshot = try await session.web.takeSnapshot(configuration:nil)
                if let tiff = screenshot.tiffRepresentation, let png = NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) { try png.write(to:output.appendingPathComponent("Catalog-offline-player.png")) }
                model.windows[game.id]?.close()
                if !live {
                    let original = catalog.detail!, originalFile = catalog.fileName
                    let alternate = ArchiveFile(name:"another/play.html",bytes:100,sha1:"")
                    catalog.detail = ArchiveDetail(item:original.item,description:original.description,date:original.date,rights:original.rights,files:original.files + [alternate],restricted:false)
                    catalog.fileName = alternate.name
                    guard catalog.installed == nil else { throw LibraryError("Another file with the same name was mistaken for the installed game") }
                    catalog.fileName = originalFile;catalog.detail = original
                    try model.library.setArtwork(model.library.defaultArtworkURL(game),for:game)
                    let custom = try Data(contentsOf:model.library.customArtworkURL(game))
                    catalog.download();await catalog.downloadTask?.value
                    guard model.games.count == 1, try Data(contentsOf:model.library.customArtworkURL(game)) == custom else { throw LibraryError("Re-downloading duplicated a game or replaced custom artwork") }
                    catalog.show(catalog.items.first(where:{ $0.id == "zip-game" })!);await catalog.detailTask?.value;try await pause()
                    try await click("archive-download",detail:true);await catalog.downloadTask?.value
                    guard model.games.count == 2, catalog.added?.isHTML == true else { throw LibraryError(catalog.detailError ?? "ZIP did not import") }
                    catalog.show(catalog.items.first(where:{ $0.id == "slow-game" })!);await catalog.detailTask?.value;try await pause()
                    try await click("archive-download",detail:true);try await pause(0.3)
                    try await snapshot("Catalog-downloading.png",dark:false,detail:true)
                    try await click("archive-cancel",detail:true);await catalog.downloadTask?.value
                    guard !catalog.busy, !model.isImporting, model.games.count == 2 else { throw LibraryError("Canceled download changed the library") }
                    catalog.show(catalog.items.first(where:{ $0.id == "unsupported" })!);await catalog.detailTask?.value
                    try await snapshot("Catalog-unsupported.png",dark:false,detail:true)
                    catalog.detailWindow?.close()
                    window.setContentSize(NSSize(width:800,height:578))
                    catalog.query = "missing-game";catalog.search();await catalog.searchTask?.value
                    try await snapshot("Catalog-empty-compact.png",dark:false)
                    catalog.query = "offline";catalog.search();await catalog.searchTask?.value
                    guard catalog.error != nil else { throw LibraryError("Failed search lacked a retry state") }
                    try await snapshot("Catalog-error-compact.png",dark:true)
                    catalog.query = "Archive";catalog.search();await catalog.searchTask?.value
                    catalog.search(more:true);await catalog.searchTask?.value
                    guard catalog.items.contains(where:{ $0.id == "page-two" }) else { throw LibraryError("Load More lost its results") }
                    try await snapshot("Catalog-results-compact.png",dark:false)
                    catalog.query = "filter-check";try await click("archive-search-button");await catalog.searchTask?.value
                    guard catalog.items.map(\.id) == ["ordinary-game"] else { throw LibraryError("Adult content reached the Discover grid") }
                    try await snapshot("Catalog-filtered.png",dark:false)
                    catalog.query = "filtered-page";try await click("archive-search-button");await catalog.searchTask?.value
                    guard catalog.items.isEmpty, catalog.nextPage == 2 else { throw LibraryError("Filtered page lost its continuation") }
                    try await snapshot("Catalog-filtered-page.png",dark:true)
                    try await click("archive-keep-looking");await catalog.searchTask?.value
                    guard catalog.items.map(\.id) == ["page-two"], catalog.nextPage == nil else { throw LibraryError("Keep Looking did not reach the next page") }
                    try await snapshot("Catalog-filtered-next-page.png",dark:false)
                }
                catalog.showInLibrary();try await snapshot("Catalog-library.png",dark:false)
                finish(nil,live:live)
            } catch { finish(error.localizedDescription,live:live) }
        }
    }
    func pause(_ seconds: Double = 0.5) async throws { try await Task.sleep(nanoseconds:UInt64(seconds * 1_000_000_000)) }
    func click(_ name: String, detail: Bool = false) async throws {
        let target = detail ? catalog.detailWindow?.window : window
        guard let target else { throw LibraryError("Missing click window: " + name) }
        NSApp.activate(ignoringOtherApps:true);target.makeKeyAndOrderFront(nil)
        for _ in 0..<30 {
            target.contentView?.layoutSubtreeIfNeeded()
            if (detail ? catalog.detailFrames : model.layoutFrames)[name] != nil { break }
            try await pause(0.1)
        }
        guard let frame = (detail ? catalog.detailFrames : model.layoutFrames)[name] else { throw LibraryError("Missing click target: " + name + " (" + (detail ? catalog.detailFrames : model.layoutFrames).keys.sorted().joined(separator:", ") + ")") }
        try await pause(0.1)
        try await LayoutCheck(model:model,window:window,output:output).click(frame,in:target)
    }
    func snapshot(_ name: String, dark: Bool, detail: Bool = false) async throws {
        guard let target = detail ? catalog.detailWindow?.window : window else { throw LibraryError("Missing catalog window") }
        target.makeKeyAndOrderFront(nil);target.appearance = NSAppearance(named:dark ? .darkAqua : .aqua)
        target.contentView?.layoutSubtreeIfNeeded();try await pause()
        try saveWindowCapture(target,to:output.appendingPathComponent(name))
    }
    func finish(_ failure: String?, live: Bool) {
        let message = failure.map { "FAIL: " + $0 } ?? "PASS: \(live ? "live Archive catalog, artwork, download, and offline Flash launch" : "native catalog content filter, details, download, ZIP, offline HTML play, custom artwork, duplicate, cancel, pagination, and error states")"
        if failure != nil { try? saveWindowCapture(window,to:output.appendingPathComponent("Failure.png")) }
        try? message.write(to:output.appendingPathComponent("Result.txt"),atomically:true,encoding:.utf8)
        print(message);exit(failure == nil ? 0 : 1)
    }
}
