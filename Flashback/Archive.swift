// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

struct ArchiveContentHidden: LocalizedError { var errorDescription: String? { ArchiveContentFilter.hiddenMessage } }

/// Metadata filtering for Discover. Unlabelled content cannot be reliably classified here.
enum ArchiveContentFilter {
    static let fields = ["identifier","title","creator","subject","collection","description","content_rating","age_rating","content_warning","content_warnings","nsfw","adult"]
    static let exclusion = " AND NOT (title:(nsfw OR porn OR pornography OR pornographic OR hentai OR erotic OR erotica OR nudity) OR subject:(nsfw OR porn OR pornography OR pornographic OR hentai OR erotic OR erotica OR nudity OR \"sexual content\"))"
    static let hiddenMessage = "This item is hidden by Discover’s adult-content filter."
    private static let explicit = try! NSRegularExpression(pattern:#"\b(?:nsfw|nsfl|porn\w*|hentai|erotic\w*|erotica|sex|sexy|sexual|nude|nudes|nudity|naked|xxx|rule\s*34|r\s*34|r\s*18|18\s*plus|fetish\w*|futanari|harem|incest|rape|raping|gore|gory|strip\s*(?:poker|blackjack|game)|adult\s*(?:only|content|game|games|material)|adults\s*only|mature\s*(?:audiences|content))\b|\b18\s*\+"#)
    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of:#"[\p{Cf}]"#,with:"",options:.regularExpression)
            .replacingOccurrences(of:#"([a-z])([A-Z])"#,with:"$1 $2",options:.regularExpression)
            .replacingOccurrences(of:#"([A-Z])([A-Z][a-z])"#,with:"$1 $2",options:.regularExpression)
            .folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX"))
            .replacingOccurrences(of:"_",with:" ").replacingOccurrences(of:"-",with:" ")
    }
    static func containsAdultContent(_ text: String) -> Bool {
        let text = normalized(text.removingPercentEncoding ?? text)
        return explicit.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) != nil
    }
    static func strings(_ value: Any?) -> [String] {
        if let array = value as? [Any] { return array.flatMap { strings($0) } }
        let value = ArchiveItem.string(value)
        return value.isEmpty ? [] : [value]
    }
    static func allows(_ metadata: [String:Any], files: [[String:Any]] = []) -> Bool {
        for key in ["nsfw","adult"] {
            if strings(metadata[key]).contains(where:{ ["true","1","yes"].contains(normalized($0).trimmingCharacters(in:.whitespacesAndNewlines)) }) { return false }
        }
        for key in fields where !["nsfw","adult"].contains(key) {
            for value in strings(metadata[key]) {
                // These are other users' bookmark collections, not content classifications.
                if key == "collection" && value.lowercased().hasPrefix("fav-") { continue }
                let text = key == "description" ? ArchiveService.plainText(value) : value
                if containsAdultContent(text) { return false }
                if ["subject","collection","content_rating","age_rating","content_warning","content_warnings"].contains(key) {
                    let label = normalized(text).replacingOccurrences(of:"adult swim",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
                    if label.range(of:#"\b(?:adult|adults|mature|explicit)\b"#,options:.regularExpression) != nil || ["ao","18","18+","r18","r 18","nc17","nc 17"].contains(label) { return false }
                }
            }
        }
        return !files.contains { containsAdultContent(ArchiveItem.string($0["name"])) }
    }
}

struct ArchiveItem: Identifiable, Sendable {
    let id: String
    let title: String
    let creator: String
    let format: String
    var page: URL { URL(string:"https://archive.org/details/")!.appendingPathComponent(id) }
    static func parse(_ value: [String:Any]) -> ArchiveItem? {
        let id = string(value["identifier"])
        guard validID(id), ArchiveContentFilter.allows(value) else { return nil }
        let tags = [string(value["emulator"]),string(value["emulator_ext"]),string(value["subject"]),string(value["collection"])].joined(separator:" ").lowercased()
        let format = tags.contains("shockwave") || tags.contains("director") || tags.contains("dcr") ? "Shockwave" : (tags.contains("flash") || tags.contains("ruffle") || tags.contains("swf") ? "Flash" : "Browser game")
        return ArchiveItem(id:id,title:String((string(value["title"]).isEmpty ? id : string(value["title"])).prefix(160)),creator:String(string(value["creator"]).prefix(240)),format:format)
    }
    static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? [String] { return value.joined(separator:", ") }
        return (value as? NSNumber)?.stringValue ?? ""
    }
    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 200 && id != "." && id != ".." && id.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) }
    }
}

