// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import SwiftUI
import WebKit

@MainActor final class WebPageScanner: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    struct Snapshot { let url: URL; let html: String; let resources: [URL] }
    private var web: WKWebView?
    private var snapshots: [URL:Snapshot] = [:]
    private var failure: Error?
    let allowLocal: Bool
    init(allowLocal: Bool = false) { self.allowLocal = allowLocal }
    func scan(_ url: URL) async throws -> [Snapshot] {
        try await WebAddress.validateNetwork(url,allowLocal:allowLocal)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        // This offscreen view must run page timers during the bounded scan.
        if #available(macOS 14.0, *) { config.preferences.inactiveSchedulingPolicy = .none }
        config.mediaTypesRequiringUserActionForPlayback = .all
        let controller = config.userContentController
        controller.add(self,name:"scan")
        controller.addUserScript(WKUserScript(source:"""
        (()=>{
          const loads=[];window.__flashbackLoads=loads;
          const remember=(url,parameters={},base)=>{
            if(typeof url!=='string'||url.length>8192||loads.length>=100)return;
            const item={url,parameters:{},base};
            if(parameters&&typeof parameters==='object')for(const [key,value] of Object.entries(parameters).slice(0,100)){
              if(typeof value==='string'||typeof value==='number'||typeof value==='boolean')item.parameters[key]=String(value).slice(0,8192);
            }loads.push(item);return item;
          };
          const wrapObject=value=>value&&typeof value==='object'?new Proxy(value,{get(target,key,receiver){
            const original=Reflect.get(target,key,receiver);
            if(key==='embedSWF'&&typeof original==='function')return function(...args){remember(args[0],args[6],args[7]?.base);return Reflect.apply(original,target,args);};
            return original;
          }}):value;
          const hook=(name,wrap)=>{let value;try{Object.defineProperty(window,name,{configurable:true,get:()=>value,set:next=>{value=wrap(next);}});}catch{}};
          hook('swfobject',wrapObject);
          for(const name of ['SWFObject','FlashObject'])hook(name,value=>typeof value==='function'?new Proxy(value,{
            construct(target,args,newTarget){const item=remember(args[0]);const object=Reflect.construct(target,args,newTarget);
              return new Proxy(object,{get(target,key,receiver){const original=Reflect.get(target,key,receiver);
                if(key==='addVariable'&&typeof original==='function')return function(key,value){if(item)item.parameters[String(key)]=String(value).slice(0,8192);return original.call(target,key,value);};
                return original;}});}
          }):value);
          hook('AC_FL_RunContent',value=>typeof value==='function'?function(...args){
            const params={};for(let i=0;i+1<args.length;i+=2)params[String(args[i]).toLowerCase()]=args[i+1];
            let url=params.movie||params.src;if(typeof url==='string'&&!/\\.swf(?:[?#]|$)/i.test(url))url+='.swf';
            remember(url,Object.fromEntries(new URLSearchParams(params.flashvars||'')),params.base);return Reflect.apply(value,this,args);
          }:value);
        })();
        """,injectionTime:.atDocumentStart,forMainFrameOnly:false))
        controller.addUserScript(WKUserScript(source:"""
        (()=>{const send=()=>{try{
          const captured=(window.__flashbackLoads||[]).map(item=>{
            const object=document.createElement('object');object.type='application/x-shockwave-flash';object.setAttribute('data',item.url);
            const param=document.createElement('param');param.name='flashvars';param.value=new URLSearchParams(item.parameters).toString();object.appendChild(param);
            if(item.base){const base=document.createElement('param');base.name='base';base.value=String(item.base);object.appendChild(base);}
            return object.outerHTML;
          }).join('');
          window.webkit.messageHandlers.scan.postMessage({url:location.href,
          html:document.documentElement.outerHTML.slice(0,4000000)+captured.slice(0,194304),
          resources:performance.getEntriesByType('resource').slice(0,300).map(e=>e.name)});}catch{}};
          send();setTimeout(send,2000);setTimeout(send,5000);})();
        """,injectionTime:.atDocumentEnd,forMainFrameOnly:false))
        let privateHosts = [#"localhost[:/]"#,#"[^/]*\.localhost[:/]"#,#"[^/]*\.local[:/]"#,
            #"127\."#,#"10\."#,#"192\.168\."#,#"169\.254\."#,#"172\.1[6-9]\."#,#"172\.2[0-9]\."#,#"172\.3[01]\."#,
            #"100\.6[4-9]\."#,#"100\.[7-9][0-9]\."#,#"100\.1[01][0-9]\."#,#"100\.12[0-7]\."#,#"198\.1[89]\."#,#"0\."#,#"\["#]
        var rules: [[String:Any]] = [["trigger":["url-filter":".*","resource-type":["image","media","font"]],"action":["type":"block"]]]
        // WebKit content rules do not support regex alternation; use one rule per prefix.
        rules += privateHosts.map { ["trigger":["url-filter":"^https?://" + $0],"action":["type":"block"]] }
        if !allowLocal {
            let data = try JSONSerialization.data(withJSONObject:rules)
            let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier:"Flashback-website-scan-v1",encodedContentRuleList:String(decoding:data,as:UTF8.self))
            if let list { controller.add(list) }
        }
        let view = WKWebView(frame:NSRect(x:0,y:0,width:1024,height:768),configuration:config)
        web = view; view.navigationDelegate = self; view.uiDelegate = self
        defer { view.stopLoading(); controller.removeScriptMessageHandler(forName:"scan"); web = nil }
        view.load(URLRequest(url:url))
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds:500_000_000)
            if let failure { throw failure }
        }
        return Array(snapshots.values)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard snapshots.count < 24, let body = message.body as? [String:Any], let raw = body["url"] as? String,
              let url = URL(string:raw), (try? WebAddress.checked(url,allowLocal:allowLocal)) != nil,
              message.frameInfo.request.url?.host == url.host, let html = body["html"] as? String, html.utf8.count <= 8 * 1024 * 1024 else { return }
        let otherBytes = snapshots.filter { $0.key != url }.values.reduce(0) { $0 + $1.html.utf8.count }
        guard otherBytes + html.utf8.count <= 32 * 1024 * 1024 else { return }
        let urls = (body["resources"] as? [String] ?? []).prefix(300).compactMap { URL(string:$0) }.filter { (try? WebAddress.checked($0,allowLocal:allowLocal)) != nil }
        snapshots[url] = Snapshot(url:url,html:html,resources:urls)
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !action.shouldPerformDownload, let url = action.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        Task { do { try await WebAddress.validateNetwork(url,allowLocal:allowLocal); decisionHandler(.allow) } catch { decisionHandler(.cancel) } }
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let binary = response.response.url.flatMap { WebPage.gameExtension(url:$0,mime:response.response.mimeType ?? "",filename:response.response.suggestedFilename) } != nil
        decisionHandler(response.canShowMIMEType && !binary ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled && snapshots.isEmpty { failure = error }
    }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge,nil)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) { completionHandler() }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) { completionHandler(false) }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) { completionHandler(nil) }
}

