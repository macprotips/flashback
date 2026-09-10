// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit
import Compression

struct WebCandidate: Identifiable, Hashable, Sendable {
    var id: String { url.absoluteString }
    let url: URL
    var pageURL: URL
    var title: String
    var kind: String
    var evidence: String
    var score: Int
    var parameters: [String:String] = [:]
    var companions: [URL] = []
    var baseURL: URL? = nil
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct WebReference: Hashable, Sendable {
    let url: URL
    let role: String
}

struct WebPage: Sendable {
    var url: URL
    var base: URL
    var title: String
    var candidates: [WebCandidate] = []
    var frames: [URL] = []
    var scripts: [URL] = []
    var resources: [WebReference] = []
    var isDirectory = false
    var folders: [URL] = []

    static let games = Set(["swf","dcr","dir","dxr","jar","zip"])
    static let assets = games.union(["cct","cst","txt","xml","json","ini","cfg","csv","dat","bin","pak","pck","atlas","plist",
        "png","jpg","jpeg","gif","webp","svg","bmp","ico","mp3","wav","ogg","oga","m4a","mp4","webm","flv","swv","swa",
        "js","mjs","css","wasm","data","unityweb","woff","woff2","ttf","otf","fnt"])

    static func gameExtension(url: URL, mime: String = "", filename: String? = nil) -> String? {
        let ext = url.pathExtension.lowercased()
        if games.contains(ext) { return ext }
        if let name = filename, games.contains((name as NSString).pathExtension.lowercased()) { return (name as NSString).pathExtension.lowercased() }
        return ["application/x-shockwave-flash":"swf", "application/x-director":"dcr", "application/java-archive":"jar",
                "application/x-java-archive":"jar", "application/zip":"zip", "application/x-zip-compressed":"zip"][mime.lowercased()]
    }

    static func text(_ data: Data) -> String {
        String(data:data,encoding:.utf8) ?? String(data:data,encoding:.windowsCP1252) ?? String(decoding:data,as:UTF8.self)
    }

    static func matches(_ pattern: String, _ text: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern:pattern,options:options) else { return [] }
        let text = text as NSString
        var result: [[String]] = []
        regex.enumerateMatches(in:text as String,range:NSRange(location:0,length:text.length)) { match, _, stop in
            guard let match else { return }
            result.append((0..<match.numberOfRanges).map { match.range(at:$0).location == NSNotFound ? "" : text.substring(with:match.range(at:$0)) })
            if result.count >= 10000 { stop.pointee = true }
        }
        return result
    }

