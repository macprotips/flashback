// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import SwiftUI
import WebKit
import UniformTypeIdentifiers

final class GameWebContent: WKWebView {
    var movieSize: CGSize? { didSet { fitMovie() } }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); fitMovie() }
    private func fitMovie() {
        guard let size = movieSize, bounds.width > 0, bounds.height > 0 else { return }
        // Browser zoom scales input coordinates together with the movie.
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        if abs(pageZoom - scale) > 0.001 { pageZoom = scale }
    }
}

final class GameResources: NSObject, WKURLSchemeHandler {
    let gameFolder: URL
    let resources: URL
    let host: String
    let entry: String
    let isHTML: Bool
    let isShockwave: Bool
    let routing: WebRouting?
    var missingFile: ((String) -> Void)?

    init(gameFolder: URL, resources: URL, host: String, entry: String, record: WebImportRecord? = nil) {
        self.gameFolder = gameFolder; self.resources = resources; self.host = host; self.entry = entry
        self.isHTML = ["html", "htm"].contains((entry as NSString).pathExtension.lowercased())
        self.isShockwave = ["dcr", "dir", "dxr"].contains((entry as NSString).pathExtension.lowercased())
        let html = self.isHTML
        routing = record.flatMap { $0.files.contains(where:{ $0.path == entry }) ? WebRouting(record:$0,origin:URL(string:"flashback://\(host)/")!,isHTML:html) : nil }
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        do {
            guard url.scheme == "flashback", url.host == host, task.request.httpMethod == "GET" else {
                throw LibraryError("This request is not part of the game.")
            }
            let file: URL
            var gamePath: String?
            if isHTML {
                let path = url.hasDirectoryPath ? url.path + (url.path.hasSuffix("/") ? "" : "/") + "index.html" : url.path
                gamePath = routing?.path(for:url) ?? String(path.dropFirst())
                file = try GameLibrary.contained(gamePath!, in:gameFolder)
            } else if url.path == "/player.html" { file = resources.appendingPathComponent(isShockwave ? "Shockwave.html" : "Player.html") }
            else if isShockwave && url.path.hasPrefix("/shockwave/") {
                file = try GameLibrary.contained(String(url.path.dropFirst(11)), in:resources.appendingPathComponent("Shockwave"))
            }
            else if url.path.hasPrefix("/runtime/") {
                file = try GameLibrary.contained(String(url.path.dropFirst(9)), in:resources.appendingPathComponent("Runtime"))
            } else if url.path.hasPrefix("/game/") {
                gamePath = routing?.path(for:url) ?? String(url.path.dropFirst(6))
                file = try GameLibrary.resource(gamePath!, entry:entry, in:gameFolder)
            } else { throw LibraryError("This file is outside the game folder.") }
            var data = try Data(contentsOf:file, options:.mappedIfSafe)
            let known = ["wasm":"application/wasm", "js":"application/javascript", "mjs":"application/javascript", "html":"text/html", "htm":"text/html", "css":"text/css", "json":"application/json", "swf":"application/x-shockwave-flash"]
            let storedType = gamePath.flatMap { path in routing?.record.files.first(where:{ $0.path == path })?.mime }
            let type = known[file.pathExtension.lowercased()] ?? (storedType?.isEmpty == false ? storedType : nil) ?? UTType(filenameExtension:file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            if isHTML, let routing, let path = gamePath, ["text/html","text/css","application/javascript","text/javascript","application/json"].contains(type), data.count <= 32 * 1024 * 1024 {
                data = Data(routing.text(WebPage.text(data),path:path,mime:type).utf8)
            }
            // An HTTP status is required even for a custom scheme: fetch() rejects a status of zero.
            var headers = [
                "Content-Type":type, "Content-Length":String(data.count), "Cache-Control":"no-cache"
            ]
            if isHTML {
                headers["Content-Security-Policy"] = "default-src 'self' data: blob:; script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:; style-src 'self' 'unsafe-inline'; connect-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'none'; frame-src 'self' blob:"
            }
            let response = HTTPURLResponse(url:url, statusCode:200, httpVersion:"HTTP/1.1", headerFields:headers)!
            task.didReceive(response); task.didReceive(data); task.didFinish()
        } catch {
            if isHTML || url.path.hasPrefix("/game/") { missingFile?(url.absoluteString) }
            task.didFailWithError(error)
        }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

@MainActor final class PlayerSession: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    @Published var game: Game
    let library: GameLibrary
    let resources: URL
    @Published var loading = true
    @Published var paused = false
    @Published var muted = false
    @Published var failure: String?
    @Published var missingFiles = false
    var missingResources: [String] = []
    var web: WKWebView!
    var onReady: (() -> Void)?
    var onCover: (() -> Void)?
    private var timeout: Task<Void, Never>?
    private var routing: WebRouting?

    init(game: Game, library: GameLibrary, resources: URL, dataStore: WKWebsiteDataStore) {
        self.game = game; self.library = library; self.resources = resources
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        let handler = GameResources(gameFolder:library.folder(for:game), resources:resources, host:game.id, entry:game.entry,record:library.webRecord(game))
        routing = handler.routing
        if let routing { config.userContentController.addUserScript(WKUserScript(source:routing.script,injectionTime:.atDocumentStart,forMainFrameOnly:false)) }
        handler.missingFile = { [weak self] url in
            self?.missingFiles = true
            if let self, self.missingResources.count < 100, !self.missingResources.contains(url) { self.missingResources.append(url) }
        }
        config.setURLSchemeHandler(handler, forURLScheme:"flashback")
        config.userContentController.add(self, name:"player")
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        web = GameWebContent(frame:.zero, configuration:config)
        web.navigationDelegate = self
        if game.isShockwave { web.uiDelegate = self }
        web.allowsBackForwardNavigationGestures = false
    }

    func start() {
        loading = true; failure = nil; missingFiles = false; missingResources = []; paused = false
        (web as? GameWebContent)?.movieSize = nil
        web.pageZoom = 1
        let origin = URL(string:"flashback://\(game.id)/")!
        web.load(URLRequest(url:origin.appendingPathComponent(game.isHTML ? game.entry : "player.html")))
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds:30_000_000_000)
            guard !Task.isCancelled, let self, self.loading else { return }
            self.failure = "This game is taking too long to open. Try restarting it, or add its complete folder."
            self.loading = false
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !game.isHTML, message.frameInfo.isMainFrame, message.frameInfo.request.url?.host == game.id,
              let body = message.body as? [String:Any], let event = body["event"] as? String else { return }
        if event == "stageSize", game.isShockwave,
           let width = body["width"] as? Double, let height = body["height"] as? Double,
           width > 0, height > 0, width <= 16384, height <= 16384 {
            (web as? GameWebContent)?.movieSize = CGSize(width:width,height:height)
        } else if event == "boot" {
            let origin = URL(string:"flashback://\(game.id)/")!
            let movieURL = origin.appendingPathComponent("game/" + game.entry)
            var options: [String:Any] = ["url":movieURL.absoluteString,
                           "base":movieURL.deletingLastPathComponent().absoluteString,
                           "publicPath":origin.appendingPathComponent("runtime", isDirectory:true).absoluteString]
            if game.isShockwave && routing == nil { options["parameters"] = library.localShockwaveParameters(game) }
            if let routing {
                options.merge(routing.options) { _, new in new }
                options["parameters"] = routing.record.parameters
                if game.isFlash || game.isShockwave { options["base"] = (routing.record.baseURL ?? routing.record.entryURL.deletingLastPathComponent()).absoluteString }
                // Director exposes its movie address to Lingo and embedded Flash.
                // Keep the archived address; WebRouting maps every fetch to local files.
                if game.isShockwave { options["url"] = routing.record.entryURL.absoluteString }
            }
            do {
                let json = try JSONSerialization.data(withJSONObject:options)
                web.evaluateJavaScript("startGame(\(String(decoding:json, as:UTF8.self))); void 0;")
            } catch { failure = error.localizedDescription; loading = false }
        } else if event == "ready" {
            ready()
        } else if event == "error", loading || game.isShockwave {
            timeout?.cancel(); loading = false
            failure = game.isShockwave
                ? "This Shockwave game couldn’t continue. Try Add from Website to recover its original settings, or add the complete game folder. Some Director features and Xtras remain unsupported."
                : "This game couldn’t start. It may need more files or a Flash feature that isn’t supported yet."
        }
    }

    private func ready() {
        timeout?.cancel(); loading = false
        if muted && game.isFlash { web.evaluateJavaScript("player.ruffle().volume = 0; void 0;") }
        web.window?.makeFirstResponder(web)
        onReady?()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds:4_000_000_000)
            guard let self, self.failure == nil else { return }
            self.captureCover()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if game.isHTML, webView.url?.scheme == "flashback", webView.url?.host == game.id { ready() }
    }