struct ArchiveFile: Identifiable, Sendable {
    let name: String
    let bytes: Int64
    let sha1: String
    var id: String { name }
    var ext: String { (name as NSString).pathExtension.lowercased() }
    var playable: Bool { ["swf","dcr","dir","dxr","zip","html","htm"].contains(ext) }
    var size: String { ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file) }
}

struct ArchiveDetail: Sendable {
    let item: ArchiveItem
    let description: String
    let date: String
    let rights: String
    let files: [ArchiveFile]
    let restricted: Bool
    var choices: [ArchiveFile] {
        restricted ? [] : files.filter { $0.playable && $0.bytes > 0 && $0.bytes <= ArchiveService.fileLimit }.sorted {
            func rank(_ file: ArchiveFile) -> Int { ["zip","swf","dcr","dir","dxr","html","htm"].firstIndex(of:file.ext) ?? 9 }
            return rank($0) == rank($1) ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : rank($0) < rank($1)
        }
    }
    func compatibility(_ file: ArchiveFile?) -> String {
        let tested: [String:(String,String)] = [
            "legojunkbot":("84169063110fe66a399a4bec95dc276b12b8e9c0","Opening gameplay tested: first-level brick moving."),
            "lego-world-builder":("0fd2cbd4c0701b7037a923bc2ba45467416d6626","Opening gameplay tested: Mission 1 tutorial and camera panning."),
            "legosupersonicrcgame":("29cb4582170abefd45d3fb47275c3a199909af5c","Opening gameplay tested: 3D driving and game interface.")]
        if let file, let known = tested[item.id], file.sha1 == known.0 { return known.1 }
        return "Untested in Flashback. Some games need unavailable servers or player features."
    }
    func downloadFiles(_ selected: ArchiveFile) throws -> [ArchiveFile] {
        guard choices.contains(where:{ $0.id == selected.id }) else { throw LibraryError("Choose an available game file.") }
        if selected.ext == "zip" { return [selected] }
        let assets: Set<String> = ["swf","dcr","dir","dxr","cct","cxt","cst","w3d","html","htm","js","mjs","css","json","xml","txt","csv","dat","bin","wasm","png","jpg","jpeg","gif","webp","bmp","svg","ico","mp3","wav","ogg","aif","aiff","mid","midi","flv","mp4","webm","woff","woff2","ttf","otf","swa"]
        let parent = (selected.name as NSString).deletingLastPathComponent
        let companions = files.filter {
            let lower = $0.name.lowercased(), base = (lower as NSString).lastPathComponent
            return $0.id != selected.id && (parent.isEmpty || $0.name.hasPrefix(parent + "/")) && assets.contains($0.ext)
                && !lower.contains("__ia_thumb") && !base.hasPrefix("screenshot") && !base.hasPrefix("cover") && !base.contains("_thumb.")
                && !base.hasSuffix("_files.xml") && !base.hasSuffix("_meta.xml") && !base.hasSuffix("_reviews.xml")
        }
        let result = [selected] + companions
        guard result.count <= 500, result.allSatisfy({ $0.bytes > 0 && $0.bytes <= ArchiveService.fileLimit }), result.reduce(Int64(0),{ $0 + $1.bytes }) <= 1024 * 1024 * 1024 else {
            throw LibraryError("This item has too many supporting files for a single download. Choose a game ZIP, or download the files from Internet Archive and use Add Games.")
        }
        return result
    }
}

enum ArchiveFilter: String, CaseIterable { case all = "All", flash = "Flash", shockwave = "Shockwave" }
struct ArchiveResults: Sendable { let items: [ArchiveItem]; let total: Int; let nextPage: Int? }

