// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@main struct ArchiveChecks {
    static func require(_ condition: Bool, _ message: String) throws { if !condition { throw LibraryError(message) } }
    static func main() async throws {
        let base = URL(string:CommandLine.arguments[1])!, live = !["127.0.0.1","localhost"].contains(base.host ?? "")
        let service = ArchiveService(base:base,allowLocal:!live)
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("Flashback-Catalog-Check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:workspace) }
        let result = try await service.search(live ? "alien hominid" : "Archive",filter:.all)
        try require(!result.items.isEmpty,"Search returned no items")
        let item = live ? result.items.first(where:{ $0.id == "1100_alien_hominid" }) ?? result.items[0] : result.items[0]
        let detail = try await service.detail(item)
        try require(!detail.choices.isEmpty,"No downloadable game")
        let file = detail.choices[0]
        let recovered = try await service.download(detail,file:file,to:workspace.appendingPathComponent("loose"),progress:{ _ in })
        try require(!recovered.record.files.isEmpty,"Download produced no files")
        _ = try await service.artwork(item)
        if !live {
            for value in ["NSFW","ＮＳＦＷ","N\u{200b}SFW","18+","R-18","rule34","StripPoker","adult_game","pornographic","hentai","nudity","sexual content"] {
                try require(!ArchiveContentFilter.allows(["title":value]),"Adult title accepted: \(value)")
            }
            for value in ["Sussex Adventure","Essex Racer","Scunthorpe Soccer","Adult Swim","Gay Pride Platformer","Furry Friends","Swords and Sandals 2"] {
                try require(ArchiveContentFilter.allows(["title":value]),"Ordinary title rejected: \(value)")
            }
            try require(!ArchiveContentFilter.allows(["adult":true]) && !ArchiveContentFilter.allows(["subject":["Flash","Adult"]]),"Explicit rating was accepted")
            try require(ArchiveContentFilter.allows(["collection":["softwarelibrary_flash","fav-nsfw_user"]]),"Bookmark collection was treated as a rating")
            try require(!ArchiveContentFilter.allows(["collection":"softwarelibrary_flash_adult"]) && ArchiveContentFilter.allows(["subject":"Adult Swim; Flash"]),"Adult collection or publisher handling failed")
            let filtered = try await service.search("filter-check",filter:.flash)
            try require(filtered.items.map(\.id) == ["ordinary-game"] && filtered.nextPage == 2,"Search leaked blocked metadata or lost pagination")
            let empty = try await service.search("filtered-page",filter:.shockwave)
            try require(empty.items.isEmpty && empty.nextPage == 2,"A filtered page prevented further browsing")
            let next = try await service.search("filtered-page",filter:.shockwave,page:2)
            try require(next.items.map(\.id) == ["page-two"] && next.nextPage == nil,"End of filtered pagination was incorrect")
            let blocked = ArchiveItem(id:"blocked-description",title:"Ordinary title",creator:"",format:"Flash")
            do { _ = try await service.artwork(blocked); throw LibraryError("Blocked artwork was fetched") } catch is ArchiveContentHidden { }
            do { _ = try await service.detail(blocked); throw LibraryError("Blocked details were returned") } catch is ArchiveContentHidden { }
            let forged = ArchiveDetail(item:blocked,description:"",date:"",rights:"",files:detail.files,restricted:false)
            do { _ = try await service.download(forged,file:file,to:workspace.appendingPathComponent("blocked"),progress:{ _ in }); throw LibraryError("Blocked download was accepted") } catch is ArchiveContentHidden { }
            try require(result.total == 5 && result.items.count == 4,"Search count failed")
            let second = try await service.search("Archive",filter:.all,page:2)
            try require(second.items.first?.id == "page-two","Pagination failed")
            // Discover's featured list is browsed a screen of identifiers at a
            // time, so a curated list longer than one page has to keep its
            // order, report the whole list as the total, and end cleanly.
            let curated = (1...30).map { "featured-\($0)" }
            let browser = ArchiveService(base:base,allowLocal:true,featuredIDs:curated)
            let firstPage = try await browser.search("",filter:.all)
            try require(firstPage.items.map(\.id) == Array(curated.prefix(24)),"Featured page 1 lost its curated order")
            try require(firstPage.total == 30 && firstPage.nextPage == 2,"Featured paging reported the wrong extent")
            let lastPage = try await browser.search("",filter:.all,page:2)
            try require(lastPage.items.map(\.id) == Array(curated.dropFirst(24)),"Featured page 2 returned the wrong slice")
            try require(lastPage.nextPage == nil,"Featured paging ran past the end of the list")
            let beyond = try await browser.search("",filter:.all,page:3)
            try require(beyond.items.isEmpty && beyond.nextPage == nil,"Featured paging past the end was not empty")
            try require(detail.files.count == 4,"Unsafe or private file was accepted")
            try require(recovered.record.files.count == 3,"Companion assets or cover exclusion failed")
            try require(recovered.record.files.contains(where:{ $0.path.hasSuffix("/level.json") }),"Level file missing")
            let library = GameLibrary(root:workspace.appendingPathComponent("Library"))
            let plan = try library.prepare(recovered.source,resources:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).deletingLastPathComponent().appendingPathComponent("Flashback.app/Contents/Resources"))
            let game = try library.importGame(plan,entry:recovered.entry!)
            try library.save([game]);try library.saveWebRecord(recovered.record,for:game)
            try require(try library.load().first?.id == game.id,"Library persistence failed")
            let duplicate = try library.importGame(plan,entry:recovered.entry!)
            try require(duplicate.id == game.id,"Duplicate download produced another game")
            let zipDetail = try await service.detail(result.items[1])
            let zip = try await service.download(zipDetail,file:zipDetail.choices[0],to:workspace.appendingPathComponent("zip"),progress:{ _ in })
            let zipPlan = try library.prepare(zip.source,resources:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).deletingLastPathComponent().appendingPathComponent("Flashback.app/Contents/Resources"))
            defer { if let temp = zipPlan.temporaryDirectory { try? FileManager.default.removeItem(at:temp) } }
            try require(zip.entry == nil && zipPlan.movies == ["play.html"],"ZIP entry discovery failed")
            try require(try await service.detail(result.items[2]).choices.isEmpty,"Installer was downloadable")
            let bad = try await service.detail(ArchiveItem(id:"bad-hash",title:"Bad",creator:"",format:"Flash"))
            do { _ = try await service.download(bad,file:bad.choices[0],to:workspace.appendingPathComponent("bad"),progress:{ _ in }); throw LibraryError("Bad checksum accepted") }
            catch { try require(error.localizedDescription.contains("integrity"),"Unexpected hash failure: \(error)") }
            let slow = try await service.detail(result.items[3])
            let task = Task { try await service.download(slow,file:slow.choices[0],to:workspace.appendingPathComponent("slow"),progress:{ _ in }) }
            try await Task.sleep(nanoseconds:200_000_000);task.cancel()
            do { _ = try await task.value; throw LibraryError("Cancellation was ignored") } catch is CancellationError { }
            try require(ArchiveService.query("x\" OR *:*",filter:.flash).contains("\"x\\\"\" AND \"OR\" AND \"*:*\""),"Search text was not quoted")
            try require(!ArchiveItem.validID("../bad") && !ArchiveItem.validID(".."),"Invalid identifier accepted")
            try require(ArchiveService.plainText("<p>A &amp; B</p><script>bad()</script>").contains("A & B") && !ArchiveService.plainText("<script>bad()</script>").contains("bad()"),"Description parsing failed")
        }
        print("PASS: \(live ? "live Archive search, metadata, artwork, and verified download" : "catalog content filter, pagination, featured-list paging and order, assets, ZIP, persistence, duplicate, checksum, cancellation, and unsafe metadata")")
    }
}
