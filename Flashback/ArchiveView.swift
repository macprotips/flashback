// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import SwiftUI
import ImageIO

struct GameSourceLink: Identifiable {
    let title: String
    let format: String
    let source: String
    let terms: String
    let url: URL
    let tested: Bool
    var id: String { url.absoluteString }

    static let recommendations = [
        GameSourceLink(title:"Happyland Adventures",format:"DOS",source:"DOS Games Archive",terms:"Freeware",url:URL(string:"https://www.dosgamesarchive.com/download/happyland-adventures/")!,tested:true),
        GameSourceLink(title:"Commander Keen 1",format:"DOS",source:"DOSGames.com",terms:"Shareware episode",url:URL(string:"https://dosgames.com/game/commander-keen-1-invasion-of-the-vorticons/")!,tested:false),
        GameSourceLink(title:"Jazz Jackrabbit",format:"DOS",source:"DOSGames.com",terms:"Shareware episode",url:URL(string:"https://dosgames.com/game/jazz-jackrabbit")!,tested:false),
        GameSourceLink(title:"Tyrian 2000",format:"DOS",source:"GOG",terms:"Free, DRM-free",url:URL(string:"https://www.gog.com/en/game/tyrian_2000")!,tested:false),
        GameSourceLink(title:"Alex the Allegator",format:"DOS",source:"DOS Games Archive",terms:"Freeware + source",url:URL(string:"https://www.dosgamesarchive.com/download/alex-the-allegator")!,tested:false),
        GameSourceLink(title:"Major Stryker",format:"DOS",source:"DOS Games Archive",terms:"Full freeware",url:URL(string:"https://www.dosgamesarchive.com/download/major-stryker/")!,tested:false),
        GameSourceLink(title:"Stargunner",format:"DOS",source:"DOS Games Archive",terms:"Full freeware",url:URL(string:"https://www.dosgamesarchive.com/download/stargunner")!,tested:false),
        GameSourceLink(title:"Prince of Persia",format:"DOS",source:"DOSGames.com",terms:"Playable demo",url:URL(string:"https://dosgames.com/game/prince-of-persia/")!,tested:false)
    ]
}

struct GameSourceProvider: Identifiable {
    let name: String
    let detail: String
    let symbol: String
    let url: URL?
    var id: String { name }

    static let all = [
        GameSourceProvider(name:"Internet Archive",detail:"Search inside Flashback",symbol:"building.columns",url:nil),
        GameSourceProvider(name:"DOS Games Archive",detail:"Classic DOS picks",symbol:"shippingbox",url:URL(string:"https://www.dosgamesarchive.com/")!),
        GameSourceProvider(name:"DOSGames.com",detail:"Popular DOS games",symbol:"gamecontroller",url:URL(string:"https://dosgames.com/")!),
        GameSourceProvider(name:"itch.io",detail:"New creator-made DOS games",symbol:"sparkles",url:URL(string:"https://itch.io/games/free/tag-dos")!),
        GameSourceProvider(name:"GOG",detail:"Classic store releases",symbol:"bag",url:URL(string:"https://www.gog.com/en/games?priceRange=0,0")!),
        GameSourceProvider(name:"ScummVM",detail:"Free classic adventures",symbol:"map",url:URL(string:"https://www.scummvm.org/games/")!)
    ]
}

