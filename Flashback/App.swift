// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import SwiftUI
import UniformTypeIdentifiers
import WebKit

enum Palette {
    static let action = Color(red:0.48,green:0.36,blue:0.88)
    static let accent = Color(nsColor:NSColor(name:nil) { appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
            ? NSColor(srgbRed:0.69,green:0.59,blue:1,alpha:1)
            : NSColor(srgbRed:0.48,green:0.36,blue:0.88,alpha:1)
    })
    static let background = Color(nsColor:.windowBackgroundColor)
    static let card = Color(nsColor:.controlBackgroundColor)
    static let separator = Color(nsColor:.separatorColor)
}

enum LibraryFilter: String, CaseIterable {
    case all = "Installed Games", favorites = "Favorites", recent = "Recently Played"
    var icon: String { switch self { case .all: return "square.grid.2x2"; case .favorites: return "heart"; case .recent: return "clock" } }
}

struct Message: Identifiable { let id = UUID(); let title: String; let body: String }

@MainActor final class LibraryModel: ObservableObject {
    let library: GameLibrary
    @Published var games: [Game] = []
    @Published var query = ""
    @Published var filter = LibraryFilter.all
    @Published var showingDiscover = false
    lazy var archive = ArchiveModel(libraryModel:self)
    @Published var isImporting = false
    @Published var status = ""
    @Published var alert: Message?
    @Published var coverRevision = 0
    var canWrite = true
    /// Installed only when this build includes the experimental runtime.
    /// Keeping the route here lets Add Games enter the guided setup without
    /// making Classic Windows appear in ordinary shipping builds.
    var classicWindowsRequest: ((Game) -> Void)?
    var auditsLayout = false
    var layoutFrames: [String:CGRect] = [:]
    var windows: [String:GameWindow] = [:]
    var websiteWindow: WebsiteImportWindow?
    var helpWindow: HelpWindow?
    @Published var javaSessions: [String:JavaSession] = [:]
    @Published var nativeSessions: [String:NativeSession] = [:]
    var dosSettingsWindows: [String:DOSSettingsWindow] = [:]
    @Published var dosMaintenance: Set<String> = []
    private var dosRestartRequests: Set<String> = []
    var playerDataStore = WKWebsiteDataStore.default()
    private var pending: [(URL, Bool)] = []
    private var dialogWindow: NSWindow? {
        NSApp.mainWindow ?? NSApp.keyWindow ?? (NSApp.delegate as? AppDelegate)?.window
    }

    init(root: URL) {
        library = GameLibrary(root:root)
        do { games = try library.load() }
        catch {
            canWrite = false
            alert = Message(title:"Your library needs attention", body:"Flashback couldn’t read its saved library. Your game files are still in place.\n\n\(error.localizedDescription)")
        }
    }