@MainActor final class WebsiteImportModel: ObservableObject {
    enum Phase { case address, scanning, results, recovering, review, adding, done }
    @Published var address = ""
    @Published var phase = Phase.address
    @Published var candidates: [WebCandidate] = []
    @Published var selection: String?
    @Published var title = ""
    @Published var progress = WebProgress(message:"")
    @Published var error: String?
    @Published var recovery: WebRecovery?
    @Published var added: Game?
    @Published var alreadyPresent = false
    @Published var deeper = false
    @Published var scanWarnings: [WebImportRecord.Issue] = []
    let libraryModel: LibraryModel
    var collector: WebsiteCollector?
    var operation: Task<Void,Never>?
    var sourceURL: URL?
    let allowLocal: Bool
    var selected: WebCandidate? { candidates.first { $0.id == selection } }
    var busy: Bool { [.scanning,.recovering,.adding].contains(phase) }
    init(libraryModel: LibraryModel, allowLocal: Bool = false) { self.libraryModel = libraryModel; self.allowLocal = allowLocal }

    func scan() {
        guard !busy else { return }
        do {
            let url = allowLocal ? try WebAddress.checked(URL(string:address)!,allowLocal:true) : try WebAddress.parse(address)
            sourceURL = url; address = url.absoluteString; error = nil; deeper = false
            candidates = []; recovery = nil; added = nil; alreadyPresent = false; selection = nil; scanWarnings = []
            let collector = WebsiteCollector(allowLocal:allowLocal) { [weak self] progress in Task { @MainActor in self?.progress = progress } }
            self.collector = collector; phase = .scanning
            operation = Task {
                do {
                    candidates = try await collector.scan(url)
                    if candidates.isEmpty { try await render(url,collector:collector) }
                    scanWarnings = await collector.warnings()
                    chooseFirst(); phase = .results
                } catch is CancellationError { phase = .address }
                catch { self.error = error.localizedDescription; phase = .address }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func render(_ url: URL, collector: WebsiteCollector) async throws {
        deeper = true; progress = WebProgress(message:"Looking deeper…",detail:"Checking the page after its scripts run")
        for snapshot in try await WebPageScanner(allowLocal:allowLocal).scan(url) {
            try await collector.addRenderedPage(html:snapshot.html,url:snapshot.url,resources:snapshot.resources)
        }
        candidates = await collector.results()
    }
    func lookDeeper() {
        guard !busy, let url = sourceURL, let collector else { return }
        phase = .scanning; error = nil
        operation = Task {
            do { try await render(url,collector:collector); chooseFirst(); phase = .results }
            catch is CancellationError { phase = .address }
            catch { self.error = error.localizedDescription; phase = .results }
        }
    }
    func chooseFirst() { selection = candidates.first?.id; title = selected?.title ?? "" }
    func recover() {
        guard !busy, let candidate = selected, let collector else { return }
        phase = .recovering; error = nil
        operation = Task {
            do { recovery = try await collector.recover(candidate,title:cleanTitle); phase = .review }
            catch is CancellationError { phase = .address }
            catch { self.error = error.localizedDescription; phase = .results }
        }
    }
    var cleanTitle: String { let value = String(title.trimmingCharacters(in:.whitespacesAndNewlines).prefix(120)); return value.isEmpty ? (selected?.url.deletingPathExtension().lastPathComponent ?? "Website game") : value }
    func add() {
        guard phase == .review, !libraryModel.isImporting, libraryModel.canWrite, let recovery else { return }
        phase = .adding; error = nil; libraryModel.isImporting = true
        operation = Task {
            defer { libraryModel.isImporting = false; libraryModel.resumePendingImports() }
            do {
                guard let result = try await libraryModel.addRecoveredGame(recovery,title:cleanTitle) else { phase = .review; return }
                added = result.game; alreadyPresent = result.alreadyPresent
                phase = .done
                await collector?.clean(); collector = nil
            } catch { self.error = error.localizedDescription; phase = .review }
        }
    }
    nonisolated static func inspectJava(_ file: URL, resources: URL) throws {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let process = Process(), output = Pipe()
        process.executableURL = resources.appendingPathComponent("Java/\(arch)/bin/java")
        process.arguments = ["-Xmx128m","-Djava.awt.headless=true","-cp",resources.appendingPathComponent("JavaRunner.jar").path,"JavaRunner","--inspect",file.path]
        process.environment = ["PATH":"/usr/bin:/bin","LANG":"en_US.UTF-8"]
        process.standardOutput = output; process.standardError = output
        try process.run(); let message = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw LibraryError("This JAR cannot launch as a desktop or Java ME game. It may be an applet or library. " + String(String(decoding:message,as:UTF8.self).prefix(400))) }
    }
    func cancel() {
        guard phase != .adding else { return }
        operation?.cancel()
        let oldOperation = operation, oldCollector = collector
        operation = nil; collector = nil
        Task { await oldOperation?.value; await oldCollector?.clean() }
    }
    func saveReport() {
        guard let report = recovery?.record.report else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = cleanTitle + " — Recovery.txt"; panel.allowedContentTypes = [.plainText]
        panel.begin { result in
            if result == .OK, let url = panel.url { do { try report.write(to:url,atomically:true,encoding:.utf8) } catch { self.error = error.localizedDescription } }
        }
    }
}

struct WebsiteImportView: View {
    @ObservedObject var model: WebsiteImportModel
    @ObservedObject var libraryModel: LibraryModel
    let close: () -> Void
    @FocusState private var focusAddress: Bool
    @State private var showReport = false
    private var step: Int { [.review,.adding,.done].contains(model.phase) ? 3 : (model.phase == .recovering ? 2 : 1) }
    private var heading: String {
        switch model.phase {
        case .address,.scanning,.results: return "Find a game"
        case .recovering: return "Recover game files"
        case .review: return "Review recovered files"
        case .adding: return "Adding to Library"
        case .done: return model.alreadyPresent ? "Already in Library" : "Added to Library"
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(alignment:.firstTextBaseline) {
                Text(heading).font(.system(size:22,weight:.semibold))
                Spacer()
                if model.phase != .done { Text("Step \(step) of 3").font(.system(size:11)).foregroundStyle(.secondary) }
                else { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Complete") }
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    if ![.review,.adding,.done].contains(model.phase) { address }
                    if model.busy { activity }
                    if let error = model.error {
                        HStack(alignment:.top,spacing:10) {
                            Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                            VStack(alignment:.leading,spacing:5) {
                                Text("Couldn’t complete the import").fontWeight(.semibold)
                                Text(error).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                            }
                        }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Palette.card,in:RoundedRectangle(cornerRadius:6))
                    }
                    if model.phase == .results { results }
                    if [.review,.adding,.done].contains(model.phase), let recovery = model.recovery { review(recovery.record) }
                    if model.phase == .address {
                        VStack(alignment:.leading,spacing:9) {
                            Text("Before you import").fontWeight(.semibold)
                            Text("Only extract copyright-free games.")
                            Text("Flashback recovers available game files. Removed files, sign-in requirements, and games that depend on live servers can prevent offline play.")
                                .foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        }.padding(.top,10)
                    }
                }.font(.system(size:13)).padding(24).frame(maxWidth:.infinity,alignment:.leading)
            }
            Divider()
            HStack(spacing:10) {
                if model.busy && model.phase != .adding { Button("Cancel",action:model.cancel).keyboardShortcut(.cancelAction) }
                else { Button(model.phase == .done ? "Done" : "Close",action:close).keyboardShortcut(.cancelAction).disabled(model.phase == .adding) }
                Spacer()
                if model.phase == .address {
                    Button("Find Games",action:model.scan).buttonStyle(.borderedProminent).tint(Palette.action).keyboardShortcut(.defaultAction)
                        .disabled(model.address.trimmingCharacters(in:.whitespaces).isEmpty)
                }
                if model.phase == .results, model.selected != nil {
                    Button("Recover Game",action:model.recover).buttonStyle(.borderedProminent).tint(Palette.action).keyboardShortcut(.defaultAction)
                }
                if model.phase == .review {
                    Button("Back") { model.phase = .results }
                    Button("Add to Library",action:model.add).buttonStyle(.borderedProminent).tint(Palette.action).keyboardShortcut(.defaultAction)
                        .disabled(libraryModel.isImporting || !libraryModel.canWrite)
                }
                if model.phase == .done, let game = model.added {
                    Button("Play Game") { close(); model.libraryModel.play(game) }.buttonStyle(.borderedProminent).tint(Palette.action).keyboardShortcut(.defaultAction)
                }
            }.buttonStyle(.bordered).controlSize(.large).padding(.horizontal,24).padding(.vertical,16)
        }.frame(minWidth:640,minHeight:500).background(Palette.background).tint(Palette.accent)
            .onAppear { focusAddress = true }
            .onChange(of:model.phase) { phase in focusAddress = phase == .address }
            .onChange(of:model.address) { value in
                if model.phase == .results && value != model.sourceURL?.absoluteString { model.phase = .address; model.selection = nil }
            }
    }
    private var address: some View {
        VStack(alignment:.leading,spacing:9) {
            Text("Website address").fontWeight(.medium)
            HStack(spacing:8) {
                TextField("https://example.com/play/game",text:$model.address).textFieldStyle(.roundedBorder).focused($focusAddress)
                    .accessibilityLabel("Website address").onSubmit { model.scan() }.disabled(model.busy)
                Button("Paste") { if let value = NSPasteboard.general.string(forType:.string) { model.address = value.trimmingCharacters(in:.whitespacesAndNewlines) } }
                    .disabled(model.busy)
            }.controlSize(.large)
            Text("Use a game page or a direct Flash, Java, HTML5, Shockwave, or ZIP link.")
                .font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var activity: some View {
        HStack(alignment:.top,spacing:12) {
            ProgressView().controlSize(.small).padding(.top,2)
            VStack(alignment:.leading,spacing:6) {
                Text(model.phase == .adding ? "Adding to your library…" : model.progress.message).fontWeight(.medium)
                Text(model.phase == .adding ? "Saving the game and its recovery report." : model.progress.detail)
                    .font(.system(size:12)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                if model.progress.bytes > 0 {
                    Text("\(model.progress.files) files · \(ByteCountFormatter.string(fromByteCount:model.progress.bytes,countStyle:.file))")
                        .font(.system(size:12).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical,10).frame(maxWidth:.infinity,alignment:.leading)
    }
    private var results: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(model.candidates.isEmpty ? "No games found" : "\(model.candidates.count) \(model.candidates.count == 1 ? "game found" : "possible games found")").fontWeight(.semibold)
                Spacer()
                if !model.deeper { Button("Look Deeper",action:model.lookDeeper).help("Check the page after its scripts run.") }
            }
            if model.candidates.isEmpty {
                Text("Try the original game page or a direct download. The site may have removed the files or may require a sign-in.").foregroundStyle(.secondary)
            }
            VStack(spacing:0) {
                ForEach(model.candidates) { item in
                    Button { model.selection = item.id; model.title = item.title } label: {
                        HStack(alignment:.top,spacing:11) {
                            Image(systemName:model.selection == item.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(model.selection == item.id ? Palette.accent : .secondary).padding(.top,2).accessibilityHidden(true)
                            VStack(alignment:.leading,spacing:5) {
                                HStack(alignment:.firstTextBaseline,spacing:12) {
                                    Text(item.url.lastPathComponent.isEmpty ? item.title : item.url.lastPathComponent)
                                        .font(.system(size:13,weight:.semibold)).lineLimit(2).truncationMode(.middle)
                                    Spacer(minLength:0)
                                    Text(item.kind.uppercased()).font(.system(size:10,weight:.medium)).foregroundStyle(.secondary).fixedSize()
                                }
                                Text(item.evidence + " · " + (item.url.host ?? "")).font(.system(size:12)).foregroundStyle(.secondary).lineLimit(2)
                                Text(item.url.absoluteString).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(item.url.absoluteString)
                            }
                        }.padding(13).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                            .background(model.selection == item.id ? Palette.accent.opacity(0.08) : Color.clear)
                    }.buttonStyle(.plain).accessibilityLabel("\(item.kind) game: \(item.url.lastPathComponent), \(item.evidence)")
                        .accessibilityAddTraits(model.selection == item.id ? [.isSelected] : [])
                    if item.id != model.candidates.last?.id { Divider() }
                }
            }.background(Palette.card,in:RoundedRectangle(cornerRadius:7))
                .clipShape(RoundedRectangle(cornerRadius:7))
                .overlay(RoundedRectangle(cornerRadius:7).strokeBorder(Palette.separator.opacity(0.6)))
            if !model.scanWarnings.isEmpty {
                Label("\(model.scanWarnings.count) page resources could not be read. More games may be present.",systemImage:"info.circle")
                    .font(.system(size:12)).foregroundStyle(.secondary)
            }
            if model.selected != nil { Text("Select the main game. You’ll review the files before adding it.").font(.system(size:12)).foregroundStyle(.secondary) }
        }
    }
    private func review(_ record: WebImportRecord) -> some View {
        VStack(alignment:.leading,spacing:20) {
            if model.phase == .done { Text(model.cleanTitle).font(.system(size:20,weight:.semibold)).textSelection(.enabled) }
            else {
                VStack(alignment:.leading,spacing:8) {
                    Text("Game name").fontWeight(.medium)
                    TextField("Game name",text:$model.title).textFieldStyle(.roundedBorder).controlSize(.large).disabled(model.phase == .adding)
                }
            }
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Text("Recovered").foregroundStyle(.secondary).frame(width:82,alignment:.leading)
                    Text("\(record.files.count) files · \(ByteCountFormatter.string(fromByteCount:record.bytes,countStyle:.file))").monospacedDigit()
                }
                HStack(alignment:.top) {
                    Text("Source").foregroundStyle(.secondary).frame(width:82,alignment:.leading)
                    Text(record.page.absoluteString).lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(record.page.absoluteString)
                }
            }
            if !record.issues.isEmpty {
                HStack(alignment:.top,spacing:10) {
                    Image(systemName:"exclamationmark.triangle").foregroundStyle(.orange).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:6) {
                        Text("\(record.issues.count) \(record.issues.count == 1 ? "reference" : "references") unavailable or skipped").fontWeight(.semibold)
                        Text("Some references are optional. Missing required files may prevent the game from starting or leave sounds and levels unavailable.")
                            .font(.system(size:12)).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Files are stored on this Mac. Games that require live servers or unsupported player features may not work offline.")
                .font(.system(size:12)).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("Recovery report").fontWeight(.semibold)
                Spacer()
                Button("Save Report…",action:model.saveReport)
            }
            DisclosureGroup("File details",isExpanded:$showReport) {
                Text(record.report).font(.system(size:11,design:.monospaced)).textSelection(.enabled)
                    .frame(maxWidth:.infinity,alignment:.leading).padding(.top,10)
            }.font(.system(size:12))
        }
    }
}

@MainActor final class WebsiteImportWindow: NSWindowController, NSWindowDelegate {
    let model: WebsiteImportModel
    var onClose: (() -> Void)?
    init(libraryModel: LibraryModel, allowLocal: Bool = false) {
        model = WebsiteImportModel(libraryModel:libraryModel,allowLocal:allowLocal)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:680,height:590),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "Add from Website"; window.minSize = NSSize(width:640,height:530); window.isReleasedWhenClosed = false
        super.init(window:window); window.delegate = self
        window.contentView = NSHostingView(rootView:WebsiteImportView(model:model,libraryModel:libraryModel,close:{ [weak self] in self?.close() }))
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model.phase != .adding }
    func windowWillClose(_ notification: Notification) { model.cancel(); onClose?() }
}