    static func parse(_ html: String, url: URL) -> WebPage {
        var page = WebPage(url:url,base:url,title:url.deletingPathExtension().lastPathComponent)
        // Foundation's system HTML parser tolerates legacy markup; external
        // entities stay disabled. No site JavaScript executes in this pass.
        let document = try? XMLDocument(xmlString:html,options:[.documentTidyHTML,.nodeLoadExternalEntitiesNever])
        if let value = try? document?.nodes(forXPath:"//title").first?.stringValue,
           !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { page.title = String(value.trimmingCharacters(in:.whitespacesAndNewlines).prefix(120)) }
        if let base = try? document?.nodes(forXPath:"//base[@href]").first as? XMLElement,
           let href = base.attribute(forName:"href")?.stringValue, let resolved = WebAddress.resolve(href,from:url) { page.base = resolved }
        page.isDirectory = page.title.lowercased().hasPrefix("index of ") || html.contains("Parent Directory</a>")
        func attr(_ node: XMLElement, _ name: String) -> String? { node.attribute(forName:name)?.stringValue }
        func add(_ raw: String?, role: String, base: URL? = nil) {
            guard let raw, let link = WebAddress.resolve(raw,from:base ?? page.base) else { return }
            if !page.resources.contains(where:{ $0.url == link }) { page.resources.append(WebReference(url:link,role:role)) }
        }
        func candidate(_ raw: String?, node: XMLElement, evidence: String, score: Int, base: URL? = nil, hint: String? = nil) {
            let classID = (attr(node,"classid") ?? "").lowercased()
            let pluginType = classID.contains("d27cdb6e") ? "application/x-shockwave-flash" :
                (["166b1bca-3f9c-11cf-8075-444553540000","7fd1d18d-7787-11d2-b3f7-00600832b7c6"].contains(where:classID.contains) ? "application/x-director" : "")
            guard let raw, let link = WebAddress.resolve(raw,from:base ?? page.base),
                  let kind = gameExtension(url:link,mime:attr(node,"type") ?? pluginType,filename:hint), !link.lastPathComponent.lowercased().contains("expressinstall") else { return }
            var params = queryParameters(link)
            if ["dcr","dir","dxr"].contains(kind) {
                // Director exposes plug-in settings through externalParamValue().
                let layout: Set<String> = ["src","data","width","height","type","classid","codebase","pluginspage","name","align","hspace","vspace","border","class","id","style","title","tabindex","hidden","role"]
                for attribute in node.attributes ?? [] {
                    guard let name = attribute.name, let value = attribute.stringValue else { continue }
                    let lower = name.lowercased()
                    if lower.hasPrefix("data-sw-"), name.count > 8 { params[String(name.dropFirst(8))] = value }
                    else if !layout.contains(lower), !lower.hasPrefix("data-"), !lower.hasPrefix("on") { params[name] = value }
                }
                for case let child as XMLElement in (try? node.nodes(forXPath:"./param")) ?? [] {
                    if let name = attr(child,"name"), let value = attr(child,"value"), !["src","movie","filename"].contains(name.lowercased()) { params[name] = value }
                }
            }
            let documentDirectory = page.base.hasDirectoryPath ? page.base : page.base.deletingLastPathComponent()
            var launchBase = attr(node,"base").flatMap { WebAddress.resolve($0,from:page.base) }.map(WebAddress.directory) ?? documentDirectory
            if let flashvars = attr(node,"flashvars") { params.merge(queryParameters(flashvars)) { _, new in new } }
            if let children = try? node.nodes(forXPath:".//param") {
                for case let child as XMLElement in children {
                    if attr(child,"name")?.lowercased() == "flashvars", let value = attr(child,"value") {
                        params.merge(queryParameters(value)) { _, new in new }
                    }
                    if attr(child,"name")?.lowercased() == "base", let value = attr(child,"value"), let resolved = WebAddress.resolve(value,from:page.base) { launchBase = WebAddress.directory(resolved) }
                }
            }
            let item = WebCandidate(url:link,pageURL:url,title:page.title,kind:kind,evidence:evidence,score:score,parameters:params,baseURL:kind == "swf" && score == 100 ? launchBase : nil)
            page.merge(item)
        }
        if let nodes = try? document?.nodes(forXPath:"//*") {
            for case let node as XMLElement in nodes {
                let tag = node.name?.lowercased() ?? ""
                switch tag {
                case "object", "embed":
                    candidate(attr(node,"data") ?? attr(node,"src"),node:node,evidence:"Embedded game",score:100)
                    add(attr(node,"data") ?? attr(node,"src"),role:"embedded")
                    for case let child as XMLElement in (try? node.nodes(forXPath:"./param")) ?? [] {
                        if ["movie","src","filename"].contains(attr(child,"name")?.lowercased() ?? "") {
                            candidate(attr(child,"value"),node:node,evidence:"Embedded game",score:100)
                            add(attr(child,"value"),role:"embedded")
                        }
                    }
                case "applet":
                    let base = attr(node,"codebase").flatMap { WebAddress.resolve($0.hasSuffix("/") ? $0 : $0 + "/",from:page.base) } ?? page.base
                    let jars = (attr(node,"archive") ?? "").split(separator:",").compactMap { WebAddress.resolve(String($0).trimmingCharacters(in:.whitespaces),from:base) }
                    for jar in jars { candidate(jar.absoluteString,node:node,evidence:"Java archive — must support standalone launch",score:85) }
                    for index in page.candidates.indices where jars.contains(page.candidates[index].url) { page.candidates[index].companions = jars.filter { $0 != page.candidates[index].url } }
                case "a":
                    let href = attr(node,"href")
                    candidate(href,node:node,evidence:"Download link",score:65,hint:attr(node,"download"))
                    if page.isDirectory, let href, let link = WebAddress.resolve(href,from:page.base), link != url,
                       link.host == url.host, link.path.hasPrefix(url.path == "/" ? "/" : url.path + "/"), !href.hasPrefix("?"), !href.hasPrefix("..") {
                        if link.hasDirectoryPath { page.folders.append(link) }
                        else if assets.contains(link.pathExtension.lowercased()) { add(href,role:"listed file") }
                    }
                    if let href, let link = WebAddress.resolve(href,from:page.base),
                       ["html","htm","php","asp","aspx"].contains(link.pathExtension.lowercased()),
                       matches(#"\b(play|launch|start game|download game)\b"#,node.stringValue ?? "").count > 0 {
                        page.frames.append(link)
                    }
                case "iframe", "frame":
                    if let src = attr(node,"src"), let frame = WebAddress.resolve(src,from:page.base) { page.frames.append(frame); add(src,role:"frame") }
                case "script":
                    if let src = attr(node,"src"), let link = WebAddress.resolve(src,from:page.base) { page.scripts.append(link); add(src,role:"script") }
                    else { page.addScript(node.stringValue ?? "") }
                case "link":
                    if ["stylesheet","preload","modulepreload"].contains(attr(node,"rel")?.lowercased() ?? "") { add(attr(node,"href"),role:attr(node,"rel")?.lowercased() == "stylesheet" ? "stylesheet" : "asset") }
                case "img", "audio", "video", "source", "track", "input":
                    add(attr(node,"src"),role:"asset"); add(attr(node,"poster"),role:"asset")
                    for part in (attr(node,"srcset") ?? "").split(separator:",") {
                        add(part.split(whereSeparator: { $0.isWhitespace }).first.map(String.init),role:"asset")
                    }
                default: break
                }
            }
        }
        // Some legacy scripts are not retained by the HTML repair parser.
        for match in matches(#"<script\b[^>]*>([\s\S]*?)</script\s*>"#,html) { page.addScript(match[1]) }
        if matches(#"<canvas\b|new\s+Phaser\.Game\b|cr_createRuntime\s*\("#,html).count > 0 && page.candidates.isEmpty {
            page.merge(WebCandidate(url:url,pageURL:url,title:page.title,kind:"html",evidence:"HTML game page",score:75))
        }
        return page
    }

    mutating func merge(_ item: WebCandidate) {
        if let index = candidates.firstIndex(where:{ $0.url == item.url }) {
            var merged = candidates[index]
            if item.score > merged.score { merged.evidence = item.evidence; merged.score = item.score; merged.pageURL = item.pageURL; merged.title = item.title }
            merged.parameters.merge(item.parameters) { old, _ in old }
            merged.companions = Array(Set(merged.companions + item.companions))
            if merged.baseURL == nil { merged.baseURL = item.baseURL }
            candidates[index] = merged
        } else { candidates.append(item) }
    }

    mutating func addScript(_ script: String) {
        let literals = Self.stringLiterals(script)
        let modules = Set(Self.moduleReferences(in:script,from:base))
        let documentDirectory = base.hasDirectoryPath ? base : base.deletingLastPathComponent()
        folders += Self.assetDirectories(in:script,from:base)
        folders = Array(Set(folders)).sorted { $0.absoluteString < $1.absoluteString }
        var variables: [String:String] = [:]
        for match in Self.matches(#"(?:var|let|const)\s+([\w$]+)\s*=\s*(['"])(.*?)\2"#,script) { variables[match[1]] = Self.unescape(match[3]) }
        func value(_ expression: String) -> String? {
            let parts = expression.split(separator:"+").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
            let resolved = parts.compactMap { part -> String? in
                if let literal = Self.stringLiterals(part).first, part.first == "\"" || part.first == "'" { return literal }
                return variables[part]
            }
            return resolved.count == parts.count ? resolved.joined() : nil
        }
        var primary = Set<URL>()
        for call in Self.matches(#"(?:embedSWF|SWFObject|FlashObject)\s*\(\s*([^,\n]+)"#,script) {
            if let path = value(call[1]), let link = WebAddress.resolve(path,from:base) {
                primary.insert(link)
                merge(WebCandidate(url:link,pageURL:url,title:title,kind:Self.gameExtension(url:link) ?? "swf",evidence:"Game loader",score:98,parameters:Self.queryParameters(link),baseURL:documentDirectory))
            }
        }
        for call in Self.matches(#"['"](?:movie|src)['"]\s*,\s*(['"])(.*?)\1"#,script) {
            var path = Self.unescape(call[2])
            if (path as NSString).pathExtension.isEmpty && script.contains("AC_FL_RunContent") { path += ".swf" }
            if let link = WebAddress.resolve(path,from:base), let kind = Self.gameExtension(url:link) {
                primary.insert(link)
                merge(WebCandidate(url:link,pageURL:url,title:title,kind:kind,evidence:"Game loader",score:97,parameters:Self.queryParameters(link),baseURL:documentDirectory))
            }
        }
        var parameters: [String:String] = [:]
        for match in Self.matches(#"flashvars\.([\w]+)\s*=\s*(['"])(.*?)\2"#,script) { parameters[match[1]] = Self.unescape(match[3]) }
        for object in Self.matches(#"(?:flashvars)\s*=\s*\{([^}]{0,32768})\}"#,script) {
            for match in Self.matches(#"['"]?([\w]+)['"]?\s*:\s*(['"])(.*?)\2"#,object[1]) { parameters[match[1]] = Self.unescape(match[3]) }
        }
        for index in candidates.indices where primary.contains(candidates[index].url) {
            candidates[index].parameters.merge(parameters) { old, _ in old }
            if let match = Self.matches(#"params\.base\s*=\s*(['"])(.*?)\1"#,script).first,
               let explicit = WebAddress.resolve(Self.unescape(match[2]),from:base) { candidates[index].baseURL = WebAddress.directory(explicit) }
        }
        for literal in literals {
            guard let link = WebAddress.resolve(literal,from:base) else { continue }
            let ext = link.pathExtension.lowercased()
            if Self.assets.contains(ext) && !modules.contains(link) { resources.append(WebReference(url:link,role:"Possible script asset")) }
            if let kind = Self.gameExtension(url:link), !link.lastPathComponent.lowercased().contains("expressinstall") {
                merge(WebCandidate(url:link,pageURL:url,title:title,kind:kind,evidence:"Referenced in a script",score:40,parameters:Self.queryParameters(link)))
            }
        }
        resources = Array(Set(resources))
    }

    static func queryParameters(_ url: URL) -> [String:String] { queryParameters(url.query ?? "") }
    static func queryParameters(_ value: String) -> [String:String] {
        var result: [String:String] = [:]
        for item in value.prefix(65536).split(separator:"&") {
            let pair = item.split(separator:"=",maxSplits:1,omittingEmptySubsequences:false)
            func decode(_ value: Substring) -> String { let text = value.replacingOccurrences(of:"+",with:" "); return text.removingPercentEncoding ?? text }
            let key = decode(pair[0])
            if !key.isEmpty && key.count <= 256 { result[key] = pair.count == 2 ? String(decode(pair[1]).prefix(8192)) : "" }
        }
        return result
    }

    static func unescape(_ text: String) -> String {
        var result = text.replacingOccurrences(of:"\\/",with:"/").replacingOccurrences(of:"\\'",with:"'").replacingOccurrences(of:"\\\"",with:"\"")
        for match in matches(#"\\(?:u([0-9a-f]{4})|x([0-9a-f]{2}))"#,result) {
            if let code = UInt32(match[1].isEmpty ? match[2] : match[1],radix:16), let scalar = UnicodeScalar(code) { result = result.replacingOccurrences(of:match[0],with:String(scalar)) }
        }
        return result
    }

    static func stringLiterals(_ text: String, valuesOnly: Bool = false) -> [String] {
        matches(#"(?:"((?:\\.|[^"\\\r\n]){1,8192})"|'((?:\\.|[^'\\\r\n]){1,8192})')\s*(:?)"#,text)
            .filter { !valuesOnly || $0[3].isEmpty }.map { unescape($0[1].isEmpty ? $0[2] : $0[1]) }
    }

    static func assetDirectories(in text: String, from base: URL) -> [URL] {
        var values = stringLiterals(text).filter { $0.hasSuffix("/") && $0.count < 512 && $0.contains(where:{ $0.isLetter }) }
        values += matches(#"\b[\w$]*(?:path|directory|folder|prefix)[\w$]*['"]?\s*[:=]\s*(['"])([A-Za-z0-9_./:%~@+\-]{1,256})\1"#,text).map { $0[2] }
        return Array(Set(values.compactMap { value in
            guard !value.contains(where:{ $0.isWhitespace }), let url = WebAddress.resolve(value,from:base),
                  !assets.contains(url.pathExtension.lowercased()), !url.path.isEmpty, url.path != "/" else { return nil }
            return WebAddress.resolve(value.hasSuffix("/") ? value : value + "/",from:base)
        })).sorted { $0.absoluteString < $1.absoluteString }
    }

    static func references(in text: String, from base: URL, css: Bool = false, json: Bool = false) -> [URL] {
        if json, let data = text.data(using:.utf8), let object = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
           object["frames"] != nil, let meta = object["meta"] as? [String:Any], let atlas = meta["image"] as? String {
            // TexturePacker frame names are regions inside the atlas, not files.
            return ([atlas] + (meta["related_multi_packs"] as? [String] ?? [])).compactMap { WebAddress.resolve($0,from:base) }
        }
        var values = stringLiterals(text,valuesOnly:json)
        if css { values += matches(#"url\(\s*['"]?([^'"\)\s]+)"#,text).map { $0[1] } }
        let explicit = matches(#"(?:fetch|loadJSON|loadXML|loadImage|loadSound)\s*\(\s*(['"])([^'"\r\n]{1,8192})\1"#,text).compactMap { WebAddress.resolve($0[2],from:base) }
        return Array(Set(values.compactMap { value in
            guard let link = WebAddress.resolve(value,from:base), assets.contains(link.pathExtension.lowercased()) else { return nil }
            return link
        } + explicit))
    }

    static func moduleReferences(in text: String, from base: URL) -> [URL] {
        matches(#"(?:\bfrom\s*|\bimport\s*(?:\(\s*)?)(['"])([^'"\r\n]+)\1"#,text).compactMap {
            let raw = $0[2]
            guard raw.hasPrefix(".") || raw.hasPrefix("/") || raw.hasPrefix("http") else { return nil }
            return WebAddress.resolve(raw,from:base)
        }
    }

    static func binaryReferences(_ data: Data, from base: URL) -> [URL] {
        var bytes = data
        if data.count > 8 && String(decoding:data.prefix(3),as:UTF8.self) == "CWS" {
            let length = (0..<4).reduce(0) { $0 | Int(data[4 + $1]) << ($1 * 8) }
            if length > 8 && length <= 64 * 1024 * 1024 {
                var output = [UInt8](repeating:0,count:length - 8)
                let source = [UInt8](data.dropFirst(8))
                // Apple's decoder consumes raw DEFLATE; SWF wraps it in zlib.
                let raw = Array(source.dropFirst(2))
                let count = compression_decode_buffer(&output,output.count,raw,raw.count,nil,COMPRESSION_ZLIB)
                if count > 0 { bytes = Data(output.prefix(count)) }
            }
        }
        // Literal filenames in ActionScript/Director bytecode are useful leads;
        // computed, encrypted, or LZMA-compressed names may remain undiscoverable.
        let text = String(decoding:bytes.prefix(64 * 1024 * 1024).map { (32...126).contains($0) ? $0 : 10 },as:UTF8.self)
        let extensions = assets.sorted().joined(separator:"|")
        let pattern = #"(?:https?://)?[A-Za-z0-9_./%~@+\-]+\.(?:"# + extensions + #")(?:\?[^\s\x00'"<>]*)?"#
        return Array(Set(matches(pattern,text).compactMap { WebAddress.resolve($0[0],from:base) })).sorted { $0.absoluteString < $1.absoluteString }
    }
}