    func togglePause() {
        guard game.isFlash, !loading, failure == nil else { return }
        paused.toggle()
        web.evaluateJavaScript(paused ? "player.ruffle().suspend();" : "player.ruffle().resume();")
        if !paused { web.window?.makeFirstResponder(web) }
    }
    func toggleMute() {
        guard game.isFlash else { return }
        muted.toggle()
        web.evaluateJavaScript("player.ruffle().volume = \(muted ? 0 : 1); void 0;")
        web.window?.makeFirstResponder(web)
    }
    func stop() {
        timeout?.cancel()
        web.stopLoading()
        web.configuration.userContentController.removeScriptMessageHandler(forName:"player")
        web.loadHTMLString("", baseURL:nil)
    }
    func captureCover() {
        let destination = library.defaultArtworkURL(game)
        guard !loading, failure == nil, !FileManager.default.fileExists(atPath:destination.path), web.window != nil else { return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 560
        web.takeSnapshot(with:config) { [weak self] image, _ in
            guard let tiff = image?.tiffRepresentation,
                  let png = NSBitmapImageRep(data:tiff)?.representation(using:.png, properties:[:]) else { return }
            do {
                try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(), withIntermediateDirectories:true)
                try png.write(to:destination, options:.atomic)
                self?.onCover?()
            } catch { /* Artwork is optional; gameplay and saves remain available. */ }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = action.request.url
        let ownPage = url?.scheme == "flashback" && url?.host == game.id && (game.isHTML || url?.path == "/player.html")
        decisionHandler(ownPage || url?.absoluteString == "about:blank" ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFailProvisionalNavigation:navigation, withError:error)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false; failure = "The player couldn’t open. Try restarting the game."
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false; failure = "The game stopped unexpectedly. Restart it to play again."
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let window = webView.window else { completionHandler(); return }
        let alert = NSAlert()
        alert.messageText = game.title
        alert.informativeText = String(message.prefix(2000))
        alert.addButton(withTitle:"OK")
        alert.beginSheetModal(for:window) { _ in completionHandler() }
    }
}

struct GameWebView: NSViewRepresentable {
    let session: PlayerSession
    func makeNSView(context: Context) -> WKWebView { session.web }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct PlayerView: View {
    @ObservedObject var session: PlayerSession
    @State private var confirmRestart = false
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:10) {
                Button { NSApp.sendAction(#selector(AppDelegate.showLibrary),to:nil,from:nil) } label: {
                    Label("Library",systemImage:"square.grid.2x2").font(.system(size:12)).padding(.horizontal,4).frame(height:30)
                }.help("Show Library (⌘L)")
                Spacer()
                if session.game.isFlash {
                    Button { session.togglePause() } label: { Image(systemName:session.paused ? "play.fill" : "pause.fill").frame(width:32,height:30).contentShape(Rectangle()) }
                        .help(session.paused ? "Resume game" : "Pause game").accessibilityLabel(session.paused ? "Resume game" : "Pause game")
                        .disabled(session.loading || session.failure != nil)
                }
                Button { confirmRestart = true } label: { Image(systemName:"arrow.counterclockwise").frame(width:32,height:30).contentShape(Rectangle()) }
                    .help("Restart game").accessibilityLabel("Restart game")
                if session.game.isFlash {
                    Button { session.toggleMute() } label: { Image(systemName:session.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width:32,height:30).contentShape(Rectangle()) }
                        .help(session.muted ? "Unmute" : "Mute").accessibilityLabel(session.muted ? "Unmute" : "Mute")
                }
                Divider().frame(height:18)
                Button { session.web.window?.toggleFullScreen(nil) } label: { Image(systemName:"arrow.up.left.and.arrow.down.right").frame(width:32,height:30).contentShape(Rectangle()) }
                    .help("Full screen").accessibilityLabel("Full screen")
            }
            .buttonStyle(.borderless).font(.system(size:14)).padding(.horizontal,14).frame(height:46)
            .background(.bar)
            Divider()
            ZStack {
                Color.black
                GameWebView(session:session)
                if session.loading {
                    VStack(spacing:16) {
                        ProgressView().controlSize(.regular)
                        Text("Opening \(session.game.title)…").font(.system(size:13)).multilineTextAlignment(.center)
                            .lineLimit(3).frame(maxWidth:420).padding(.horizontal,24)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity).background(.regularMaterial)
                }
                if let failure = session.failure {
                    VStack(spacing:18) {
                        Image(systemName:"exclamationmark.triangle").font(.system(size:30,weight:.light)).foregroundStyle(.secondary)
                        Text("Unable to Open Game").font(.system(size:20,weight:.semibold))
                        Text(failure).font(.system(size:13)).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth:400).fixedSize(horizontal:false,vertical:true)
                        Button("Try Again") { session.start() }.buttonStyle(.borderedProminent).tint(Palette.action).controlSize(.large)
                    }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity).background(Palette.background)
                } else if session.paused {
                    VStack(spacing:16) {
                        Text("Paused").font(.system(size:23,weight:.semibold))
                        Button("Resume Game") { session.togglePause() }.buttonStyle(.borderedProminent).tint(Palette.action).controlSize(.large)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity).background(.ultraThinMaterial)
                }
            }
            if session.game.isShockwave && !session.missingFiles && session.failure == nil {
                Text("Shockwave support is experimental. Use the game’s pause and sound controls.")
                    .font(.caption).foregroundStyle(.secondary).padding(8).frame(maxWidth:.infinity).background(.bar)
            }
            if session.missingFiles && session.failure == nil {
                Label("Some game files are missing. Add the complete game folder.", systemImage:"info.circle")
                    .font(.system(size:12)).padding(10).frame(maxWidth:.infinity).background(.bar)
            }
        }
        .tint(Palette.accent)
        .alert("Restart this game?", isPresented:$confirmRestart) {
            Button("Cancel", role:.cancel) {}
            Button("Restart") { session.start() }
        } message: { Text("Progress that the game hasn’t saved will be lost.") }
    }
}

@MainActor final class GameWindow: NSWindowController, NSWindowDelegate {
    let session: PlayerSession
    var onClose: (() -> Void)?
    init(session: PlayerSession) {
        self.session = session
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:960,height:774), styleMask:[.titled,.closable,.miniaturizable,.resizable], backing:.buffered, defer:false)
        window.title = session.game.title
        window.minSize = NSSize(width:640,height:500)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        let content = NSHostingView(rootView:PlayerView(session:session))
        // The window owns its size; status text must not enlarge it off-screen.
        content.sizingOptions = []
        window.contentView = content
        super.init(window:window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func windowWillClose(_ notification: Notification) { session.stop(); onClose?() }
}