@MainActor final class ArchiveModel: ObservableObject {
    unowned let libraryModel: LibraryModel
    let service: ArchiveService
    @Published var query = ""
    @Published var filter = ArchiveFilter.all
    @Published var items: [ArchiveItem] = []
    @Published var total = 0
    @Published var loading = false
    @Published var error: String?
    @Published var selected: ArchiveItem?
    @Published var detail: ArchiveDetail?
    @Published var fileName = ""
    @Published var detailLoading = false
    @Published var detailError: String?
    @Published var downloading = false
    @Published var adding = false
    @Published var progress = WebProgress(message:"")
    @Published var added: Game?
    private var addedSource: URL?
    @Published var artworkNote: String?
    var searchTask: Task<Void,Never>?
    var detailTask: Task<Void,Never>?
    var downloadTask: Task<Void,Never>?
    var detailWindow: ArchiveWindow?
    var detailFrames: [String:CGRect] = [:]
    private var generation = UUID()
    @Published var nextPage: Int?
    private var searchedQuery = ""
    private var searchedFilter = ArchiveFilter.all
    var started = false
    init(libraryModel: LibraryModel, service: ArchiveService = ArchiveService()) { self.libraryModel = libraryModel; self.service = service }
    var featured: Bool { searchedQuery.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && searchedFilter == .all }
    var file: ArchiveFile? { detail?.choices.first { $0.name == fileName } }
    var busy: Bool { downloading || adding }
    var installed: Game? {
        guard let selected, let file else { return nil }
        let source = service.fileURL(item:selected,file:file)
        if let added, addedSource == source { return libraryModel.games.first { $0.id == added.id } }
        return libraryModel.games.first {
            guard let record = libraryModel.library.webRecord($0) else { return false }
            return record.page == selected.page && record.entryURL == source
        }
    }
    func search(more: Bool = false) {
        if more && (loading || nextPage == nil) { return }
        searchTask?.cancel(); generation = UUID(); let token = generation
        if !more { nextPage = nil; searchedQuery = query; searchedFilter = filter; items = []; total = 0 }
        let requestedPage = more ? nextPage! : 1
        started = true; loading = true; error = nil
        searchTask = Task {
            do {
                let result = try await service.search(searchedQuery,filter:searchedFilter,page:requestedPage)
                try Task.checkCancellation(); guard generation == token else { return }
                let existing = Set(items.map(\.id))
                items += result.items.filter { !existing.contains($0.id) }; total = result.total; nextPage = result.nextPage
            } catch is CancellationError { }
            catch { if generation == token { self.error = error.localizedDescription } }
            if generation == token { loading = false }
        }
    }
    func show(_ item: ArchiveItem) {
        guard !busy else { detailWindow?.showWindow(nil); return }
        detailTask?.cancel(); selected = item; detail = nil; fileName = ""; detailError = nil; added = nil; artworkNote = nil; detailLoading = true
        if detailWindow == nil { detailWindow = ArchiveWindow(model:self) }
        detailWindow?.window?.title = item.title
        detailWindow?.showWindow(nil); detailWindow?.window?.makeKeyAndOrderFront(nil)
        detailTask = Task {
            do { let result = try await service.detail(item); try Task.checkCancellation(); detail = result; fileName = result.choices.first?.name ?? "" }
            catch is CancellationError { return }
            catch { detailError = error.localizedDescription }
            detailLoading = false
        }
    }
    func download() {
        guard !busy, !libraryModel.isImporting, libraryModel.canWrite, let detail, let file else { return }
        downloading = true; detailError = nil; artworkNote = nil; libraryModel.isImporting = true
        progress = WebProgress(message:"Preparing download…",detail:file.name)
        downloadTask = Task { [self] in
            let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("Flashback-Archive-Import-" + UUID().uuidString)
            defer {
                try? FileManager.default.removeItem(at:workspace)
                downloading = false; adding = false; libraryModel.isImporting = false; libraryModel.resumePendingImports()
            }
            do {
                let recovery = try await service.download(detail,file:file,to:workspace) { [weak self] value in
                    Task { @MainActor in if self?.downloading == true { self?.progress = value } }
                }
                try Task.checkCancellation(); downloading = false; adding = true
                progress = WebProgress(message:"Adding to Library…",detail:detail.item.title)
                guard let result = try await libraryModel.addRecoveredGame(recovery,title:detail.item.title) else { return }
                added = result.game; addedSource = recovery.record.entryURL
                let storage = libraryModel.library, game = result.game
                if !FileManager.default.fileExists(atPath:storage.defaultArtworkURL(game).path) {
                    do {
                        let bytes = try await service.artwork(detail.item), art = workspace.appendingPathComponent("Artwork")
                        try bytes.write(to:art)
                        try await Task.detached(priority:.utility) { try storage.setArtwork(art,for:game,custom:false) }.value
                        libraryModel.coverRevision += 1
                    } catch { artworkNote = "Game added. Archive artwork is unavailable; you can choose artwork in your library." }
                }
            } catch is CancellationError { progress = WebProgress(message:"Download canceled") }
            catch { detailError = error.localizedDescription }
        }
    }
    func showInLibrary() {
        libraryModel.showingDiscover = false; libraryModel.query = ""; libraryModel.filter = .all
        detailWindow?.close()
        (NSApp.delegate as? AppDelegate)?.window.makeKeyAndOrderFront(nil)
    }
}