actor ArchiveService {
    static let fileLimit: Int64 = 512 * 1024 * 1024
    static let featured = ["legojunkbot","lego-world-builder","legosupersonicrcgame","stick-rpg-complete",
        "cannibals-missioneries","swords-and-sandals-2","1100_alien_hominid","super-mario-63",
        "bloons-tower-defense-3_202201","bloxors","bubble-shooter_swf","robotunicornattack_flash",
        "impossible-quiz-deluxe-newgrounds","tiq2_swf","flash_alien_hominid","the-last-stand-union-city",
        "flash_papaspizzeria","portal_flash_version","helicoptergame_flash","flash_Mario_Combat","flash_age_of_war",
        "mudandblood2_flash","gun-mayhem-two","dadnme","ultimate-flash-sonic_202101","duck-life-4_20210406",
        "plants-vs-zombies_202111","mahjong_202011","learn_to_fly_2","qwop_flash","super_mario-flash-3",
        "bowmaster_prelude_202012","flash_Line_Rider_2","interactive_buddy_v_1_02_by_shock_value_d6ma8m","hobo1",
        "swords-and-sandals-2_flash","bad_ice_cream","warlords-calltoarms","adobeflash-run2",
        "courage_the_cowardly_dog_nightmare_vacation","mother_load","earn_to-die","papastacomia_202008",
        "flash_riddleschool","flash_thisistheonlylevel","ducklife2worldchampion_flash","red-ball_",
        "tank-trouble_flash","ageofwar2_202401","btd5-dat_20231125","cubefield_flash",
        "duck-life-3-evolution_202111","Example_flash13","commando-2-battle-of-asia","curveball_flash",
        "asteroids_swf","isaac_202102","fancypantsadventure_202011","run3_","feudalism-ii","warfare-1917",
        "flash_kitten_canons","strikeforceheroes_202310","stick-war","newgrounds-rumble","achievementflash",
        "1100_solitaire","madness_202303","1100_fight_man_xiaoxiao9","kingdom-rush-frontie-15717",
        "toss_the_turtle_flash","nv-12","bowman2_flash","flash_salad-fingers","lego-racers-tiny-turbos-game",
        "snailbob_flash","riddle-transfer1","learn-to-fly","flash_spaceinvaders","bejeweled-ste","papasburgeria_v2",
        "suma-the-lost-treasure_flash","frogger_202204","vex-2_20231202","gemcraft-1716","bobble_swf",
        "fireboy-and-watergirl-3-in-the-ice-temple","Example_flash4","bookworm_202403","btd_5","time-fcuk",
        "happy-wheels_202209","dolphin-olympics-2","boating_dcr","heli_attack-2","flash_monkeylander",
        "heli_attack-3_","bubble_trouble_20210714","web-of-words-spiderman","raze_20201123","sushi-cat-2",
        "1100_snake","pacman_pastore","1100_boom_boom_volleyball","nights-shockwave-game","sugarsugar_flash",
        "fireboy_and-watergirl-in-the-forest-temple","ragdollcannon2_flash","minecar","2611-territory-war",
        "dune_buggy","pbs-galaga","epic-battle-fantasy-3","fish-tales-flash-game","the-last-stand",
        "tetris_20201123_0932","1100_flash_arkanoid","1100_american_football","centipede_202204","breakout_202204",
        "redlinerumbleog","8_ball","pongflashgame","doodle-god-2-11411ec92","fragger_flash","free-rider-2",
        "galidor_quest","rooftop_skater_1","2557-dragon-ball-z-flash-dimension","download_20220503",
        "1100_ultimatefootball","powerpuff-girls-pillow-fight","2549-sniper-assassin","20_20240806","game_20220603",
        "nwmgholes","1100_sonny","meat-boy-2388-1","1100_frantic","1100_jetpack","rooms-town-water-scavenger-hunt"]
    let base: URL
    let allowLocal: Bool
    /// The curated list this instance browses. Defaults to the shipped one; a
    /// check supplies its own so featured paging can be exercised against the
    /// local fixture instead of the live Archive.
    let featuredIDs: [String]
    /// The UTC week chosen when this service is created. Keeping it fixed means
    /// an open Discover window cannot reorder its cards at a calendar boundary.
    let featuredWeek: Int
    private var cache: [URL:(Date,Data)] = [:]
    init(base: URL = URL(string:"https://archive.org")!, allowLocal: Bool = false,
         featuredIDs: [String] = ArchiveService.featured, featuredWeek: Int? = nil) {
        self.base = base; self.allowLocal = allowLocal
        var seen = Set<String>()
        self.featuredIDs = featuredIDs.filter { seen.insert($0).inserted }
        self.featuredWeek = featuredWeek ?? Self.utcWeek()
    }
    /// A stable UTC ISO-week bucket. Tests can supply a bucket directly rather
    /// than depending on the date when they run.
    static func utcWeek(for date: Date = Date()) -> Int {
        var calendar = Calendar(identifier:.iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT:0)!
        guard let start = calendar.dateInterval(of:.weekOfYear,for:date)?.start else { return 0 }
        return Int(floor(start.timeIntervalSinceReferenceDate / (7 * 24 * 60 * 60)))
    }
    /// Rotate the complete curated order by a screen each week. The result is
    /// a permutation, so pagination remains valid and every entry eventually
    /// reaches the first screen without duplicate cards.
    static func featuredOrder(_ ids: [String], week: Int) -> [String] {
        guard ids.count > 1 else { return ids }
        let stride = min(24,ids.count - 1)
        let offset = ((week % ids.count) + ids.count) % ids.count * stride % ids.count
        return Array(ids[offset...]) + Array(ids[..<offset])
    }
    static func query(_ text: String, filter: ArchiveFilter) -> String {
        let scope: String
        switch filter {
        case .all: scope = "(collection:softwarelibrary_flash OR subject:Shockwave OR subject:\"Shockwave games\" OR subject:\"Macromedia Director\")"
        case .flash: scope = "collection:softwarelibrary_flash"
        case .shockwave: scope = "(subject:Shockwave OR subject:\"Shockwave games\" OR subject:\"Macromedia Director\")"
        }
        let words = text.prefix(300).split(whereSeparator:{ $0.isWhitespace }).prefix(20).map { "\"" + $0.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"") + "\"" }
        return "mediatype:software AND " + scope + (words.isEmpty ? "" : " AND " + words.joined(separator:" AND ")) + ArchiveContentFilter.exclusion
    }
    func search(_ text: String, filter: ArchiveFilter, page: Int = 1) async throws -> ArchiveResults {
        let featured = text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && filter == .all
        // The featured list is long enough that asking for every identifier in
        // one query would build a URL the search endpoint rejects. Page through
        // it here instead, a screen of identifiers at a time, which also keeps
        // the curated order rather than re-sorting the whole list by downloads.
        let featuredOrder = Self.featuredOrder(featuredIDs,week:featuredWeek)
        let slice = featured ? Array(featuredOrder.dropFirst(max(0,page - 1) * 24).prefix(24)) : []
        if featured && slice.isEmpty { return ArchiveResults(items:[],total:featuredIDs.count,nextPage:nil) }
        var parts = URLComponents(url:base.appendingPathComponent("advancedsearch.php"),resolvingAgainstBaseURL:false)!
        let query = featured ? "(" + slice.map { "identifier:" + $0 }.joined(separator:" OR ") + ")" + ArchiveContentFilter.exclusion : Self.query(text,filter:filter)
        parts.queryItems = [URLQueryItem(name:"q",value:query),URLQueryItem(name:"rows",value:"24"),URLQueryItem(name:"page",value:String(featured ? 1 : page)),URLQueryItem(name:"output",value:"json"),URLQueryItem(name:"sort[]",value:"downloads desc")] + (ArchiveContentFilter.fields + ["emulator","emulator_ext"]).map { URLQueryItem(name:"fl[]",value:$0) }
        let json = try await object(parts.url!)
        guard let response = json["response"] as? [String:Any], let docs = response["docs"] as? [[String:Any]], let total = response["numFound"] as? Int else { throw LibraryError("Internet Archive returned an unreadable search. Try again shortly.") }
        let candidates = docs.compactMap(ArchiveItem.parse)
        // Keep unchecked metadata and artwork out of the visible grid. Four workers
        // reuse the same metadata cache when a user opens a card or downloads it.
        let checked = await withTaskGroup(of:([ArchiveItem],Int).self,returning:([ArchiveItem],Int).self) { group in
            for worker in 0..<min(4,candidates.count) {
                group.addTask {
                    var visible: [ArchiveItem] = []; var failures = 0
                    for index in stride(from:worker,to:candidates.count,by:4) {
                        if Task.isCancelled { break }
                        do { visible.append(try await self.detail(candidates[index]).item) }
                        catch is ArchiveContentHidden { }
                        catch { failures += 1 }
                    }
                    return (visible,failures)
                }
            }
            var visible: [ArchiveItem] = []; var failures = 0
            for await (items,count) in group { visible += items; failures += count }
            return (visible,failures)
        }
        try Task.checkCancellation()
        if checked.0.isEmpty && checked.1 > 0 { throw LibraryError("Couldn’t check these game listings. Try again when Internet Archive is available.") }
        let visible = Set(checked.0.map(\.id))
        var items = candidates.filter { visible.contains($0.id) }
        if featured {
            items.sort { (featuredOrder.firstIndex(of:$0.id) ?? Int.max) < (featuredOrder.firstIndex(of:$1.id) ?? Int.max) }
            // Paging is over the curated list, not the response: a page whose
            // identifiers are all withheld by the content filter still has
            // pages after it.
            let consumed = max(0,page - 1) * 24 + slice.count
            return ArchiveResults(items:items,total:featuredIDs.count,
                                  nextPage:consumed < featuredIDs.count ? page + 1 : nil)
        }
        let start = response["start"] as? Int ?? max(0,page-1) * 24
        return ArchiveResults(items:items,total:max(0,total),nextPage:!docs.isEmpty && start + docs.count < total ? page + 1 : nil)
    }
    func detail(_ item: ArchiveItem) async throws -> ArchiveDetail {
        guard ArchiveItem.validID(item.id) else { throw LibraryError("This Archive identifier is invalid.") }
        let json = try await object(base.appendingPathComponent("metadata").appendingPathComponent(item.id))
        guard let metadata = json["metadata"] as? [String:Any], let raw = json["files"] as? [[String:Any]], raw.count <= 30000 else { throw LibraryError("This item’s files are unavailable. It may have been removed from Internet Archive.") }
        guard ArchiveContentFilter.allows(metadata,files:raw), ArchiveContentFilter.allows(["identifier":item.id,"title":item.title,"creator":item.creator]) else { throw ArchiveContentHidden() }
        var seen = Set<String>()
        let files = raw.compactMap { value -> ArchiveFile? in
            let name = ArchiveItem.string(value["name"])
            guard !name.isEmpty, name.count < 2000, !name.contains("\\"), !name.hasPrefix("/"), !name.split(separator:"/",omittingEmptySubsequences:false).contains(where:{ $0.isEmpty || $0 == "." || $0 == ".." }), !name.contains(where:{ $0.isNewline || $0 == "\0" }), seen.insert(name).inserted,
                  !["true","1"].contains(ArchiveItem.string(value["private"]).lowercased()), let size = Int64(ArchiveItem.string(value["size"])), size >= 0, size <= 10 * 1024 * 1024 * 1024 else { return nil }
            return ArchiveFile(name:name,bytes:size,sha1:ArchiveItem.string(value["sha1"]).lowercased())
        }
        let description = Self.plainText(ArchiveItem.string(metadata["description"]))
        let restricted = ["true","1"].contains(ArchiveItem.string(metadata["access-restricted-item"]).lowercased()) || ["true","1"].contains(ArchiveItem.string(json["is_dark"]).lowercased())
        return ArchiveDetail(item:ArchiveItem.parse(metadata) ?? item,description:description,date:String(ArchiveItem.string(metadata["date"]).prefix(10)),rights:String(ArchiveItem.string(metadata["rights"]).prefix(1000)),files:files,restricted:restricted)
    }
    static func plainText(_ html: String) -> String {
        let input = String(html.prefix(60000)).replacingOccurrences(of:"(?is)<(script|style)[^>]*>.*?</\\1>",with:"",options:.regularExpression)
            .replacingOccurrences(of:"(?i)<br\\s*/?>|</p>|</div>",with:"\n\n",options:.regularExpression)
        guard let document = try? XMLDocument(xmlString:"<html><body>" + input + "</body></html>",options:[.documentTidyHTML,.nodeLoadExternalEntitiesNever]) else { return String(input.replacingOccurrences(of:"<[^>]*>",with:"",options:.regularExpression).prefix(12000)) }
        return String((document.rootElement()?.stringValue ?? "").trimmingCharacters(in:.whitespacesAndNewlines).prefix(12000))
    }
    func artwork(_ item: ArchiveItem) async throws -> Data {
        guard ArchiveItem.validID(item.id) else { throw LibraryError("Invalid item") }
        _ = try await detail(item)
        return try await data(base.appendingPathComponent("services/img").appendingPathComponent(item.id),limit:5 * 1024 * 1024)
    }
    private func object(_ url: URL) async throws -> [String:Any] {
        let bytes = try await data(url,limit:8 * 1024 * 1024)
        guard let value = try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else { throw LibraryError("Internet Archive returned an unreadable response.") }
        return value
    }
    private func data(_ url: URL, limit: Int64) async throws -> Data {
        if let (date,data) = cache[url], Date().timeIntervalSince(date) < 900 { return data }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("Flashback-Archive-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:temp) }
        let response = try await WebTransfer(url:url,directory:temp,limit:limit,scanOnly:false,allowLocal:allowLocal,progress:{ _,_ in }).start()
        let data = try Data(contentsOf:response.file)
        if cache.values.reduce(0,{ $0 + $1.1.count }) + data.count > 32 * 1024 * 1024 { cache.removeAll() }
        cache[url] = (Date(),data)
        return data
    }
    nonisolated func fileURL(item: ArchiveItem, file: ArchiveFile) -> URL { base.appendingPathComponent("download").appendingPathComponent(item.id).appendingPathComponent(file.name) }
    func download(_ detail: ArchiveDetail, file: ArchiveFile, to workspace: URL, progress: @escaping @Sendable (WebProgress) -> Void) async throws -> WebRecovery {
        let verified = try await self.detail(detail.item)
        guard verified.files.contains(where:{ $0.name == file.name && $0.sha1 == file.sha1 && $0.bytes == file.bytes }) else { throw LibraryError("This item’s file listing changed. Reopen its details before downloading.") }
        let files = try verified.downloadFiles(file), fm = FileManager.default
        let payload = workspace.appendingPathComponent("Game"), scratch = workspace.appendingPathComponent("Transfers")
        let entryURL = fileURL(item:detail.item,file:file)
        var record = WebImportRecord(page:detail.item.page,entryURL:entryURL,baseURL:entryURL.deletingLastPathComponent(),title:detail.item.title,parameters:[:])
        var bytes: Int64 = 0
        for (index,asset) in files.enumerated() {
            try Task.checkCancellation()
            let url = fileURL(item:detail.item,file:asset), completed = bytes
            let response = try await WebTransfer(url:url,directory:scratch,limit:Self.fileLimit,scanOnly:false,allowLocal:allowLocal,progress:{ received,_ in
                progress(WebProgress(message:"Downloading file \(index + 1) of \(files.count)…",detail:asset.name,files:index,bytes:completed + received))
            }).start()
            guard response.bytes == asset.bytes else { throw LibraryError("The download size doesn’t match the Archive listing for \(asset.name). Try again later.") }
            if !asset.sha1.isEmpty {
                let handle = try FileHandle(forReadingFrom:response.file); defer { try? handle.close() }
                var hash = Insecure.SHA1()
                while let data = try handle.read(upToCount:65536), !data.isEmpty { try Task.checkCancellation(); hash.update(data:data) }
                guard hash.finalize().map({ String(format:"%02x",$0) }).joined() == asset.sha1 else { throw LibraryError("The downloaded file failed its integrity check: \(asset.name). Try again later.") }
            }
            let path = WebImportRecord.path(url), destination = try GameLibrary.contained(path,in:payload)
            try fm.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
            try fm.moveItem(at:response.file,to:destination)
            record.files.append(WebImportRecord.File(urls:url == response.url ? [url] : [url,response.url],path:path,mime:response.mimeType,bytes:response.bytes,sha256:try WebImportRecord.hashFile(destination)))
            if ["html","htm"].contains(asset.ext), asset.bytes <= 2 * 1024 * 1024 {
                let page = WebPage.parse(WebPage.text(try Data(contentsOf:destination)),url:url)
                record.documentBases[path] = page.base
                if let candidate = page.candidates.first(where:{ $0.url == entryURL }) { record.parameters = candidate.parameters; record.embeddingPage = url; record.baseURL = candidate.baseURL }
            }
            bytes += response.bytes
        }
        try Task.checkCancellation()
        let entry = WebImportRecord.path(entryURL)
        return WebRecovery(source:file.ext == "zip" ? try GameLibrary.contained(entry,in:payload) : payload,entry:file.ext == "zip" ? nil : entry,record:record)
    }
}