    var visibleGames: [Game] {
        games.filter {
            (filter != .favorites || $0.favorite) && (filter != .recent || $0.lastPlayed != nil)
                && (query.isEmpty || $0.title.localizedStandardContains(query))
        }.sorted {
            let a = $0.lastPlayed ?? $0.added, b = $1.lastPlayed ?? $1.added
            return a == b ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : a > b
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Add games"
        panel.message = classicWindowsRequest == nil
            ? "Choose a Flash, Java, HTML, DOS, or Director game. Add its ZIP or entire folder to include graphics and sounds."
            : "Choose a Flash, Java, HTML, DOS, Director, or Classic Windows game. For Windows, choose its ISO or complete folder."
        panel.prompt = "Add to Library"
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        var types = [UTType(filenameExtension:"swf") ?? .data, UTType(filenameExtension:"jar") ?? .data, UTType(filenameExtension:"dcr") ?? .data, UTType(filenameExtension:"dir") ?? .data, UTType(filenameExtension:"dxr") ?? .data, .html, .zip, .folder] + ["jnlp","exe","com","bat","scummvm"].map { UTType(filenameExtension:$0) ?? .data }
        if classicWindowsRequest != nil { types.append(UTType(filenameExtension:"iso") ?? .data) }
        panel.allowedContentTypes = types
        if auditsLayout { panel.directoryURL = library.root }
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            if result == .OK { self?.add(panel.urls) }
        }
        if let window = dialogWindow {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for:window,completionHandler:completion)
        }
        else { panel.begin(completionHandler:completion) }
    }

    func chooseWebsite() {
        guard canWrite else { return }
        if websiteWindow == nil {
            websiteWindow = WebsiteImportWindow(libraryModel:self)
            websiteWindow?.onClose = { [weak self] in self?.websiteWindow = nil }
        }
        websiteWindow?.showWindow(nil); websiteWindow?.window?.makeKeyAndOrderFront(nil)
    }

    func websiteDetails(_ game: Game) {
        guard let record = library.webRecord(game) else { return }
        if websiteWindow != nil { websiteWindow?.close() }
        guard websiteWindow == nil else { return }
        let window = WebsiteImportWindow(libraryModel:self)
        window.model.title = game.title; window.model.added = game; window.model.phase = .done
        window.model.recovery = WebRecovery(source:library.folder(for:game),entry:game.entry,record:record)
        window.onClose = { [weak self] in self?.websiteWindow = nil }
        websiteWindow = window; window.showWindow(nil); window.window?.makeKeyAndOrderFront(nil)
    }

    func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard canWrite else { return false }
        Task {
            let urls = await Self.droppedURLs(providers)
            if urls.isEmpty { alert = Message(title:"Couldn’t read this drop", body:"Try choosing the game with Add Games instead.") }
            else { add(urls) }
        }
        return true
    }

    /// Drop an image straight onto a game's card to use it as that game's
    /// artwork. Only a provider that carries an image is claimed here, so
    /// dragging a game file onto a card still falls through to the window's
    /// import drop above.
    func receiveArtworkDrop(_ providers: [NSItemProvider], for game: Game) -> Bool {
        guard canWrite, let provider = providers.first(where:{
            $0.registeredTypeIdentifiers.contains { UTType($0)?.conforms(to:.image) == true }
        }) else { return false }
        Task {
            if let url = await Self.droppedURLs([provider]).first, url.isFileURL {
                await changeArtwork(url,for:game)
            } else if let url = await Self.materializedImage(provider) {
                defer { try? FileManager.default.removeItem(at:url) }
                await changeArtwork(url,for:game)
            } else {
                alert = Message(title:"Couldn’t read this image",
                                body:"Try Change Artwork… and choose the image from your Mac.")
            }
        }
        return true
    }

    /// An image dragged from a browser or Photos arrives as data rather than a
    /// file, so write it out before the decoder in `setArtwork` reads it. The
    /// same 50 MB ceiling applies here, before anything touches the disk.
    static func materializedImage(_ provider: NSItemProvider) async -> URL? {
        guard let identifier = provider.registeredTypeIdentifiers.first(where:{
            UTType($0)?.conforms(to:.image) == true
        }) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier:identifier) { data, _ in
                guard let data, !data.isEmpty, data.count <= 50 * 1024 * 1024 else {
                    return continuation.resume(returning:nil)
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("flashback-artwork-\(UUID().uuidString)")
                do { try data.write(to:url,options:.atomic); continuation.resume(returning:url) }
                catch { continuation.resume(returning:nil) }
            }
        }
    }

    static func droppedURLs(_ providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let url: URL? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier, options:nil) { item, _ in
                    if let data = item as? Data { continuation.resume(returning:URL(dataRepresentation:data, relativeTo:nil)) }
                    else { continuation.resume(returning:item as? URL) }
                }
            }
            if let url { urls.append(url) }
        }
        return urls
    }

    func add(_ urls: [URL]) {
        guard canWrite else { return }
        pending += urls.map { ($0, urls.count == 1) }
        guard !isImporting else { return }
        isImporting = true
        Task {
            var failures: [String] = []
            while !pending.isEmpty {
                let (url, autoPlay) = pending.removeFirst()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                status = "Adding \(url.lastPathComponent)…"
                if let request = ClassicWindowsImport.directRequest(url), let route = classicWindowsRequest {
                    do { route(try await addClassicWindows(request)) }
                    catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                    continue
                }
                do {
                    let storage = library
                    guard let resources = Bundle.main.resourceURL else { throw LibraryError("The player is missing. Reinstall Flashback.") }
                    let plan = try await Task.detached(priority:.userInitiated) { try storage.prepare(url, resources:resources) }.value
                    defer { if let temp = plan.temporaryDirectory { try? FileManager.default.removeItem(at:temp) } }
                    guard let entry = await selectEntry(plan) else { status = ""; continue }
                    let imported = try await Task.detached(priority:.userInitiated) { try storage.importGame(plan, entry:entry) }.value
                    let game: Game
                    if let existing = games.first(where:{ $0.id == imported.id }) {
                        game = existing; status = "\(existing.title) is already in your library."
                    } else {
                        try commit(games + [imported])
                        game = imported; status = "\(imported.title) added."
                    }
                    query = ""; filter = .all; showingDiscover = false
                    if autoPlay && pending.isEmpty { play(game) }
                } catch {
                    if let request = ClassicWindowsImport.requestAfterStandardImportFailed(url),
                       let route = classicWindowsRequest {
                        do { route(try await addClassicWindows(request)) }
                        catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                    } else {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
            isImporting = false
            if !failures.isEmpty {
                alert = Message(title:"Some games couldn’t be added", body:failures.joined(separator:"\n\n"))
                status = ""
            } else if !status.isEmpty {
                let completedStatus = status
                try? await Task.sleep(nanoseconds:2_000_000_000)
                if !isImporting && status == completedStatus { status = "" }
            }
        }
    }

    private func addClassicWindows(_ request: ClassicWindowsImportRequest) async throws -> Game {
        status = "Adding \(request.displayName)…"
        let storage = library
        let imported = try await Task.detached(priority:.userInitiated) { try storage.importClassicWindows(request) }.value
        let game: Game
        if let existing = games.first(where:{ $0.id == imported.id }) {
            game = existing
            status = "\(existing.title) is already in your library."
        } else {
            try commit(games + [imported])
            game = imported
            status = "\(imported.title) added."
        }
        query = ""; filter = .all; showingDiscover = false
        return game
    }

    func addRecoveredGame(_ recovery: WebRecovery, title: String) async throws -> (game: Game, alreadyPresent: Bool)? {
        guard let resources = Bundle.main.resourceURL else { throw LibraryError("The player resources are missing.") }
        let storage = library
        var plan = try await Task.detached(priority:.userInitiated) { try storage.prepare(recovery.source,resources:resources) }.value
        defer { if let temp = plan.temporaryDirectory { try? FileManager.default.removeItem(at:temp) } }
        plan.suggestedTitle = title
        let choice: String?
        if let entry = recovery.entry, plan.movies.contains(entry) { choice = entry } else { choice = await selectEntry(plan) }
        guard let entry = choice else { return nil }
        let importPlan = plan
        let imported = try await Task.detached(priority:.userInitiated) {
            if ["jar","jnlp"].contains((entry as NSString).pathExtension.lowercased()) {
                let base = importPlan.isFolder ? importPlan.source : importPlan.source.deletingLastPathComponent()
                try WebsiteImportModel.inspectJava(GameLibrary.contained(entry,in:base),resources:resources)
            }
            return try storage.importGame(importPlan,entry:entry)
        }.value
        var record = recovery.record; record.title = title
        let existing = games.first(where:{ $0.id == imported.id })
        // Preserve the original resource routing when a byte-identical game already exists.
        if existing == nil || storage.webRecord(imported) == nil { try storage.saveWebRecord(record,for:imported) }
        if existing == nil { try commit(games + [imported]) }
        let game = existing ?? imported
        query = ""; filter = .all
        status = existing == nil ? "\(game.title) added." : "\(game.title) is already in your library."
        return (game,existing != nil)
    }

    func resumePendingImports() { if !pending.isEmpty && !isImporting { add([]) } }

    func selectEntry(_ plan: ImportPlan) async -> String? {
        if plan.movies.count == 1 { return plan.movies.first }
        let choices = plan.movies.sorted {
            func rank(_ path: String) -> Int {
                ["projector-loader.dcr", "game.swf", "main.swf", "index.swf", "start.swf", "game.dcr", "main.dcr", "game.dir", "main.dir", "game.dxr", "index.html", "index.htm", "game.html", "play.html"].firstIndex(of:URL(fileURLWithPath:path).lastPathComponent.lowercased()) ?? 14
            }
            return rank($0) == rank($1) ? $0 < $1 : rank($0) < rank($1)
        }
        let panel = NSAlert()
        panel.messageText = "Which file starts the game?"
        panel.informativeText = "“\(plan.source.lastPathComponent)” contains several game files. Choose the main game; all of the folder’s supporting files will be kept."
        panel.addButton(withTitle:"Add Game"); panel.addButton(withTitle:"Cancel")
        let picker = NSPopUpButton(frame:NSRect(x:0,y:0,width:400,height:28))
        picker.addItems(withTitles:choices); picker.setAccessibilityLabel("Main game file")
        panel.accessoryView = picker
        let response = await confirm(panel)
        return response == .alertFirstButtonReturn ? choices[picker.indexOfSelectedItem] : nil
    }

    private func confirm(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        if let window = dialogWindow {
            window.makeKeyAndOrderFront(nil)
            return await withCheckedContinuation { continuation in alert.beginSheetModal(for:window) { continuation.resume(returning:$0) } }
        }
        return alert.runModal()
    }

    func commit(_ next: [Game]) throws { try library.save(next); games = next }

    func showDOSSettings(_ game: Game) {
        if let existing = dosSettingsWindows[game.id] { existing.showWindow(nil); existing.window?.makeKeyAndOrderFront(nil); return }
        let controller = DOSSettingsWindow(game:game,model:self)
        controller.onClose = { [weak self] in self?.dosSettingsWindows[game.id] = nil }
        dosSettingsWindows[game.id] = controller
        controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
    }

    func restartDOS(_ game: Game) {
        guard game.isDOS, !dosMaintenance.contains(game.id), !dosRestartRequests.contains(game.id) else { return }
        guard let session = nativeSessions[game.id] else { play(game); return }
        dosRestartRequests.insert(game.id)
        let dialog = NSAlert()
        dialog.messageText = "Restart “\(game.title)”?"
        dialog.informativeText = "Progress you have not saved in the game will be lost. Saved game files will be kept."
        dialog.addButton(withTitle:"Cancel")
        dialog.addButton(withTitle:"Restart Game")
        Task { [self] in
            defer { dosRestartRequests.remove(game.id) }
            guard await confirm(dialog) == .alertSecondButtonReturn,
                  nativeSessions[game.id] === session,
                  games.contains(where: { $0.id == game.id }) else { return }
            let previous = session.onExit
            session.onExit = { [weak self] error in
                previous?(error)
                guard let self, self.games.contains(where: { $0.id == game.id }) else { return }
                self.play(game)
            }
            session.stop()
        }
    }

    func play(_ game: Game, dosMode: DOSLaunchMode = .game) {
        guard !dosMaintenance.contains(game.id) else { show(LibraryError("Please wait for this game’s data operation to finish.")); return }
        if game.isClassicWindows {
            guard let route = classicWindowsRequest else {
                show(LibraryError("Classic Windows support is not included in this build.")); return
            }
            route(game)
            return
        }
        if let window = windows[game.id] { window.showWindow(nil); window.window?.makeKeyAndOrderFront(nil); return }
        if let session = javaSessions[game.id] { session.activate(); return }
        if let session = nativeSessions[game.id] { session.activate(); return }
        do {
            try GameLibrary.validateGame(library.movie(for:game))
            guard let resources = Bundle.main.resourceURL else { throw LibraryError("The player is missing from this app. Reinstall Flashback.") }
            if game.isNative {
                let session = NativeSession(game:game)
                session.onReady = { [weak self] in self?.markPlayed(game) }
                session.onExit = { [weak self] error in
                    self?.nativeSessions[game.id] = nil
                    if let error { self?.show(LibraryError(error)) }
                }
                nativeSessions[game.id] = session
                Task {
                    do { try await session.start(library:library,resources:resources,dosMode:dosMode) }
                    catch { nativeSessions[game.id] = nil; show(error) }
                }
                return
            }
            if game.isJava {
                let session = JavaSession(game:game)
                session.onReady = { [weak self] in self?.markPlayed(game) }
                session.onExit = { [weak self] error in
                    self?.javaSessions[game.id] = nil
                    if let error { self?.show(LibraryError(error)) }
                }
                javaSessions[game.id] = session
                Task {
                    do { try await session.start(library:library, resources:resources) }
                    catch { javaSessions[game.id] = nil; show(error) }
                }
                return
            }
            let session = PlayerSession(game:game, library:library, resources:resources, dataStore:playerDataStore)
            let window = GameWindow(session:session)
            window.onClose = { [weak self] in self?.windows[game.id] = nil }
            session.onCover = { [weak self] in self?.coverRevision += 1 }
            session.onReady = { [weak self] in self?.markPlayed(game) }
            session.onVolumeChange = { [weak self] volume in self?.setVolume(volume,for:game) }
            windows[game.id] = window
            window.showWindow(nil); window.window?.makeKeyAndOrderFront(nil)
            session.start()
        } catch { show(error) }
    }

    private func markPlayed(_ game: Game) {
        guard let index = games.firstIndex(where:{ $0.id == game.id }) else { return }
        var next = games; next[index].lastPlayed = Date()
        do { try commit(next) } catch { show(error) }
    }

    func setVolume(_ volume: Double, for game: Game) {
        guard let index = games.firstIndex(where:{ $0.id == game.id }) else { return }
        var next = games
        next[index].volume = min(max(volume,0),1)
        do { try commit(next) } catch { show(error) }
    }

    func chooseVolume(_ game: Game) {
        guard canWrite else { return }
        let panel = NSAlert()
        panel.messageText = "Volume for “\(game.title)”"
        panel.informativeText = game.isNative && nativeSessions[game.id] != nil
            ? "The new volume applies the next time you open this game."
            : "Flashback remembers this setting for this game."
        panel.addButton(withTitle:"Save Volume")
        panel.addButton(withTitle:"Cancel")
        let row = NSStackView(frame:NSRect(x:0,y:0,width:330,height:32))
        row.orientation = .horizontal; row.spacing = 10
        let quiet = NSImageView(image:NSImage(systemSymbolName:"speaker.fill",accessibilityDescription:"Quiet")!)
        let slider = NSSlider(value:game.playbackVolume,minValue:0,maxValue:1,target:nil,action:nil)
        slider.setAccessibilityLabel("Game volume")
        let loud = NSImageView(image:NSImage(systemSymbolName:"speaker.wave.3.fill",accessibilityDescription:"Loud")!)
        row.addArrangedSubview(quiet); row.addArrangedSubview(slider); row.addArrangedSubview(loud)
        slider.widthAnchor.constraint(equalToConstant:250).isActive = true
        panel.accessoryView = row
        Task {
            if await confirm(panel) == .alertFirstButtonReturn { setVolume(slider.doubleValue,for:game) }
        }
    }

    func favorite(_ game: Game) {
        guard canWrite, let index = games.firstIndex(where:{ $0.id == game.id }) else { return }
        var next = games; next[index].favorite.toggle()
        do { try commit(next) } catch { show(error) }
    }
    func chooseArtwork(_ game: Game) {
        guard canWrite else { return }
        let panel = NSOpenPanel()
        panel.title = "Change Artwork"
        panel.message = "Choose an image for this game’s library card."
        panel.prompt = "Use Artwork"
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if auditsLayout { panel.directoryURL = library.root }
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard result == .OK, let url = panel.url, let self else { return }
            Task { await self.changeArtwork(url,for:game) }
        }
        if let window = dialogWindow {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for:window,completionHandler:completion)
        }
        else { panel.begin(completionHandler:completion) }
    }

    func changeArtwork(_ url: URL, for game: Game) async {
        guard canWrite, games.contains(where:{ $0.id == game.id }) else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let storage = library
            try await Task.detached(priority:.userInitiated) { try storage.setArtwork(url,for:game) }.value
            coverRevision += 1
            status = "Artwork updated for \(game.title)."
        } catch { show(error) }
    }

    func restoreArtwork(_ game: Game) {
        guard canWrite else { return }
        do {
            try library.restoreArtwork(game)
            coverRevision += 1
            windows[game.id]?.session.captureCover()
            status = "Default artwork restored for \(game.title)."
        } catch { show(error) }
    }

    func rename(_ game: Game) {
        let dialog = NSAlert()
        dialog.messageText = "Rename game"
        dialog.addButton(withTitle:"Save"); dialog.addButton(withTitle:"Cancel")
        let field = NSTextField(string:game.title)
        field.frame = NSRect(x:0,y:0,width:320,height:26)
        field.setAccessibilityLabel("Game name")
        dialog.accessoryView = field
        dialog.window.initialFirstResponder = field
        Task {
            guard await confirm(dialog) == .alertFirstButtonReturn, canWrite else { return }
            let title = String(field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).prefix(120))
            guard !title.isEmpty, let index = games.firstIndex(where:{ $0.id == game.id }) else { return }
            var next = games; next[index].title = title
            do {
                try commit(next)
                windows[game.id]?.window?.title = title
                windows[game.id]?.session.game.title = title
            } catch { show(error) }
        }
    }

    func remove(_ game: Game) {
        guard canWrite, !isImporting, !dosMaintenance.contains(game.id) else { return }
        let dialog = NSAlert()
        dialog.messageText = "Remove “\(game.title)”?"
        dialog.informativeText = "Flashback’s copy will move to the Trash. Your original files and saved game data will be kept."
        dialog.addButton(withTitle:"Remove"); dialog.addButton(withTitle:"Cancel")
        Task {
            guard await confirm(dialog) == .alertFirstButtonReturn, canWrite else { return }
            guard !isImporting, !dosMaintenance.contains(game.id) else { show(LibraryError("Wait for the current import or game data operation to finish, then remove the game.")); return }
            let original = games
            do {
                javaSessions[game.id]?.stop()
                nativeSessions[game.id]?.stop()
                try library.save(games.filter { $0.id != game.id })
                do {
                    if FileManager.default.fileExists(atPath:library.folder(for:game).path) {
                        try FileManager.default.trashItem(at:library.folder(for:game), resultingItemURL:nil)
                    }
                } catch { try library.save(original); throw error }
                dosSettingsWindows[game.id]?.close()
                windows[game.id]?.close()
                games.removeAll { $0.id == game.id }
            } catch { show(error) }
        }
    }

    func show(_ error: Error) { alert = Message(title:"Couldn’t Complete the Action", body:error.localizedDescription) }
    func help() {
        if helpWindow == nil {
            helpWindow = HelpWindow()
            helpWindow?.onClose = { [weak self] in self?.helpWindow = nil }
        }
        helpWindow?.showWindow(nil); helpWindow?.window?.makeKeyAndOrderFront(nil)
    }

}