struct ArchiveArtwork: View {
    let item: ArchiveItem
    let service: ArchiveService
    let height: CGFloat
    @State private var image: NSImage?
    var body: some View {
        Color(nsColor:.underPageBackgroundColor).frame(height:height).overlay {
            if let image { Image(nsImage:image).resizable().scaledToFit() }
            else { Image(systemName:"gamecontroller").font(.system(size:34,weight:.light)).foregroundStyle(.secondary) }
        }.clipped().accessibilityHidden(true).task(id:item.id) {
            image = nil
            guard let data = try? await service.artwork(item), !Task.isCancelled,
                  let source = CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1120] as CFDictionary) else { return }
            image = NSImage(cgImage:cg,size:.zero)
        }
    }
}

struct ArchiveView: View {
    @ObservedObject var model: ArchiveModel
    @ObservedObject var libraryModel: LibraryModel
    @FocusState private var focused: Bool
    @State private var showingAllFeatured = false
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            VStack(alignment:.leading,spacing:15) {
                Text("Discover").font(.system(size:27,weight:.semibold))
                Text("Find a favorite, try something new, and add it to your library.").font(.system(size:13)).foregroundStyle(.secondary)
                HStack(spacing:10) {
                    HStack(spacing:8) {
                        Image(systemName:"magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("Search the Internet Archive",text:$model.query).textFieldStyle(.plain).focused($focused).onSubmit { showingAllFeatured = false; model.search() }
                            .accessibilityLabel("Search Internet Archive")
                        if !model.query.isEmpty { Button { model.query = ""; showingAllFeatured = false; model.search() } label: { Image(systemName:"xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search") }
                    }.padding(10).background(Palette.card,in:RoundedRectangle(cornerRadius:7))
                        .overlay(RoundedRectangle(cornerRadius:7).strokeBorder(focused ? Palette.accent : Palette.separator.opacity(0.6),lineWidth:focused ? 2 : 1))
                        .auditFrame("archive-search",model:libraryModel)
                    Button("Search") { showingAllFeatured = false; model.search() }.controlSize(.large).buttonStyle(.borderedProminent).tint(Palette.action).auditFrame("archive-search-button",model:libraryModel)
                }
                HStack {
                    Picker("Format",selection:$model.filter) { ForEach(ArchiveFilter.allCases,id:\.self) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(width:265).accessibilityLabel("Archive format")
                        .onChange(of:model.filter) { _ in showingAllFeatured = false; model.search() }
                    Spacer()
                    if !model.loading && model.error == nil && !model.featured { Text("\(model.items.count.formatted()) shown").font(.system(size:11)).foregroundStyle(.secondary) }
                }
            }.padding(.horizontal,28).padding(.top,24).padding(.bottom,18)
            if model.featured {
                featuredContent
            } else {
                resultsContent
            }
            Text("Archive results are filtered · Source links open in your browser")
                .font(.system(size:11)).foregroundStyle(.secondary).padding(.horizontal,28).padding(.vertical,12).frame(maxWidth:.infinity,alignment:.leading).overlay(alignment:.top) { Divider() }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Palette.background)
            .onAppear { if !model.started { model.search() } }
            .onReceive(NotificationCenter.default.publisher(for:NSNotification.Name("FlashbackFindGame"))) { _ in focused = true }
    }

    private var featuredContent: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:28) {
                if model.items.isEmpty && model.loading {
                    inlineStatus("Finding this week’s games…",detail:"",symbol:nil)
                } else if let error = model.error, model.items.isEmpty {
                    VStack(spacing:12) {
                        statusText("Featured games are unavailable",detail:error,symbol:"wifi.exclamationmark")
                        Button("Try Again") { model.search() }.controlSize(.large)
                    }.frame(maxWidth:.infinity).padding(.vertical,28)
                } else if !model.items.isEmpty {
                    VStack(alignment:.leading,spacing:14) {
                        sectionHeader("Top games this week",detail:"A new selection every Monday")
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:220,maximum:360),spacing:16)],alignment:.leading,spacing:16) {
                            ForEach(Array(model.items.prefix(3))) { archiveCard($0,artworkHeight:108) }
                        }
                        if model.items.count > 3 {
                            Button(showingAllFeatured ? "Show top games only" : "Browse all \(model.items.count) featured games") {
                                showingAllFeatured.toggle()
                            }.buttonStyle(.link).font(.system(size:12,weight:.medium))
                                .accessibilityHint(showingAllFeatured ? "Hides the remaining featured games" : "Shows the remaining featured games")
                                .auditFrame("archive-browse-all",model:libraryModel)
                        }
                    }
                }

                sourceSection

                if showingAllFeatured && model.items.count > 3 {
                    VStack(alignment:.leading,spacing:14) {
                        sectionHeader("More featured games",detail:"Selected from the Flash and Shockwave catalog")
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:205,maximum:300),spacing:18)],alignment:.leading,spacing:18) {
                            ForEach(Array(model.items.dropFirst(3))) { archiveCard($0,artworkHeight:132) }
                        }
                    }.auditFrame("archive-featured-more",model:libraryModel)
                }
                if let error = model.error, !model.items.isEmpty { Text(error).font(.system(size:12)).foregroundStyle(.secondary).textSelection(.enabled) }
            }.padding(.horizontal,28).padding(.bottom,28)
        }
    }

    private var sourceSection: some View {
        VStack(alignment:.leading,spacing:14) {
            sectionHeader("Browse more sources",detail:"Find a DOS folder or ZIP, then choose Add Games")
            LazyVGrid(columns:[GridItem(.adaptive(minimum:200,maximum:280),spacing:10)],alignment:.leading,spacing:10) {
                ForEach(GameSourceProvider.all) { provider in providerCard(provider) }
            }
            Text("Handpicked games").font(.system(size:13,weight:.semibold)).padding(.top,2)
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:10) {
                    ForEach(GameSourceLink.recommendations) { game in
                        Link(destination:game.url) {
                            VStack(alignment:.leading,spacing:5) {
                                HStack(spacing:5) {
                                    Text(game.title).font(.system(size:12,weight:.semibold)).lineLimit(1)
                                    if game.tested { Text("TESTED").font(.system(size:8,weight:.bold)).foregroundStyle(Palette.action) }
                                }
                                HStack { Text("\(game.format) · \(game.source)").lineLimit(1); Spacer(); Image(systemName:"arrow.up.right") }
                                    .font(.system(size:10)).foregroundStyle(.secondary)
                            }.padding(11).frame(width:195,height:64,alignment:.leading)
                                .background(Palette.card,in:RoundedRectangle(cornerRadius:8))
                                .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Palette.separator.opacity(0.45)))
                        }.buttonStyle(.plain).help("Open the download page for \(game.title)")
                            .accessibilityLabel("Open \(game.title) on \(game.source)")
                    }
                }
            }
        }
    }

    @ViewBuilder private func providerCard(_ provider: GameSourceProvider) -> some View {
        if let url = provider.url {
            Link(destination:url) { providerLabel(provider,external:true) }
                .buttonStyle(.plain).help("Open \(provider.name)").accessibilityLabel("Open \(provider.name)")
        } else {
            Button { focused = true } label: { providerLabel(provider,external:false) }
                .buttonStyle(.plain).help("Search Internet Archive in Flashback").accessibilityLabel("Search Internet Archive in Flashback")
        }
    }

    private func providerLabel(_ provider: GameSourceProvider, external: Bool) -> some View {
        HStack(spacing:10) {
            Image(systemName:provider.symbol).font(.system(size:15)).foregroundStyle(Palette.accent).frame(width:18)
            VStack(alignment:.leading,spacing:3) {
                Text(provider.name).font(.system(size:11,weight:.semibold)).lineLimit(1)
                Text(provider.detail).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength:2)
            Image(systemName:external ? "arrow.up.right" : "magnifyingglass").font(.system(size:9)).foregroundStyle(.secondary)
        }.padding(10).frame(height:54).background(Palette.card,in:RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(Palette.separator.opacity(0.45)))
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment:.firstTextBaseline,spacing:10) {
            Text(title).font(.system(size:17,weight:.semibold))
            Spacer()
            Text(detail).font(.system(size:10)).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func archiveCard(_ item: ArchiveItem, artworkHeight: CGFloat) -> some View {
        Button { model.show(item) } label: {
            VStack(alignment:.leading,spacing:0) {
                ArchiveArtwork(item:item,service:model.service,height:artworkHeight)
                VStack(alignment:.leading,spacing:6) {
                    Text(item.title).font(.system(size:13,weight:.semibold)).lineLimit(2).frame(height:34,alignment:.topLeading)
                    HStack { Text(item.format); Spacer(); Image(systemName:"arrow.right") }.font(.system(size:10)).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            }.background(Palette.card,in:RoundedRectangle(cornerRadius:9)).clipShape(RoundedRectangle(cornerRadius:9))
                .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(Palette.separator.opacity(0.45)))
        }.buttonStyle(.plain).help("View \(item.title)").accessibilityLabel("Details for \(item.title)")
            .auditFrame("archive-card-\(item.id)",model:libraryModel)
    }

    private var resultsContent: some View {
        Group {
            if model.items.isEmpty && model.loading {
                status("Searching Internet Archive…",symbol:nil)
            } else if let error = model.error, model.items.isEmpty {
                VStack(spacing:14) { statusText("Couldn’t load games",detail:error,symbol:"wifi.exclamationmark"); Button("Try Again") { model.search() } }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(28)
            } else if model.items.isEmpty {
                VStack(spacing:16) {
                    statusText("No matching games",detail:"Try a different title or another format.",symbol:"magnifyingglass")
                    if model.nextPage != nil { Button("Keep Looking") { model.search(more:true) }.controlSize(.large).auditFrame("archive-keep-looking",model:libraryModel) }
                }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(28)
            } else {
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        sectionHeader("Search results",detail:"\(model.items.count.formatted()) shown")
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:205,maximum:300),spacing:18)],alignment:.leading,spacing:18) {
                            ForEach(model.items) { archiveCard($0,artworkHeight:140) }
                        }
                        if model.loading { ProgressView().frame(maxWidth:.infinity).padding() }
                        if let error = model.error { Text(error).font(.system(size:12)).foregroundStyle(.secondary).textSelection(.enabled) }
                        if !model.loading && model.nextPage != nil {
                            Button(model.error == nil ? "Load More" : "Try Again") { model.search(more:true) }.controlSize(.large).frame(maxWidth:.infinity).padding(.vertical,8)
                        }
                    }.padding(.horizontal,28).padding(.bottom,28)
                }
            }
        }
    }

    private func inlineStatus(_ title: String, detail: String, symbol: String?) -> some View {
        VStack(spacing:10) { if symbol == nil { ProgressView() }; statusText(title,detail:detail,symbol:symbol) }
            .frame(maxWidth:.infinity,minHeight:150).padding(.vertical,8)
    }
    private func status(_ title: String, detail: String = "", symbol: String?) -> some View {
        VStack(spacing:14) { if symbol == nil { ProgressView() }; statusText(title,detail:detail,symbol:symbol) }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(28)
    }
    private func statusText(_ title: String, detail: String, symbol: String?) -> some View {
        VStack(spacing:12) {
            if let symbol { Image(systemName:symbol).font(.system(size:30,weight:.light)).foregroundStyle(.secondary).accessibilityHidden(true) }
            Text(title).font(.system(size:19,weight:.semibold))
            if !detail.isEmpty { Text(detail).font(.system(size:13)).foregroundStyle(.secondary).multilineTextAlignment(.center).textSelection(.enabled) }
        }
    }
}

