// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

struct WebImportRecord: Codable, Sendable {
    struct File: Codable, Sendable {
        var urls: [URL]
        var path: String
        var mime: String
        var bytes: Int64
        var sha256: String
    }
    struct Issue: Codable, Identifiable, Sendable {
        var id: String { url.absoluteString + reason }
        let url: URL
        let reason: String
        let evidence: String
    }
    var page: URL
    var entryURL: URL
    var embeddingPage: URL? = nil
    var baseURL: URL? = nil
    var title: String
    var date = Date()
    var parameters: [String:String]
    var files: [File] = []
    var issues: [Issue] = []
    var documentBases: [String:URL] = [:]
    var bytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    var report: String {
        ([title, "Source: " + page.absoluteString, "Game: " + entryURL.absoluteString,
          "Embedded page: " + (embeddingPage ?? page).absoluteString,
          "Asset base: " + (baseURL ?? entryURL.deletingLastPathComponent()).absoluteString,
          "Recovered: \(files.count) files, \(ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file))",
          "Some games depend on unavailable servers or unsupported player features.", "", "RECOVERED FILES"] +
         files.map { "\($0.path) (\($0.bytes) bytes)\n  \($0.urls.first?.absoluteString ?? "")\n  SHA-256: \($0.sha256)" } +
         ["", "UNAVAILABLE / SKIPPED REFERENCES"] + issues.map { "\($0.url.absoluteString)\n  \($0.reason) [\($0.evidence)]" }).joined(separator:"\n")
    }

    static func namespace(_ url: URL) -> String {
        "web/" + (url.scheme ?? "https") + "/" + component((url.host ?? "unknown") + (url.port.map { ":\($0)" } ?? "")) + "/"
    }
    static func component(_ value: String) -> String {
        if !value.isEmpty, value != ".", value != "..", value.utf8.count < 180,
           !value.contains(where:{ "/\\:\0".contains($0) || $0.isNewline }) { return value }
        return "_" + digest(Data(value.utf8)).prefix(24)
    }
    static func path(_ url: URL, kind: String? = nil) -> String {
        var parts = url.path.split(separator:"/").map { component(String($0)) }
        if parts.isEmpty || url.hasDirectoryPath { parts.append("index.html") }
        var name = parts.removeLast()
        if let kind, (name as NSString).pathExtension.lowercased() != kind { name += "." + kind }
        if let query = url.query, !query.isEmpty {
            let ext = (name as NSString).pathExtension
            name = (name as NSString).deletingPathExtension + "~" + digest(Data(query.utf8)).prefix(16) + (ext.isEmpty ? "" : "." + ext)
        }
        return namespace(url) + (parts + [name]).joined(separator:"/")
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    static func hashFile(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom:file); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount:65536), !data.isEmpty { hash.update(data:data) }
        return hash.finalize().map { String(format:"%02x",$0) }.joined()
    }
}

extension GameLibrary {
    func localShockwaveParameters(_ game: Game) -> [String:String] {
        guard game.isShockwave else { return [:] }
        let root = folder(for:game), fm = FileManager.default
        // Use a reserved origin only to resolve relative HTML links. Parsing
        // never loads the page, runs its scripts, or contacts this address.
        let origin = URL(string:"https://flashback.invalid/")!
        let movieURL = origin.appendingPathComponent(game.entry)
        var directory = (game.entry as NSString).deletingLastPathComponent
        var remainingBytes = 8 * 1024 * 1024, remainingPages = 64
        while remainingPages > 0 {
            let folder = directory.isEmpty ? root : root.appendingPathComponent(directory)
            let pages = ((try? fm.contentsOfDirectory(atPath:folder.path)) ?? []).filter {
                ["html","htm"].contains(($0 as NSString).pathExtension.lowercased())
            }.sorted()
            for name in pages.prefix(remainingPages) {
                remainingPages -= 1
                let relative = directory.isEmpty ? name : directory + "/" + name
                guard let file = try? Self.contained(relative,in:root),
                      let size = try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize,
                      size <= min(2 * 1024 * 1024,remainingBytes),
                      let data = try? Data(contentsOf:file) else { continue }
                remainingBytes -= data.count
                let page = WebPage.parse(WebPage.text(data),url:origin.appendingPathComponent(relative))
                if let embed = page.candidates.first(where:{ $0.score == 100 && $0.url.host == movieURL.host && $0.url.path == movieURL.path }) {
                    return embed.parameters
                }
            }
            if directory.isEmpty { break }
            directory = (directory as NSString).deletingLastPathComponent
        }
        return [:]
    }