struct LibraryView: View {
    @ObservedObject var model: LibraryModel
    @State private var dragging = false
    @FocusState private var searchFocused: Bool
    var body: some View {
        HStack(spacing:0) {
            sidebar
            Divider()
            if model.showingDiscover { ArchiveView(model:model.archive,libraryModel:model) }
            else { VStack(alignment:.leading, spacing:0) {
                header
                if model.games.isEmpty { emptyLibrary }
                else if model.visibleGames.isEmpty { noResults }
                else { gameGrid }
                footer
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Palette.background) }
        }
        .frame(minWidth:800,minHeight:560)
        .tint(Palette.accent)
        .overlay {
            if dragging {
                RoundedRectangle(cornerRadius:18).fill(Palette.accent.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(Palette.accent, style:StrokeStyle(lineWidth:3,dash:[10,7])))
                    .padding(8).allowsHitTesting(false)
            }
        }
        .onDrop(of:[UTType.fileURL.identifier], isTargeted:$dragging, perform:model.receiveDrop)
        .onReceive(NotificationCenter.default.publisher(for:NSNotification.Name("FlashbackFindGame"))) { _ in if !model.showingDiscover { searchFocused = true } }
        .coordinateSpace(name:"library")
        .onPreferenceChange(LayoutFrames.self) { if model.auditsLayout { model.layoutFrames = $0 } }
        .alert(item:$model.alert) { message in Alert(title:Text(message.title), message:Text(message.body), dismissButton:.default(Text("OK"))) }
    }