struct ArchiveDetailView: View {
    @ObservedObject var model: ArchiveModel
    @ObservedObject var libraryModel: LibraryModel
    var body: some View {
        VStack(spacing:0) {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    if let item = model.selected {
                        ArchiveArtwork(item:item,service:model.service,height:225).clipShape(RoundedRectangle(cornerRadius:10))
                        VStack(alignment:.leading,spacing:7) {
                            Text(model.detail?.item.title ?? item.title).font(.system(size:24,weight:.semibold)).textSelection(.enabled)
                            let creator = model.detail?.item.creator ?? item.creator
                            if !creator.isEmpty { Text(creator).font(.system(size:13)).foregroundStyle(.secondary).textSelection(.enabled) }
                            if let detail = model.detail, !detail.date.isEmpty { Text(detail.date).font(.system(size:12)).foregroundStyle(.secondary) }
                        }
                    }
                    if model.detailLoading { ProgressView("Loading game details…").frame(maxWidth:.infinity).padding() }
                    if let detail = model.detail {
                        VStack(alignment:.leading,spacing:10) {
                            Text("About this game").font(.system(size:15,weight:.semibold))
                            Text(detail.description.isEmpty ? "No description was provided for this item." : detail.description).font(.system(size:13)).lineSpacing(3).textSelection(.enabled)
                        }
                        Divider()
                        if !detail.choices.isEmpty {
                            VStack(alignment:.leading,spacing:10) {
                                Text("Game download").font(.system(size:15,weight:.semibold))
                                Picker("File",selection:$model.fileName) { ForEach(detail.choices) { file in Text("\(file.name) · \(file.size)").tag(file.name) } }.labelsHidden().disabled(model.busy)
                                if let file = model.file {
                                    let count = (try? detail.downloadFiles(file).count) ?? 0
                                    Text(file.ext == "zip" ? "The ZIP is unpacked into your library with its supporting files." : (count <= 1 ? "Standalone game file." : "Includes \(count-1) supporting \(count == 2 ? "file" : "files") from this Archive item."))
                                        .font(.system(size:12)).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text(detail.restricted ? "This item requires access that Flashback cannot provide. Open its Archive page for details." : "No supported game download is listed. Flashback can add SWF, Shockwave, HTML, and ZIP files; Windows installers and RAR archives cannot be added here.").font(.system(size:13)).foregroundStyle(.secondary)
                        }
                        Label(detail.compatibility(model.file),systemImage:"info.circle").font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        if !detail.rights.isEmpty { Text(ArchiveService.plainText(detail.rights)).font(.system(size:11)).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                    if let error = model.detailError {
                        VStack(alignment:.leading,spacing:8) {
                            Label("Couldn’t complete this request",systemImage:"exclamationmark.triangle").fontWeight(.semibold)
                            Text(error).textSelection(.enabled)
                            if model.detail == nil, let item = model.selected { Button("Try Again") { model.show(item) } }
                        }.font(.system(size:12)).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Palette.card,in:RoundedRectangle(cornerRadius:8))
                    }
                    if let note = model.artworkNote { Text(note).font(.system(size:12)).foregroundStyle(.secondary) }
                }.padding(24)
            }
            Divider()
            VStack(alignment:.leading,spacing:12) {
                if model.busy {
                    HStack(spacing:12) {
                        ProgressView().controlSize(.small)
                        VStack(alignment:.leading,spacing:4) {
                            Text(model.progress.message).fontWeight(.medium)
                            Text(model.progress.detail).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            if model.progress.bytes > 0 { Text(ByteCountFormatter.string(fromByteCount:model.progress.bytes,countStyle:.file)).foregroundStyle(.secondary) }
                        }.font(.system(size:12))
                        Spacer()
                        Button("Cancel") { model.downloadTask?.cancel() }.disabled(model.adding).auditFrame("archive-cancel",model:libraryModel)
                    }
                } else if let game = model.installed {
                    HStack { Label("In your library",systemImage:"checkmark.circle.fill").foregroundStyle(.secondary); Spacer(); Button("Show in Library",action:model.showInLibrary); Button("Play") { libraryModel.play(game) }.buttonStyle(.borderedProminent).tint(Palette.action).auditFrame("archive-play",model:libraryModel) }
                } else {
                    HStack {
                        if let item = model.selected { Link("View on Internet Archive",destination:item.page).font(.system(size:12)) }
                        Spacer()
                        Button("Download to Library",action:model.download).buttonStyle(.borderedProminent).tint(Palette.action)
                            .disabled(model.file == nil || libraryModel.isImporting || !libraryModel.canWrite).auditFrame("archive-download",model:libraryModel)
                    }
                }
            }.padding(20).controlSize(.large)
        }.frame(minWidth:580,minHeight:550).background(Palette.background).tint(Palette.accent)
            .coordinateSpace(name:"library").onPreferenceChange(LayoutFrames.self) { if libraryModel.auditsLayout { model.detailFrames = $0 } }
    }
}

@MainActor final class ArchiveWindow: NSWindowController, NSWindowDelegate {
    unowned let model: ArchiveModel
    init(model: ArchiveModel) {
        self.model = model
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "Game Details"; window.minSize = NSSize(width:580,height:580); window.isReleasedWhenClosed = false
        super.init(window:window); window.delegate = self
        window.contentView = NSHostingView(rootView:ArchiveDetailView(model:model,libraryModel:model.libraryModel)); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !model.busy }
    func windowWillClose(_ notification: Notification) { model.detailTask?.cancel(); model.detailWindow = nil }
}