    func webRecordURL(_ game: Game) -> URL { root.appendingPathComponent("Web Imports/\(game.id).json") }
    func webRecord(_ game: Game) -> WebImportRecord? {
        guard let data = try? Data(contentsOf:webRecordURL(game)), data.count < 16 * 1024 * 1024,
              let record = try? JSONDecoder().decode(WebImportRecord.self,from:data), record.files.count <= 10000,
              record.files.allSatisfy({ (try? Self.contained($0.path,in:folder(for:game))) != nil }) else { return nil }
        return record
    }
    func saveWebRecord(_ record: WebImportRecord, for game: Game) throws {
        let url = webRecordURL(game)
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        try encoder.encode(record).write(to:url,options:.atomic)
    }
}

struct WebProgress: Sendable {
    var message: String
    var detail = ""
    var files = 0
    var bytes: Int64 = 0
}
struct WebRecovery: Sendable {
    let source: URL
    let entry: String?
    let record: WebImportRecord
}

/// One import owns one temporary workspace. The library sees only a completed recovery.
actor WebsiteCollector {
    let workspace: URL
    let allowLocal: Bool
    let progress: @Sendable (WebProgress) -> Void
    private var cache: [URL:WebDownload] = [:]
    private var pages: [URL:WebPage] = [:]
    private var candidates: [String:WebCandidate] = [:]
    private var issues: [WebImportRecord.Issue] = []
    private var transferred: Int64 = 0
    private var scanBytes: Int64 = 0
    private var requested: Set<URL> = []
    private var sourcePage: URL?
    private var primaryPage: URL? { sourcePage.flatMap { cache[$0]?.url } ?? sourcePage }

    init(allowLocal: Bool = false, progress: @escaping @Sendable (WebProgress) -> Void) {
        self.allowLocal = allowLocal; self.progress = progress
        workspace = FileManager.default.temporaryDirectory.appendingPathComponent("Flashback-web-" + UUID().uuidString)
    }
    deinit { try? FileManager.default.removeItem(at:workspace) }
    func clean() { try? FileManager.default.removeItem(at:workspace) }
    func results() -> [WebCandidate] {
        let primary = primaryPage
        return candidates.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            let first = $0.pageURL == primary, second = $1.pageURL == primary
            if first != second { return first }
            return $0.url.absoluteString < $1.url.absoluteString
        }
    }
    func warnings() -> [WebImportRecord.Issue] { issues }

    private func fetch(_ url: URL, referer: URL?, scan: Bool, limit: Int64 = 512 * 1024 * 1024) async throws -> WebDownload {
        try Task.checkCancellation()
        if let saved = cache[url], !saved.binaryReferenceOnly { return saved }
        guard requested.count < 5500, transferred < 1_073_741_824 else { throw LibraryError("The recovery reached its 1 GB or 5,500-request limit.") }
        requested.insert(url)
        let previous = transferred, count = cache.count, notify = progress
        let download = try await WebTransfer(url:url,directory:workspace.appendingPathComponent("Transfers"),
            limit:scan ? min(limit,8 * 1024 * 1024) : min(limit,1_073_741_824 - transferred),scanOnly:scan,allowLocal:allowLocal,
            progress:{ bytes, _ in notify(WebProgress(message:scan ? "Reading the website…" : "Recovering game files…",detail:url.lastPathComponent,files:count,bytes:previous + bytes)) }).start(referer:referer)
        transferred += download.bytes
        if scan { scanBytes += download.bytes; guard scanBytes <= 32 * 1024 * 1024 else { throw LibraryError("This site exceeded the 32 MB page-scan limit.") } }
        guard transferred <= 1_073_741_824 else { throw LibraryError("The recovery reached its 1 GB download limit.") }
        cache[url] = download; cache[download.url] = download
        return download
    }

    private func merge(_ page: WebPage) {
        var page = page
        if let old = pages[page.url] {
            page.resources = Array(Set(old.resources + page.resources)).sorted { $0.url.absoluteString < $1.url.absoluteString }
            page.folders = Array(Set(old.folders + page.folders)).sorted { $0.absoluteString < $1.absoluteString }
            for item in old.candidates { page.merge(item) }
        }
        pages[page.url] = page
        for candidate in page.candidates {
            if let old = candidates[candidate.id], old.score > candidate.score ||
                (old.score == candidate.score && candidate.pageURL != primaryPage) { continue }
            if candidates.count >= 200 && candidates[candidate.id] == nil {
                if !issues.contains(where:{ $0.evidence == "Result limit" }) { issues.append(.init(url:page.url,reason:"This page lists more than 200 game files. Use a specific game's page to narrow the scan.",evidence:"Result limit")) }
                continue
            }
            candidates[candidate.id] = candidate
        }
    }

    func scan(_ url: URL) async throws -> [WebCandidate] {
        _ = try WebAddress.checked(url,allowLocal:allowLocal)
        sourcePage = url
        if let kind = WebPage.gameExtension(url:url) {
            let item = WebCandidate(url:url,pageURL:url,title:url.deletingPathExtension().lastPathComponent,kind:kind,evidence:"Direct game file",score:100,parameters:WebPage.queryParameters(url))
            candidates[item.id] = item; return results()
        }
        var queue: [(URL,Int)] = [(url,0)], visited = Set<URL>(), scripts = Set<URL>()
        while !queue.isEmpty && visited.count < 24 {
            try Task.checkCancellation()
            let (next, depth) = queue.removeFirst()
            guard visited.insert(next).inserted else { continue }
            progress(WebProgress(message:"Looking for games…",detail:next.host ?? "",files:visited.count,bytes:transferred))
            do {
                let response = try await fetch(next,referer:url,scan:true)
                if response.binaryReferenceOnly, let kind = WebPage.gameExtension(url:response.url,mime:response.mimeType,filename:response.filename) {
                    let item = WebCandidate(url:response.url,pageURL:url,title:(response.filename as NSString).deletingPathExtension,kind:kind,evidence:"Game download",score:100,parameters:WebPage.queryParameters(response.url))
                    candidates[item.id] = item; continue
                }
                let text = WebPage.text(try Data(contentsOf:response.file))
                var page = WebPage.parse(text,url:response.url)
                for script in page.scripts.prefix(20) where scripts.count < 30 && scripts.insert(script).inserted {
                    do {
                        let download = try await fetch(script,referer:page.url,scan:true,limit:4 * 1024 * 1024)
                        if !download.binaryReferenceOnly { page.addScript(WebPage.text(try Data(contentsOf:download.file))) }
                    } catch is CancellationError { throw CancellationError() }
                    catch { issues.append(.init(url:script,reason:error.localizedDescription,evidence:"Page script")) }
                }
                merge(page)
                if depth < 3 { queue += page.frames.prefix(12).map { ($0,depth + 1) } }
            } catch is CancellationError { throw CancellationError() }
            catch {
                if visited.count == 1 { throw error }
                issues.append(.init(url:next,reason:error.localizedDescription,evidence:"Embedded page"))
            }
        }
        if !queue.isEmpty { issues.append(.init(url:url,reason:"Stopped at the page-scan limit.",evidence:"Scan limit")) }
        return results()
    }

    func addRenderedPage(html: String, url: URL, resources: [URL]) async throws {
        _ = try WebAddress.checked(url,allowLocal:allowLocal)
        var page = WebPage.parse(String(html.prefix(4 * 1024 * 1024)),url:url)
        for resource in resources.prefix(300) {
            if let kind = WebPage.gameExtension(url:resource) {
                page.merge(WebCandidate(url:resource,pageURL:url,title:page.title,kind:kind,evidence:"Loaded by the page",score:90,parameters:WebPage.queryParameters(resource)))
            }
            if WebPage.assets.contains(resource.pathExtension.lowercased()) { page.resources.append(WebReference(url:resource,role:"Loaded by the page")) }
        }
        merge(page)
    }

    private func directoryReferences(_ roots: [URL], referer: URL, seen: inout Set<URL>) async throws -> [WebReference] {
        var directories = roots.prefix(30).map { ($0,0) }, files: [WebReference] = []
        while !directories.isEmpty && seen.count < 60 {
            let (url,depth) = directories.removeFirst()
            guard seen.insert(url).inserted else { continue }
            try Task.checkCancellation()
            do {
                let listing = try await fetch(url,referer:referer,scan:true,limit:2 * 1024 * 1024)
                guard !listing.binaryReferenceOnly else { continue }
                let page = WebPage.parse(WebPage.text(try Data(contentsOf:listing.file)),url:listing.url)
                if page.isDirectory {
                    files += page.resources
                    if depth < 4 { directories += page.folders.prefix(30).map { ($0,depth + 1) } }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { /* Directory listings are optional discovery, not required assets. */ }
        }
        return files
    }

    static func assetDirectory(_ url: URL) -> URL {
        let parts = url.path.split(separator:"/").map(String.init)
        if let template = parts.firstIndex(where:{ !WebPage.matches(#"[%$][A-Za-z{]|\{[^}]+\}"#,$0).isEmpty }),
           var components = URLComponents(url:url,resolvingAgainstBaseURL:true) {
            components.path = "/" + parts.prefix(template).joined(separator:"/") + (template > 0 ? "/" : "")
            components.query = nil
            if let directory = components.url { return directory }
        }
        return url.deletingLastPathComponent()
    }

    func recover(_ candidate: WebCandidate, title: String) async throws -> WebRecovery {
        let fm = FileManager.default, payload = workspace.appendingPathComponent("Game")
        try? fm.removeItem(at:payload)
        try fm.createDirectory(at:payload,withIntermediateDirectories:true)
        var record = WebImportRecord(page:sourcePage ?? candidate.pageURL,entryURL:candidate.url,embeddingPage:candidate.pageURL,title:title,parameters:candidate.parameters)
        let main = try await fetch(candidate.url,referer:candidate.pageURL,scan:false)
        guard main.bytes > 0 else { throw LibraryError("The game download is empty.") }
        record.entryURL = main.url
        record.parameters.merge(WebPage.queryParameters(main.url)) { old, _ in old }
        var gameBase = candidate.baseURL ?? main.url.deletingLastPathComponent()
        if candidate.kind == "swf", candidate.baseURL == nil {
            // A direct SWF link loses its HTML base. Recover it only when a
            // nearby page actually embeds this exact movie; do not guess paths.
            var folder = main.url.deletingLastPathComponent()
            for _ in 0..<2 {
                do {
                    let nearby = try await fetch(folder,referer:candidate.pageURL,scan:true,limit:2 * 1024 * 1024)
                    if !nearby.binaryReferenceOnly {
                        let page = WebPage.parse(WebPage.text(try Data(contentsOf:nearby.file)),url:nearby.url)
                        if let embed = page.candidates.first(where:{ $0.url == main.url && $0.baseURL != nil }) {
                            gameBase = embed.baseURL!; record.embeddingPage = page.url; break
                        }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { /* Direct files need not have a surviving embedding page. */ }
                folder = folder.deletingLastPathComponent()
            }
        }
        record.baseURL = gameBase
        let mainPath = WebImportRecord.path(main.url,kind:candidate.kind)
        var entries = Set<URL>(), paths = Set<String>()
        func store(_ download: WebDownload, kind: String? = nil) throws -> String {
            var path = WebImportRecord.path(download.url,kind:kind)
            if paths.contains(where:{ $0.lowercased() == path.lowercased() && $0 != path }) {
                let ext = (path as NSString).pathExtension
                path = (path as NSString).deletingPathExtension + "~" + WebImportRecord.digest(Data(download.url.absoluteString.utf8)).prefix(16) + (ext.isEmpty ? "" : "." + ext)
            }
            let target = try GameLibrary.contained(path,in:payload)
            if !paths.insert(path).inserted {
                if let index = record.files.firstIndex(where:{ $0.path == path }), !record.files[index].urls.contains(download.requestedURL) { record.files[index].urls.append(download.requestedURL) }
                return path
            }
            try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            try fm.copyItem(at:download.file,to:target)
            record.files.append(.init(urls:Array(Set([download.requestedURL,download.url])).sorted { $0.absoluteString < $1.absoluteString },path:path,mime:download.mimeType,bytes:download.bytes,sha256:try WebImportRecord.hashFile(target)))
            return path
        }
        _ = try store(main,kind:candidate.kind)
        entries.insert(candidate.url); entries.insert(main.url)
        if candidate.kind == "zip" { return WebRecovery(source:try GameLibrary.contained(mainPath,in:payload),entry:nil,record:record) }
        try GameLibrary.validateGame(GameLibrary.contained(mainPath,in:payload))
        var queue: [(WebReference,Int)] = candidate.companions.map { (WebReference(url:$0,role:"Companion archive"),0) }
        let context = pages[candidate.pageURL]
        if candidate.kind == "html" {
            let page = WebPage.parse(WebPage.text(try Data(contentsOf:main.file)),url:main.url)
            record.documentBases[mainPath] = page.base
            queue += page.resources.map { ($0,0) }
            if let context { queue += context.resources.map { ($0,0) } }
        } else if candidate.kind != "jar" {
            queue += WebPage.binaryReferences(try Data(contentsOf:main.file),from:gameBase).prefix(500).map { (WebReference(url:$0,role:"Possible game asset"),0) }
            if let context {
                queue += context.resources.filter { $0.url.path.hasPrefix(main.url.deletingLastPathComponent().path + "/") && $0.url.host == main.url.host }.map { ($0,0) }
            }
            for value in candidate.parameters.values {
                if let url = WebAddress.resolve(value,from:gameBase), WebPage.assets.contains(url.pathExtension.lowercased()) { queue.append((WebReference(url:url,role:"Launch parameter"),0)) }
            }
        }
        // Public directory indexes are often the only surviving map of old sound/level folders.
        var seenDirectories = Set<URL>()
        if candidate.kind != "jar" {
            let assetFolders = queue.map { Self.assetDirectory($0.0.url) }.filter {
                candidate.kind != "html" || ($0.host == main.url.host && $0.path.hasPrefix(main.url.deletingLastPathComponent().path + "/"))
            }
            let roots = [main.url.deletingLastPathComponent()] + (context?.folders ?? []) + assetFolders
            queue += try await directoryReferences(roots,referer:candidate.pageURL,seen:&seenDirectories).map { ($0,0) }
        }
        while !queue.isEmpty && entries.count < 5000 {
            try Task.checkCancellation()
            var batch: [(WebReference,Int)] = []
            while !queue.isEmpty && batch.count < 4 {
                let item = queue.removeFirst()
                if entries.insert(item.0.url).inserted { batch.append(item) }
            }
            let downloads = await withTaskGroup(of:(WebReference,Int,Result<WebDownload,Error>).self) { group in
                for (ref,depth) in batch { group.addTask { do { return (ref,depth,.success(try await self.fetch(ref.url,referer:candidate.pageURL,scan:false))) } catch { return (ref,depth,.failure(error)) } } }
                var values: [(WebReference,Int,Result<WebDownload,Error>)] = []
                for await value in group { values.append(value) }
                return values.sorted { $0.0.url.absoluteString < $1.0.url.absoluteString }
            }
            for (ref,depth,result) in downloads {
                try Task.checkCancellation()
                switch result {
                case .failure(let error): record.issues.append(.init(url:ref.url,reason:error.localizedDescription,evidence:ref.role))
                case .success(let download):
                    // An expired asset URL often returns the site's HTML error page with HTTP 200.
                    if download.mimeType == "text/html" && !["frame","script","Loaded by the page"].contains(ref.role) && !["html","htm","php","asp"].contains(ref.url.pathExtension.lowercased()) {
                        record.issues.append(.init(url:ref.url,reason:"The server returned a web page instead of this asset.",evidence:ref.role)); continue
                    }
                    let path = try store(download)
                    guard depth < 5, download.bytes < 64 * 1024 * 1024 else { continue }
                    let ext = download.url.pathExtension.lowercased(), data = try Data(contentsOf:download.file)
                    var refs: [URL] = []
                    if download.mimeType == "text/html" || ["html","htm"].contains(ext) {
                        let page = WebPage.parse(WebPage.text(data),url:download.url)
                        record.documentBases[path] = page.base
                        queue += page.resources.map { ($0,depth + 1) }
                    } else if ["css","js","mjs","json","xml","txt","ini","cfg","fnt"].contains(ext) || download.mimeType.contains("javascript") || download.mimeType == "text/css" {
                        let base = candidate.kind != "html" ? gameBase : (["js","mjs"].contains(ext) ? (context?.base ?? main.url) : download.url)
                        refs = WebPage.references(in:WebPage.text(data),from:base,css:ext == "css",json:ext == "json")
                        if ["js","mjs"].contains(ext) {
                            let documentRelative = Set(WebPage.moduleReferences(in:WebPage.text(data),from:base))
                            refs.removeAll { documentRelative.contains($0) }
                            refs += WebPage.moduleReferences(in:WebPage.text(data),from:download.url)
                            let folders = WebPage.assetDirectories(in:WebPage.text(data),from:base)
                            queue += try await directoryReferences(folders,referer:candidate.pageURL,seen:&seenDirectories).map { ($0,depth + 1) }
                        }
                    } else if ["swf","dcr","dir","dxr","cct","cst"].contains(ext) { refs = WebPage.binaryReferences(data,from:gameBase) }
                    if candidate.kind != "html", !refs.isEmpty {
                        queue += try await directoryReferences(refs.map(Self.assetDirectory),referer:candidate.pageURL,seen:&seenDirectories).map { ($0,depth + 1) }
                    }
                    queue += refs.prefix(500).map { (WebReference(url:$0,role:ext == "swf" ? "Possible game asset" : "Asset reference"),depth + 1) }
                }
            }
            progress(WebProgress(message:"Recovering game files…",detail:queue.isEmpty ? "Finishing the recovery report" : "Checking \(queue.count) references",files:record.files.count,bytes:record.bytes))
        }
        if !queue.isEmpty { record.issues.append(.init(url:candidate.url,reason:"Stopped at the 5,000-file limit.",evidence:"Recovery limit")) }
        record.issues += issues
        record.files.sort { $0.path < $1.path }
        // Preserve launch-setting identity without changing any downloaded game bytes.
        if !record.parameters.isEmpty || record.baseURL != nil {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            struct Launch: Encodable { let baseURL: URL?; let parameters: [String:String] }
            let settings = Launch(baseURL:record.baseURL,parameters:record.parameters)
            try encoder.encode(settings).write(to:payload.appendingPathComponent("Flashback-launch.json"))
        }
        return WebRecovery(source:payload,entry:mainPath,record:record)
    }
}
