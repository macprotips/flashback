// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct DirectorLaunch: Codable, Sendable {
    let gameID: String
    let directory: String
    static func read(_ url: URL) throws -> Self {
        let data = try Data(contentsOf:url)
        guard data.count <= 16_384 else { throw LibraryError("The Director launch file is too large.") }
        let item = try JSONDecoder().decode(Self.self,from:data)
        guard item.gameID.range(of:#"^director:[a-zA-Z0-9_-]+$"#,options:.regularExpression) != nil,
              item.directory == "." || (try? GameLibrary.contained(item.directory,in:url.deletingLastPathComponent())) != nil else {
            throw LibraryError("This Director launch file has invalid game or folder settings.")
        }
        return item
    }
}

/// Launch trusted tools without a shell, bound their lifetime, and avoid pipe backpressure.
struct ToolResult {
    let status: Int32
    let text: String
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 15,
                    directory: URL? = nil) throws -> Self {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("Flashback-tool-" + UUID().uuidString)
        FileManager.default.createFile(atPath:log.path,contents:nil)
        defer { try? FileManager.default.removeItem(at:log) }
        let output = try FileHandle(forWritingTo:log)
        defer { try? output.close() }
        let child = Process(), ended = DispatchSemaphore(value:0)
        child.executableURL = executable; child.arguments = arguments; child.currentDirectoryURL = directory
        child.environment = ["PATH":"/usr/bin:/bin", "LANG":"en_US.UTF-8", "HOME":FileManager.default.temporaryDirectory.path]
        let keepAlive = Pipe()
        child.standardOutput = output; child.standardError = output; child.standardInput = keepAlive
        defer { try? keepAlive.fileHandleForWriting.close() }
        child.terminationHandler = { _ in ended.signal() }
        try child.run()
        if ended.wait(timeout:.now() + timeout) == .timedOut {
            child.terminate()
            if ended.wait(timeout:.now() + 2) == .timedOut { kill(child.processIdentifier,SIGKILL); _ = ended.wait(timeout:.now() + 2) }
            throw LibraryError("The game inspection took too long. Check that you selected the game's own folder.")
        }
        let reader = try FileHandle(forReadingFrom:log); defer { try? reader.close() }
        return Self(status:child.terminationStatus,text:String(decoding:try reader.read(upToCount:1_048_576) ?? Data(),as:UTF8.self))
    }
}

struct LegacyImport {
    static let extensions: Set<String> = ["swf","jar","jnlp","html","htm","dcr","dir","dxr","exe","com","bat","scummvm"]