    private var sidebar: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:9) {
                Image(nsImage:BrandArtwork.mark(size:25)).foregroundStyle(.primary).accessibilityHidden(true)
                Image(nsImage:BrandArtwork.wordmark()).foregroundStyle(.primary).accessibilityLabel("Flashback")
            }.padding(.horizontal,18).padding(.top,23).padding(.bottom,27)
            Button { model.showingDiscover = true } label: {
                Label("Discover",systemImage:"sparkle.magnifyingglass").font(.system(size:13,weight:.medium))
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,10).padding(.vertical,8)
                    .background(model.showingDiscover ? Palette.accent.opacity(0.16) : Color.clear,in:RoundedRectangle(cornerRadius:6)).contentShape(Rectangle())
            }.buttonStyle(.plain).auditFrame("discover",model:model).padding(.horizontal,10).padding(.bottom,22)
            Text("Library").font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary).padding(.horizontal,20).padding(.bottom,5)
            List(selection:Binding<LibraryFilter?>(get:{ model.showingDiscover ? nil : model.filter },set:{ if let value = $0 { model.filter = value; model.query = ""; model.showingDiscover = false } })) {
                ForEach(LibraryFilter.allCases,id:\.self) { item in
                    HStack(spacing:10) {
                        Image(systemName:item.icon).frame(width:18).accessibilityHidden(true)
                        Text(item.rawValue).lineLimit(1)
                        Spacer(minLength:0)
                        if item == .all { Text("\(model.games.count)").monospacedDigit().foregroundStyle(.secondary) }
                    }.font(.system(size:13)).padding(.vertical,3).tag(item)
                        .auditFrame("filter-\(item.rawValue)",model:model)
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
            VStack(spacing:9) {
                Button(action:model.chooseFiles) { Label("Add Games…",systemImage:"plus").frame(maxWidth:.infinity) }
                    .buttonStyle(.borderedProminent).tint(Palette.action).keyboardShortcut("o",modifiers:.command)
                Button(action:model.chooseWebsite) { Label("Add from Website…",systemImage:"globe").frame(maxWidth:.infinity) }
                    .buttonStyle(.bordered)
            }.controlSize(.large).disabled(!model.canWrite).padding(.horizontal,16)
            Button(action:model.help) { Label("Flashback Help",systemImage:"questionmark.circle").font(.system(size:11)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).padding(.vertical,20).frame(maxWidth:.infinity)
        }.frame(width:258).background(.bar)
    }
    private var header: some View {
        let count = model.visibleGames.count
        return HStack(alignment:.center,spacing:20) {
            VStack(alignment:.leading,spacing:3) {
                Text(model.filter.rawValue).font(.system(size:25,weight:.semibold))
                    .accessibilityIdentifier("library-heading").auditFrame("heading",model:model)
                Text("\(count) \(count == 1 ? "game" : "games")")
                    .font(.system(size:13)).foregroundStyle(.secondary).auditFrame("count",model:model)
            }
            Spacer(minLength:0)
            if !model.games.isEmpty {
                HStack(spacing:7) {
                    Image(systemName:"magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search games",text:$model.query).textFieldStyle(.plain).focused($searchFocused).accessibilityLabel("Search games").accessibilityIdentifier("library-search")
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("Clear search").auditFrame("clear-search",model:model)
                    }
                }.font(.system(size:13)).padding(.horizontal,11).frame(width:232,height:36)
                    .background(Palette.card,in:RoundedRectangle(cornerRadius:6))
                    .overlay(RoundedRectangle(cornerRadius:6).strokeBorder(searchFocused ? Palette.accent : Palette.separator.opacity(0.6),lineWidth:searchFocused ? 2 : 1))
                    .auditFrame("search",model:model)
            }
        }.padding(.horizontal,32).padding(.top,26).padding(.bottom,22)
    }
    private var emptyLibrary: some View {
        VStack(spacing:18) {
            Image(systemName:"gamecontroller").font(.system(size:38,weight:.light)).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(spacing:8) {
                Text("No Games Yet").font(.system(size:22,weight:.semibold))
                Text(model.classicWindowsRequest == nil
                     ? "Add Flash, Java, HTML5, Shockwave, DOS, or Director games.\nDrop a file, folder, or ZIP anywhere in this window."
                     : "Add Flash, Java, HTML5, Shockwave, DOS, Director, or Classic Windows games.\nDrop a file, folder, ZIP, or Windows game ISO anywhere in this window.")
                    .font(.system(size:13)).foregroundStyle(.secondary).lineSpacing(3).multilineTextAlignment(.center)
            }
            HStack(spacing:10) {
                Button("Add from Website…",action:model.chooseWebsite).buttonStyle(.bordered)
                Button("Add Games…",action:model.chooseFiles).buttonStyle(.borderedProminent).tint(Palette.action)
            }.controlSize(.large).disabled(!model.canWrite).padding(.top,4)
        }.padding(28).frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    private var noResults: some View {
        VStack(spacing:12) {
            Image(systemName:model.filter == .favorites ? "heart" : (model.filter == .recent && model.query.isEmpty ? "clock" : "magnifyingglass"))
                .font(.system(size:30,weight:.light)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(model.query.isEmpty ? (model.filter == .favorites ? "No Favorites Yet" : "No Recent Games") : "No Matching Games")
                .font(.system(size:19,weight:.semibold))
            Text(model.query.isEmpty ? (model.filter == .favorites ? "Click the heart on a game to save it here." : "Games appear here after you play them.") : "Try a different name or clear your search.")
                .font(.system(size:13)).foregroundStyle(.secondary)
            if !model.query.isEmpty { Button("Clear Search") { model.query = "" }.buttonStyle(.bordered) }
        }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    private var gameGrid: some View {
        ScrollView {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:220,maximum:320),spacing:24)],alignment:.leading,spacing:28) {
                ForEach(model.visibleGames) { game in GameCard(game:game,model:model) }
            }.auditFrame("grid", model:model).padding(.horizontal,32).padding(.bottom,28)
        }.auditFrame("viewport", model:model)
    }
    private var footer: some View {
        Group {
            if model.isImporting || !model.status.isEmpty {
                HStack(spacing:9) {
                    if model.isImporting { ProgressView().controlSize(.small) }
                    Image(systemName:"square.and.arrow.down").accessibilityHidden(true)
                    Text(model.status).lineLimit(1).auditFrame("status", model:model)
                }.font(.system(size:11)).foregroundStyle(.secondary)
                    .padding(.horizontal,14).frame(height:30)
                    .background(.regularMaterial,in:RoundedRectangle(cornerRadius:8))
                    .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Palette.separator.opacity(0.35),lineWidth:1))
                    .padding(.bottom,12)
                    .frame(maxWidth:.infinity,alignment:.center)
            }
        }
    }
}

struct GameCard: View {
    let game: Game
    @ObservedObject var model: LibraryModel
    @State private var hovering = false
    @State private var receivingArtwork = false
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            Button { model.play(game) } label: {
                // An overlay paints within the grid's width; artwork must never size the card.
                ZStack(alignment:.topTrailing) {
                    Color(nsColor:.underPageBackgroundColor)
                        .overlay {
                    if let cover = NSImage(contentsOf:model.library.artworkURL(game)) {
                        Image(nsImage:cover).resizable().scaledToFill().id(model.coverRevision)
                    } else {
                        ZStack(alignment:.topTrailing) {
                            VStack(spacing:12) {
                                Image(systemName:"gamecontroller").font(.system(size:35,weight:.light)).accessibilityHidden(true)
                            }.foregroundStyle(.white.opacity(0.72))
                                .frame(maxWidth:.infinity,maxHeight:.infinity)
                            Text(game.format).font(.system(size:10,weight:.medium)).tracking(0.4)
                                .foregroundStyle(.white.opacity(0.72))
                                .padding(.horizontal,10).padding(.vertical,6)
                                .background(.black.opacity(0.25),in:RoundedRectangle(cornerRadius:7))
                                .padding(10)
                        }
                            .background(LinearGradient(colors:[Color(white:0.13),Color(white:0.09)],startPoint:.topLeading,endPoint:.bottomTrailing))
                    }
                    }
                    if hovering {
                        ZStack {
                            Color.black.opacity(0.2)
                            Image(systemName:game.isClassicWindows ? "gearshape.fill" : "play.fill").font(.system(size:19)).foregroundStyle(.white).frame(width:46,height:46).background(.black.opacity(0.55),in:Circle())
                        }
                    }
                }.aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:10)).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(game.isClassicWindows ? "Set up \(game.title)" : "Play \(game.title)").accessibilityIdentifier("play-\(game.id)").onHover { hovering = $0 }.auditFrame("play-\(game.id)", model:model)
            HStack(alignment:.center,spacing:8) {
                VStack(alignment:.leading,spacing:5) {
                    Text(game.title).font(.system(size:15,weight:.semibold)).lineLimit(1).help(game.title)
                    Text(game.isClassicWindows ? "Windows 98 · Setup required" : ((model.javaSessions[game.id] != nil || model.nativeSessions[game.id] != nil) ? "Playing" : (game.lastPlayed == nil ? game.format : "Played \(game.lastPlayed!.formatted(.relative(presentation:.named)))")))
                        .font(.system(size:12)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth:.infinity,alignment:.leading).auditFrame("caption-\(game.id)", model:model)
                Button { model.favorite(game) } label: {
                    Image(systemName:game.favorite ? "heart.fill" : "heart").foregroundStyle(game.favorite ? Palette.accent : Color.secondary)
                        .frame(width:28,height:28).contentShape(Rectangle())
                }
                    .buttonStyle(.plain).accessibilityLabel(game.favorite ? "Remove \(game.title) from favorites" : "Favorite \(game.title)")
                    .accessibilityIdentifier("favorite-\(game.id)")
                    .help(game.favorite ? "Remove from favorites" : "Add to favorites").disabled(!model.canWrite)
                    .auditFrame("favorite-\(game.id)", model:model)
            }.padding(.top,10).padding(.horizontal,2).padding(.bottom,2)
        }
        .overlay {
            if receivingArtwork {
                RoundedRectangle(cornerRadius:8).fill(Palette.accent.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius:8)
                        .strokeBorder(Palette.accent, style:StrokeStyle(lineWidth:2,dash:[6,4])))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of:[UTType.image.identifier], isTargeted:$receivingArtwork) { providers in
            model.receiveArtworkDrop(providers, for:game)
        }
        .help(model.canWrite ? "Drop an image here to use it as this game’s artwork" : game.title)
        .auditFrame("card-\(game.id)", model:model)
        .contextMenu {
            Button("Play") { model.play(game) }
            if game.isDOS {
                Button("DOS Settings…") { model.showDOSSettings(game) }
                if model.nativeSessions[game.id] != nil { Button("Restart Game…") { model.restartDOS(game) } }
            }
            if game.isFlash || game.isNative { Button("Game Volume…") { model.chooseVolume(game) }.disabled(!model.canWrite) }
            if model.javaSessions[game.id] != nil || model.nativeSessions[game.id] != nil { Button("Quit Game") { model.javaSessions[game.id]?.stop(); model.nativeSessions[game.id]?.stop() } }
            Button(game.favorite ? "Remove from Favorites" : "Add to Favorites") { model.favorite(game) }.disabled(!model.canWrite)
            Button("Rename…") { model.rename(game) }.disabled(!model.canWrite)
            Button("Change Artwork…") { model.chooseArtwork(game) }.disabled(!model.canWrite)
            if FileManager.default.fileExists(atPath:model.library.customArtworkURL(game).path) {
                Button("Restore Default Artwork") { model.restoreArtwork(game) }.disabled(!model.canWrite)
            }
            if let record = model.library.webRecord(game) {
                Button("Website Details…") { model.websiteDetails(game) }
                Button("Open Source Page") { NSWorkspace.shared.open(record.page) }
            }
            Button("Show Game Files") { NSWorkspace.shared.activateFileViewerSelecting([model.library.folder(for:game)]) }
            Divider()
            Button("Remove from Library…") { model.remove(game) }.disabled(!model.canWrite || model.isImporting)
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: LibraryModel!
    var window: NSWindow!
    var launchURLs: [URL] = []
    var smokeCheck: SmokeCheck?
    var layoutCheck: LayoutCheck?
    var websiteCheck: WebsiteUICheck?
    var archiveCheck: ArchiveUICheck?
    var welcomeWindow: WelcomeWindow?
    var classicWindowsSetupWindow: ClassicWindowsSetupWindow?
    var storageSettingsWindow: StorageSettingsWindow?
    var preferences = UserDefaults.standard
    var storageLocation = StorageLocation()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let isCheck = args.count == 5 && ["--self-check","--shockwave-probe"].contains(args[1])
        let isLayoutCheck = args.count == 3 && ["--layout-check","--surfaces-check"].contains(args[1])
        let isWebsiteCheck = args.count == 4 && args[1] == "--website-check"
        let isArchiveCheck = args.count == 4 && args[1] == "--catalog-check"
        let isWelcomeCheck = args.count == 3 && args[1] == "--welcome-check"
        let isInstallationCheck = args.count == 3 && args[1] == "--installation-check"
        let isDOSPreview = args.count == 3 && args[1] == "--dos-settings-preview"
        let isAudit = isDOSPreview || isCheck || isLayoutCheck || isWebsiteCheck || isArchiveCheck || isWelcomeCheck || isInstallationCheck
        let root: URL
        if isAudit { root = URL(fileURLWithPath:args[isCheck ? 4 : (isWebsiteCheck || isArchiveCheck ? 3 : 2)]).appendingPathComponent("Library") }
        else {
            if preferences.data(forKey: StorageLocation.bookmarkKey) != nil,
               storageLocation.selectedRootPreflight() == nil {
                while true {
                    let alert = NSAlert(); alert.messageText = "Flashback storage is unavailable"
                    alert.informativeText = "The selected storage location cannot be opened. Reconnect that volume and choose Retry, choose another existing library, or explicitly use the default location."
                    alert.addButton(withTitle:"Retry"); alert.addButton(withTitle:"Choose Another…"); alert.addButton(withTitle:"Use Default")
                    switch alert.runModal() {
                    case .alertFirstButtonReturn:
                        if storageLocation.selectedRootPreflight() != nil { break }
                    case .alertSecondButtonReturn:
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = "Use Existing Library"
                        if panel.runModal() == .OK, let url = panel.url, (try? storageLocation.useExisting(url)) != nil { break }
                    default:
                        preferences.removeObject(forKey:StorageLocation.bookmarkKey); preferences.removeObject(forKey:StorageLocation.pathKey); break
                    }
                    if storageLocation.selectedRootPreflight() != nil || preferences.data(forKey:StorageLocation.bookmarkKey) == nil { break }
                }
            }
            if preferences.data(forKey: StorageLocation.bookmarkKey) == nil,
               !preferences.bool(forKey: StorageLocation.promptCompletedKey) {
                let panel = NSOpenPanel(); panel.title = "Choose Flashback Storage"
                panel.message = "Choose a folder for imported games, covers, and Java, DOS, and ScummVM saves, or Cancel to use Application Support. App preferences and Flash/HTML browser storage remain in macOS-managed app data."
                panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
                panel.prompt = "Use This Folder"
                if panel.runModal() == .OK, let url = panel.url {
                    let legacy = storageLocation.defaultRoot
                    do { _ = try storageLocation.select(url.appendingPathComponent("Flashback", isDirectory:true), movingFrom: FileManager.default.fileExists(atPath:legacy.path) ? legacy : nil) }
                    catch { NSAlert(error:error).runModal() }
                }
                preferences.set(true, forKey: StorageLocation.promptCompletedKey)
            }
            root = storageLocation.resolvedRoot()
        }
        model = LibraryModel(root:root)
        if let resources = Bundle.main.resourceURL,
           FileManager.default.isExecutableFile(atPath:resources.appendingPathComponent("ClassicWindows/dosbox-x.app/Contents/MacOS/dosbox-x").path) {
            model.classicWindowsRequest = { [weak self] game in self?.showClassicWindowsSetup(for:game) }
        }
        model.auditsLayout = isLayoutCheck || isArchiveCheck
        if isArchiveCheck, let base = URL(string:args[2]) { model.archive = ArchiveModel(libraryModel:model,service:ArchiveService(base:base,allowLocal:["localhost","127.0.0.1"].contains(base.host ?? ""))) }
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle:"About Flashback",action:#selector(about),keyEquivalent:"")
        appMenu.addItem(withTitle:"Licenses and Source…",action:#selector(licenses),keyEquivalent:"")
        appMenu.addItem(withTitle:"Settings…",action:#selector(showStorageSettings),keyEquivalent:",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"Hide Flashback",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
        let hideOthers = appMenu.addItem(withTitle:"Hide Others",action:#selector(NSApplication.hideOtherApplications(_:)),keyEquivalent:"h")
        hideOthers.keyEquivalentModifierMask = [.command,.option]
        appMenu.addItem(withTitle:"Show All",action:#selector(NSApplication.unhideAllApplications(_:)),keyEquivalent:"")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"Quit Flashback",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let fileMenu = NSMenu(title:"File")
        fileMenu.addItem(withTitle:"Add Games…",action:#selector(addGames),keyEquivalent:"o")
        let websiteItem = fileMenu.addItem(withTitle:"Add from Website…",action:#selector(addWebsite),keyEquivalent:"O")
        websiteItem.keyEquivalentModifierMask = [.command,.shift]
        if let resources = Bundle.main.resourceURL,
           FileManager.default.isExecutableFile(atPath:resources.appendingPathComponent("ClassicWindows/dosbox-x.app/Contents/MacOS/dosbox-x").path) {
            fileMenu.addItem(withTitle:"Set Up Classic Windows…",action:#selector(setupClassicWindows),keyEquivalent:"")
        }
        fileMenu.addItem(withTitle:"Show Library",action:#selector(showLibrary),keyEquivalent:"l")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle:"Close Window",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        let fileItem = NSMenuItem(); fileItem.submenu = fileMenu; menu.addItem(fileItem)
        let editMenu = NSMenu(title:"Edit")
        for (title,action,key) in [("Undo",Selector(("undo:")),"z"),("Redo",Selector(("redo:")),"Z"),("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] {
            if title == "Cut" || title == "Select All" { editMenu.addItem(.separator()) }
            let item = editMenu.addItem(withTitle:title,action:action,keyEquivalent:key)
            if title == "Redo" { item.keyEquivalentModifierMask = [.command,.shift] }
        }
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle:"Find Game…",action:#selector(findGame),keyEquivalent:"f")
        let editItem = NSMenuItem(); editItem.submenu = editMenu; menu.addItem(editItem)
        let windowMenu = NSMenu(title:"Window")
        windowMenu.addItem(withTitle:"Minimize",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        let fullScreen = windowMenu.addItem(withTitle:"Enter Full Screen",action:#selector(NSWindow.toggleFullScreen(_:)),keyEquivalent:"f")
        fullScreen.keyEquivalentModifierMask = [.control,.command]
        let windowItem = NSMenuItem(); windowItem.submenu = windowMenu; menu.addItem(windowItem)
        let helpMenu = NSMenu(title:"Help")
        helpMenu.addItem(withTitle:"Welcome to Flashback…",action:#selector(showWelcome),keyEquivalent:"")
        helpMenu.addItem(withTitle:"Flashback Help",action:#selector(showHelp),keyEquivalent:"?")
        let helpItem = NSMenuItem(); helpItem.submenu = helpMenu; menu.addItem(helpItem)
        NSApp.mainMenu = menu; NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1080,height:720),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "Flashback"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width:800,height:600)
        window.isReleasedWhenClosed = false
        if !isAudit { window.setFrameAutosaveName("FlashbackLibrary") }
        window.contentView = NSHostingView(rootView:LibraryView(model:model))
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        if isDOSPreview, let game = model.games.first(where: { $0.isDOS }) { model.showDOSSettings(game) }
        if isCheck {
            smokeCheck = SmokeCheck(model:model,output:URL(fileURLWithPath:args[4]))
            smokeCheck?.probesShockwave = args[1] == "--shockwave-probe"
            smokeCheck?.run(source:URL(fileURLWithPath:args[2]),entry:args[3])
        }
        if isLayoutCheck {
            layoutCheck = LayoutCheck(model:model, window:window, output:URL(fileURLWithPath:args[2]))
            layoutCheck?.run(secondaryOnly:args[1] == "--surfaces-check")
        }
        if isWebsiteCheck, let url = URL(string:args[2]) {
            websiteCheck = WebsiteUICheck(model:model,output:URL(fileURLWithPath:args[3]))
            websiteCheck?.run(url:url)
        }
        if isArchiveCheck, let base = URL(string:args[2]) {
            archiveCheck = ArchiveUICheck(model:model,window:window,output:URL(fileURLWithPath:args[3]))
            archiveCheck?.run(live:!["localhost","127.0.0.1"].contains(base.host ?? ""))
        }
        if isWelcomeCheck {
            layoutCheck = LayoutCheck(model:model,window:window,output:URL(fileURLWithPath:args[2]))
            layoutCheck?.checkWelcome(delegate:self)
        }
        if isInstallationCheck {
            smokeCheck = SmokeCheck(model:model,output:URL(fileURLWithPath:args[2]))
            smokeCheck?.runInstallation(delegate:self)
        }
        if !launchURLs.isEmpty { model.add(launchURLs); launchURLs = [] }
        else if !isAudit {
            showWelcomeIfNeeded()
        }
    }
    func showWelcomeIfNeeded() {
        if !preferences.bool(forKey:WelcomeWindow.completedKey) { showWelcome() }
    }
    @objc func showWelcome() {
        if welcomeWindow == nil {
            let controller = WelcomeWindow(start:{ [weak self] in self?.showLibrary() },website:{ [weak self] in self?.addWebsite() })
            controller.onClose = { [weak self] in
                self?.preferences.set(true,forKey:WelcomeWindow.completedKey)
                self?.welcomeWindow = nil
            }
            welcomeWindow = controller
        }
        welcomeWindow?.showWindow(nil); welcomeWindow?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func setupClassicWindows() {
        showClassicWindowsSetup(for:nil)
    }
    func showClassicWindowsSetup(for game: Game?) {
        if let existing = classicWindowsSetupWindow {
            if let game { existing.setPendingGame(game) }
            existing.showWindow(nil); existing.window?.makeKeyAndOrderFront(nil); return
        }
        guard let resources = Bundle.main.resourceURL else { return }
        let controller = ClassicWindowsSetupWindow(storageRoot:model.library.root,resources:resources,pendingGame:game)
        controller.onClose = { [weak self] in self?.classicWindowsSetupWindow = nil }
        classicWindowsSetupWindow = controller
        controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
    }

    @objc func chooseStorageLocation() {
        guard !model.isImporting, model.dosMaintenance.isEmpty, model.windows.isEmpty,
              model.javaSessions.isEmpty, model.nativeSessions.isEmpty else {
            model.alert = Message(title:"Storage is busy", body:"Finish imports, maintenance, or running games before moving Flashback storage.")
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Flashback Storage Location"
        panel.message = "Current location: \(model.library.root.path)\n\nChoose a new parent folder. Flashback copies and verifies your library before switching; the existing copy is retained."
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Move Library"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            self.model.canWrite = false; self.storageSettingsWindow?.progress("Copying and verifying library…")
            let destination = url.appendingPathComponent("Flashback", isDirectory:true), source = self.model.library.root, service = self.storageLocation
            DispatchQueue.global(qos:.userInitiated).async {
                do {
                    _ = try service.select(destination, movingFrom: source)
                    DispatchQueue.main.async { self.storageSettingsWindow?.readyToQuit() }
                } catch { DispatchQueue.main.async { self.model.canWrite = true; self.storageSettingsWindow?.progress("Couldn’t move storage: \(error.localizedDescription)") } }
            }
        }
    }

    @objc func showStorageSettings() {
        if storageSettingsWindow == nil {
            let controller = StorageSettingsWindow(path:model.library.root)
            controller.change = { [weak self] in self?.chooseStorageLocation() }
            controller.quit = { NSApp.terminate(nil) }
            storageSettingsWindow = controller
        }
        storageSettingsWindow?.showWindow(nil); storageSettingsWindow?.window?.makeKeyAndOrderFront(nil)
    }


    @objc func addGames() { welcomeWindow?.close(); model.chooseFiles() }
    @objc func addWebsite() { welcomeWindow?.close(); model.chooseWebsite() }
    @objc func showLibrary() { model.showingDiscover = false; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    @objc func findGame() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); NotificationCenter.default.post(name:NSNotification.Name("FlashbackFindGame"),object:nil) }
    @objc func showHelp() { model.help() }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options:[.credits:NSAttributedString(string:"Flash, Java, HTML5, Shockwave, DOS, and Director games for Mac.\n\nGPLv3 · Ruffle · OpenJDK · DirPlayer · DOSBox Staging · ScummVM\nLicenses and source are available in the Flashback menu.",attributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:NSColor.secondaryLabelColor])])
    }
    @objc func licenses() {
        if let url = Bundle.main.url(forResource:"Licenses",withExtension:"html") { NSWorkspace.shared.open(url) }
    }
    func application(_ sender: NSApplication, open urls: [URL]) {
        if let model { welcomeWindow?.close(); model.add(urls) } else { launchURLs += urls }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if welcomeWindow != nil { showWelcome() } else { showLibrary() }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let model, !model.dosMaintenance.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Game data is still being saved"
            alert.informativeText = "Wait for the disc import, backup, or restore to finish, then quit Flashback."
            alert.addButton(withTitle:"OK"); alert.runModal()
            return .terminateCancel
        }
        guard let model, !model.windows.isEmpty || !model.javaSessions.isEmpty || !model.nativeSessions.isEmpty else { return .terminateNow }
        let playing = model.windows.values.map(\.session).filter { $0.game.isFlash && !$0.paused && !$0.loading && $0.failure == nil }
        for session in playing { session.togglePause() }
        let alert = NSAlert()
        alert.messageText = "Quit Flashback?"
        alert.informativeText = "Quitting closes your games. Progress they haven’t saved will be lost, and paused sessions won’t be kept for next time."
        alert.addButton(withTitle:"Cancel")
        alert.addButton(withTitle:"Quit Flashback").hasDestructiveAction = true
        let response = alert.runModal()
        if response == .alertSecondButtonReturn { return .terminateNow }
        for session in playing where session.paused { session.togglePause() }
        return .terminateCancel
    }
    func applicationWillTerminate(_ notification: Notification) {
        for session in model.javaSessions.values { session.stop() }
        for session in model.nativeSessions.values { session.stop() }
    }
}

@main struct FlashbackApp {
    static func main() {
        if CommandLine.arguments.contains("--version") {
            let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"
            print("Flashback \(version) · Ruffle 0.6.0 · Java 8u504 · HTML5 · DirPlayer 68376fb (patched) · DOSBox Staging 0.83.0 · ScummVM 2026.3.0")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