    // Projector trailer: marker FA123456, then the stored SWF byte count, both LE.
    // Require the exact trailer and SWF header; never scan arbitrary executable bytes for a guess.
    static func flashProjector(in data: Data) -> Range<Int>? {
        guard data.count >= 24, data.starts(with:[0x4d,0x5a]),
              data.suffix(8).prefix(4) == Data([0x56,0x34,0x12,0xfa]) else { return nil }
        let end = data.count - 8
        let count = (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[end + 4 + $1]) << (8 * $1) }
        guard count >= 8, count <= 512 * 1024 * 1024, Int(count) <= end - 2 else { return nil }
        let start = end - Int(count)
        guard ["FWS","CWS","ZWS"].contains(String(decoding:data[start..<(start + 3)],as:UTF8.self)), data[start + 3] > 0 else { return nil }
        let declared = (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[start + 4 + $1]) << (8 * $1) }
        guard declared >= 8, declared <= 512 * 1024 * 1024 else { return nil }
        if data[start] == 70 && declared != count { return nil }
        return start..<end
    }

    static func isDOS(_ file: URL) throws -> Bool {
        let size = try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        let ext = file.pathExtension.lowercased()
        if ext == "bat" { return size > 0 && size <= 1_048_576 }
        if ext == "com" { return size > 0 && size <= 65_280 }
        guard ext == "exe", size >= 28, size <= 64 * 1024 * 1024 else { return false }
        let handle = try FileHandle(forReadingFrom:file); defer { try? handle.close() }
        let header = try handle.read(upToCount:64) ?? Data()
        guard header.starts(with:[0x4d,0x5a]) else { return false }
        if header.count >= 64 {
            let offset = (0..<4).reduce(UInt32(0)) { $0 | UInt32(header[60 + $1]) << (8 * $1) }
            if offset >= 64 && Int(offset) <= size - 2 {
                try handle.seek(toOffset:UInt64(offset))
                let signature = try handle.read(upToCount:4) ?? Data()
                if signature.starts(with:[0x50,0x45]) || ["NE","LE","LX"].contains(String(decoding:signature.prefix(2),as:UTF8.self)) { return false }
            }
        }
        return true
    }

    static func jnlpDocument(_ file: URL) throws -> XMLDocument {
        let data = try Data(contentsOf:file)
        guard data.count <= 2 * 1024 * 1024 else { throw LibraryError("The Java launch descriptor is too large.") }
        let text = String(decoding:data,as:UTF8.self)
        guard !text.localizedCaseInsensitiveContains("<!DOCTYPE"), !text.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw LibraryError("Java launch descriptors cannot contain external entities or document types.")
        }
        let document = try XMLDocument(data:data,options:[.nodeLoadExternalEntitiesNever])
        guard document.rootElement()?.name == "jnlp" else { throw LibraryError("Choose a valid JNLP game descriptor.") }
        return document
    }

    static func prepare(_ input: URL, library: GameLibrary, resources: URL) throws -> ImportPlan {
        let initial = try library.inspect(input,allowEmpty:true)
        let base = initial.isFolder ? initial.source : initial.source.deletingLastPathComponent()
        let needsTransform = initial.files.contains { ["exe","html","htm","jnlp"].contains(($0 as NSString).pathExtension.lowercased()) }
        let detected = initial.isFolder ? try detectDirector(in:base,resources:resources) : []
        if !needsTransform && detected.isEmpty {
            guard !initial.movies.isEmpty else { throw LibraryError("No supported game was detected. Add the complete game data folder.") }
            return initial
        }
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("Flashback-legacy-" + UUID().uuidString)
        let source = temp.appendingPathComponent("Game")
        try fm.createDirectory(at:source,withIntermediateDirectories:true)
        do {
            var files = Set(initial.files)
            // A standalone descriptor/page gets its explicitly named local Java files,
            // never an indiscriminate copy of its containing Downloads folder.
            if !initial.isFolder {
                for relative in try companionFiles(input,root:base) { files.insert(relative) }
            }
            var bytes: Int64 = 0
            for relative in files.sorted() {
                let original = try GameLibrary.contained(relative,in:base)
                let info = try original.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true else { throw LibraryError("A Java companion file is missing or is a symbolic link. Add the complete game folder.") }
                bytes += Int64(info.fileSize ?? 0)
                guard bytes <= 1_073_741_824, files.count <= 10_000 else { throw LibraryError("This game exceeds the import size limit.") }
                let target = try GameLibrary.contained(relative,in:source)
                try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                try fm.copyItem(at:original,to:target)
            }
            try GameLibrary.recoverProjectorMovies(in:source)
            try normalize(in:source,resources:resources,detected:detected)
            var plan = try library.inspect(source)
            plan.movies = try entries(plan.movies,in:source)
            guard !plan.movies.isEmpty else { throw LibraryError("No supported game was found. This may be a Windows application rather than a DOS game or Flash projector.") }
            plan.temporaryDirectory = temp
            plan.suggestedTitle = (initial.isFolder ? input : input.deletingPathExtension()).lastPathComponent
            return plan
        } catch { try? fm.removeItem(at:temp); throw LibraryError("Couldn’t prepare \(input.lastPathComponent): \(error.localizedDescription)") }
    }

    static func localReference(_ raw: String, relativeTo file: URL, root: URL, remoteBase: URL? = nil) throws -> URL {
        let value = raw.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\\") else { throw LibraryError("A Java resource has an invalid path: \(raw)") }
        var path = value
        if let url = URL(string:value), url.scheme != nil {
            guard let base = remoteBase, url.scheme == base.scheme, url.host == base.host,
                  url.port == base.port, url.path.hasPrefix(base.path) else { throw LibraryError("A Java resource is outside the local game. Recover the descriptor from its website or include local relative resources.") }
            path = String(url.path.dropFirst(base.path.count))
        } else {
            guard let components = URLComponents(string:value), components.query == nil, components.fragment == nil,
                  let decoded = components.percentEncodedPath.removingPercentEncoding else { throw LibraryError("A Java resource path is invalid.") }
            path = decoded
        }
        guard !path.hasPrefix("/"), !path.contains("\\") else { throw LibraryError("A Java resource must be relative to its game folder.") }
        let parent = file.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let target = parent.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard target.path == canonicalRoot.path || target.path.hasPrefix(canonicalRoot.path + "/") else { throw LibraryError("A Java resource points outside its game folder.") }
        return target
    }

    static func pathURL(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters:CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn:"?#%")))!
    }

    static func relativePath(from base: URL, to target: URL) -> String {
        let source = base.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let destination = target.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        var common = 0
        while common < min(source.count,destination.count), source[common] == destination[common] { common += 1 }
        let parts = Array(repeating:"..",count:source.count - common) + destination.dropFirst(common)
        return parts.isEmpty ? "." : parts.joined(separator:"/")
    }

    static func companionFiles(_ file: URL, root: URL) throws -> [String] {
        var references: [String] = []
        var remote: URL?
        var referenceFile = file
        if file.pathExtension.lowercased() == "jnlp" {
            let doc = try jnlpDocument(file)
            remote = doc.rootElement()?.attribute(forName:"codebase")?.stringValue.flatMap(URL.init(string:)).map { $0.hasDirectoryPath ? $0 : $0.appendingPathComponent("") }
            if let raw = doc.rootElement()?.attribute(forName:"codebase")?.stringValue, remote?.scheme == nil, !raw.isEmpty {
                referenceFile = try localReference(raw,relativeTo:file,root:root).appendingPathComponent("descriptor.jnlp")
            }
            references = ((try? doc.nodes(forXPath:"//resources/jar/@href")) ?? []).compactMap(\.stringValue)
        } else if ["html","htm"].contains(file.pathExtension.lowercased()) {
            for applet in try applets(file) { references += applet.archives.map { applet.codebase + $0 }; if applet.archives.isEmpty { references.append(applet.codebase + applet.code.replacingOccurrences(of:".",with:"/") + ".class") } }
        }
        return try references.map {
            let url = try localReference($0,relativeTo:referenceFile,root:root,remoteBase:remote)
            return String(url.path.dropFirst(root.standardizedFileURL.resolvingSymlinksInPath().path.count + 1))
        }
    }

    struct Applet {
        var code: String; var name: String; var width: Int; var height: Int
        var codebase: String; var archives: [String]; var parameters: [String:String]
    }
    static func applets(_ file: URL) throws -> [Applet] {
        let data = try Data(contentsOf:file)
        guard data.count <= 2 * 1024 * 1024 else { return [] }
        let doc = try XMLDocument(data:data,options:[.documentTidyHTML,.nodeLoadExternalEntitiesNever])
        var result: [Applet] = []
        for case let node as XMLElement in (try? doc.nodes(forXPath:"//applet|//object|//embed")) ?? [] {
            func attr(_ name: String) -> String? { node.attribute(forName:name)?.stringValue }
            var params: [String:String] = [:]
            for case let param as XMLElement in (try? node.nodes(forXPath:"./param")) ?? [] {
                if let key = param.attribute(forName:"name")?.stringValue, let value = param.attribute(forName:"value")?.stringValue { params[key] = value }
            }
            func setting(_ name: String) -> String? { attr(name) ?? params.first { $0.key.lowercased() == name }?.value }
            guard node.name?.lowercased() == "applet" || (attr("type") ?? "").lowercased().contains("java") || (attr("classid") ?? "").lowercased().hasPrefix("java:") else { continue }
            guard var code = setting("code") ?? attr("classid")?.replacingOccurrences(of:"java:",with:"") else { throw LibraryError("The applet page is missing its Java class name.") }
            if code.hasSuffix(".class") { code = String(code.dropLast(6)) }
            code = code.replacingOccurrences(of:"/",with:".")
            guard code.range(of:#"^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*$"#,options:.regularExpression) != nil else { throw LibraryError("The applet class name is invalid.") }
            let width = Int(setting("width") ?? "640"), height = Int(setting("height") ?? "480")
            guard let width, let height, (1...4096).contains(width), (1...4096).contains(height) else { throw LibraryError("The applet dimensions must be between 1 and 4096 pixels.") }
            var base = setting("codebase") ?? ""
            if base == "." || base == "./" { base = "" }
            if !base.isEmpty && !base.hasSuffix("/") { base += "/" }
            let jars = (setting("archive") ?? "").split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
            result.append(Applet(code:code,name:attr("name") ?? file.deletingPathExtension().lastPathComponent,width:width,height:height,codebase:base,archives:jars,parameters:params))
        }
        return result
    }

    static func normalize(in root: URL, resources: URL, detected: [String]? = nil) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath:root.appendingPathComponent("Flashback-launch.jnlp").path) {
            _ = try jnlpDocument(root.appendingPathComponent("Flashback-launch.jnlp"))
            return
        }
        let files = (fm.enumerator(at:root,includingPropertiesForKeys:[.isRegularFileKey],options:[.skipsHiddenFiles,.skipsPackageDescendants])?.allObjects as? [URL] ?? []).sorted { $0.path < $1.path }
        for file in files where ["html","htm"].contains(file.pathExtension.lowercased()) {
            for (index, applet) in try applets(file).enumerated() {
                let doc = XMLDocument(rootElement:XMLElement(name:"jnlp"))
                let element = doc.rootElement()!
                let resourcesNode = XMLElement(name:"resources"); element.addChild(resourcesNode)
                let base = try (applet.codebase.isEmpty ? file.deletingLastPathComponent() : localReference(applet.codebase,relativeTo:file,root:root)).standardizedFileURL.resolvingSymlinksInPath()
                if !applet.codebase.isEmpty { element.addAttribute(XMLNode.attribute(withName:"codebase",stringValue:pathURL(applet.codebase.removingPercentEncoding ?? applet.codebase)) as! XMLNode) }
                for archive in applet.archives {
                    let local = try localReference(applet.codebase + archive,relativeTo:file,root:root)
                    guard fm.fileExists(atPath:local.path) else { throw LibraryError("The applet archive \(archive) is missing. Add its complete folder.") }
                    let jar = XMLElement(name:"jar"); jar.addAttribute(XMLNode.attribute(withName:"href",stringValue:pathURL(relativePath(from:base,to:local))) as! XMLNode); resourcesNode.addChild(jar)
                }
                let launch = XMLElement(name:"applet-desc")
                for (key,value) in ["main-class":applet.code,"name":applet.name,"width":String(applet.width),"height":String(applet.height)] { launch.addAttribute(XMLNode.attribute(withName:key,stringValue:value) as! XMLNode) }
                // A local codebase supports loose .class trees. JAR applets use the page directory for assets.
                if applet.archives.isEmpty {
                    let classFile = base.appendingPathComponent(applet.code.replacingOccurrences(of:".",with:"/") + ".class")
                    guard fm.fileExists(atPath:classFile.path) else { throw LibraryError("The applet class file is missing. Add its complete folder.") }
                }
                for (key,value) in applet.parameters.sorted(by:{ $0.key < $1.key }) {
                    let param = XMLElement(name:"param"); param.addAttribute(XMLNode.attribute(withName:"name",stringValue:key) as! XMLNode); param.addAttribute(XMLNode.attribute(withName:"value",stringValue:value) as! XMLNode); launch.addChild(param)
                }
                element.addChild(launch)
                let target = file.deletingPathExtension().appendingPathExtension("flashback-applet-\(index + 1).jnlp")
                let data = doc.xmlData(options:[.nodePrettyPrint])
                if fm.fileExists(atPath:target.path) { guard try Data(contentsOf:target) == data else { throw LibraryError("An applet launch file conflicts with the generated settings.") } }
                else { try data.write(to:target,options:.withoutOverwriting) }
            }
        }
        // Remove historical remote codebases only when every referenced JAR is present locally.
        for file in files where file.pathExtension.lowercased() == "jnlp" {
            let doc = try jnlpDocument(file)
            guard let element = doc.rootElement() else { continue }
            let remote = element.attribute(forName:"codebase")?.stringValue.flatMap(URL.init(string:))
            if let remote, remote.scheme != nil {
                let base = remote.hasDirectoryPath ? remote : remote.appendingPathComponent("")
                for attr in (try? doc.nodes(forXPath:"//resources/jar/@href")) ?? [] {
                    guard let raw = attr.stringValue else { continue }
                    let local = try localReference(raw,relativeTo:file,root:root,remoteBase:base)
                    guard fm.fileExists(atPath:local.path) else { throw LibraryError("A JNLP archive is missing. Recover it from the website or add the complete game folder.") }
                    let parent = file.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path + "/"
                    attr.stringValue = String(local.path.dropFirst(parent.count)).addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)
                }
                element.removeAttribute(forName:"codebase"); element.removeAttribute(forName:"href")
                try doc.xmlData(options:[.nodePrettyPrint]).write(to:file,options:.atomic)
            }
        }
        for (index, gameID) in try (detected ?? detectDirector(in:root,resources:resources)).enumerated() {
            let file = root.appendingPathComponent("Flashback Director \(index + 1).scummvm")
            let data = try JSONEncoder().encode(DirectorLaunch(gameID:gameID,directory:"."))
            if !fm.fileExists(atPath:file.path) { try data.write(to:file,options:.withoutOverwriting) }
        }
    }

    static func entries(_ movies: [String], in root: URL) throws -> [String] {
        if movies.contains("Flashback-launch.jnlp") { return ["Flashback-launch.jnlp"] }
        var companions = Set<String>()
        for name in movies where name.lowercased().hasSuffix(".jnlp") {
            let file = try GameLibrary.contained(name,in:root)
            companions.formUnion(try companionFiles(file,root:root))
        }
        return try movies.filter { name in
            if companions.contains(name) { return false }
            let file = try GameLibrary.contained(name,in:root), ext = file.pathExtension.lowercased()
            if ["html","htm"].contains(ext), !((try? applets(file)) ?? []).isEmpty { return false }
            if ext == "exe" {
                let data = try Data(contentsOf:file,options:.mappedIfSafe)
                if flashProjector(in:data) != nil || GameLibrary.projectorMovie(in:data) != nil { return false }
                return try isDOS(file)
            }
            if ["com","bat"].contains(ext) { return try isDOS(file) }
            return true
        }
    }

    static func detectDirector(in root: URL, resources: URL) throws -> [String] {
        let executable = resources.appendingPathComponent("ScummVM/ScummVM.app/Contents/MacOS/scummvm")
        guard FileManager.default.isExecutableFile(atPath:executable.path) else { return [] }
        let helper = resources.deletingLastPathComponent().appendingPathComponent("MacOS/NativeHost")
        let policy = resources.appendingPathComponent("Native.policy")
        guard FileManager.default.isExecutableFile(atPath:helper.path) else { throw LibraryError("The native inspection host is missing. Reinstall Flashback.") }
        let saves = FileManager.default.temporaryDirectory.appendingPathComponent("Flashback-detect-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:saves,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:saves) }
        let result = try ToolResult.run(helper,["--profile",policy.path,"--runtime",resources.appendingPathComponent("ScummVM/ScummVM.app").path,
            "--executable",executable.path,"--game",root.path,"--saves",saves.path,"--",
            "--config=" + saves.appendingPathComponent("scummvm.ini").path,"--path=" + root.path,"--game=director","--detect"],timeout:20)
        if let error = result.text.components(separatedBy:"\n").first(where:{ $0.hasPrefix("ERROR\t") }) { throw LibraryError("Director inspection failed: " + String(error.dropFirst(6))) }
        guard result.status == 0 else { return [] }
        let regex = try NSRegularExpression(pattern:#"(?m)^\s*(director:[a-zA-Z0-9_-]+)\s"#)
        let text = result.text as NSString
        return Array(Set(regex.matches(in:result.text,range:NSRange(location:0,length:text.length)).map { text.substring(with:$0.range(at:1)) })).sorted()
    }
}
