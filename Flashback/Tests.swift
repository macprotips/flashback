// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import ImageIO

@main struct Checks {
    static func main() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("Flashback-tests-" + UUID().uuidString)
        defer { try? fm.removeItem(at:temp) }
        try fm.createDirectory(at:temp, withIntermediateDirectories:true)
        let privateTemp = URL(fileURLWithPath:"/private/tmp/Flashback-path-check-" + UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:privateTemp,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:privateTemp) }
        let newFile = try GameLibrary.contained("not-created.swf",in:privateTemp)
        assert(newFile.deletingLastPathComponent() == privateTemp.standardizedFileURL.resolvingSymlinksInPath())
        let library = GameLibrary(root:temp.appendingPathComponent("Library"))
        let source = temp.appendingPathComponent("Space Game")
        try fm.createDirectory(at:source.appendingPathComponent("root/images"), withIntermediateDirectories:true)
        let movie = source.appendingPathComponent("root/game.swf")
        let swf = Data([70,87,83,8,16,0,0,0,8,0,0,12,1,0,0,0])
        try swf.write(to:movie)
        try Data("art".utf8).write(to:source.appendingPathComponent("root/images/title.png"))
        let plan = try library.inspect(source)
        assert(plan.movies == ["root/game.swf"] && plan.files.count == 2)
        var game = try library.importGame(plan, entry:plan.movies[0])
        assert(game.title == "Space Game")
        let copy = try library.movie(for:game)
        let copiedData = try Data(contentsOf:copy)
        assert(copiedData == swf)
        assert(fm.fileExists(atPath:library.folder(for:game).appendingPathComponent("root/images/title.png").path))
        let normalAsset = try GameLibrary.resource("root/images/title.png",entry:game.entry,in:library.folder(for:game))
        let htmlRelativeAsset = try GameLibrary.resource("root/root/images/title.png",entry:game.entry,in:library.folder(for:game))
        assert(normalAsset == htmlRelativeAsset)
        let doubledSeparator = try GameLibrary.resource("root//images///title.png",entry:game.entry,in:library.folder(for:game))
        assert(doubledSeparator == normalAsset)
        let duplicate = try library.importGame(plan, entry:plan.movies[0])
        assert(duplicate.id == game.id)
        game.title = "Renamed"
        game.favorite = true
        try library.save([game])
        let restored = try library.load()
        assert(restored == [game] && restored[0].playbackVolume == 1,
               "Libraries without a volume value must retain full volume")
        game.volume = 0.35
        try library.save([game])
        let restoredVolume = try library.load().first?.playbackVolume
        assert(restoredVolume == 0.35,
               "Per-game volume must survive a library reload")
        var invalidVolume = game
        invalidVolume.volume = 1.01
        mustFail { try library.save([invalidVolume]) }
        try fm.removeItem(at:source)
        let independentData = try Data(contentsOf:copy)
        assert(independentData == swf, "Imported games must survive moving the originals")
        let odd = temp.appendingPathComponent("space #?%.SWF")
        try swf.write(to:odd)
        let standalone = try library.inspect(odd)
        assert(standalone.movies == ["space #?%.SWF"])
        _ = try library.importGame(standalone, entry:standalone.movies[0])
        func mustFail(_ block: () throws -> Void) {
            do { try block(); fatalError("Expected validation failure") } catch {}
        }
        let projector = temp.appendingPathComponent("Projector")
        try fm.createDirectory(at:projector,withIntermediateDirectories:true)
        let embedded = Data("XFIR".utf8) + Data([8,0,0,0]) + Data("MDGFtest".utf8)
        let executable = Data("MZpadding".utf8) + embedded
        assert(GameLibrary.projectorMovie(in:executable) == 9..<25)
        assert(GameLibrary.projectorMovie(in:executable + embedded) == nil, "Ambiguous movies must not be guessed")
        assert(GameLibrary.projectorMovie(in:executable.dropLast()) == nil, "Truncated movies must not be extracted")
        assert(GameLibrary.projectorMovie(in:embedded) == nil, "Require an executable header")
        let bigEndian = Data("MZ".utf8) + Data("RIFX".utf8) + Data([0,0,0,8]) + Data("FGDMtest".utf8)
        assert(GameLibrary.projectorMovie(in:bigEndian) == 2..<18)
        let windowsStub = Data("MZ".utf8) + Data("XFIR".utf8) + Data([8,0,0,0]) + Data("39VMtest".utf8)
        assert(GameLibrary.projectorMovie(in:windowsStub) == nil)
        let exe = projector.appendingPathComponent("game.exe")
        try executable.write(to:exe)
        try GameLibrary.recoverProjectorMovies(in:projector)
        let recovered = projector.appendingPathComponent("projector-loader.dcr")
        let recoveredData = try Data(contentsOf:recovered)
        assert(recoveredData == embedded)
        try Data("existing".utf8).write(to:recovered)
        try GameLibrary.recoverProjectorMovies(in:projector)
        let preserved = try Data(contentsOf:recovered)
        assert(preserved == Data("existing".utf8), "Existing game files must never be overwritten")
        try fm.removeItem(at:recovered)
        try executable.write(to:projector.appendingPathComponent("second.exe"))
        try GameLibrary.recoverProjectorMovies(in:projector)
        assert(!fm.fileExists(atPath:recovered.path), "Do not guess between multiple projectors")
        let originalExecutable = try Data(contentsOf:exe)
        assert(originalExecutable == executable)
        let castFolder = temp.appendingPathComponent("Casts")
        try fm.createDirectory(at:castFolder,withIntermediateDirectories:true)
        try Data("editable".utf8).write(to:castFolder.appendingPathComponent("Cave2.cst"))
        let editable = try GameLibrary.resource("Cave2.cct",entry:"game.dcr",in:castFolder)
        assert(editable.lastPathComponent == "Cave2.cst")
        let flashCast = try GameLibrary.resource("Cave2.cct",entry:"game.swf",in:castFolder)
        assert(flashCast.lastPathComponent == "Cave2.cct")
        try Data("published".utf8).write(to:castFolder.appendingPathComponent("Cave2.cct"))
        let published = try GameLibrary.resource("Cave2.cct",entry:"game.dcr",in:castFolder)
        assert(published.lastPathComponent == "Cave2.cct")
        try fm.createSymbolicLink(at:castFolder.appendingPathComponent("Outside.cst"),withDestinationURL:copy)
        mustFail { _ = try GameLibrary.resource("Outside.cct",entry:"game.dcr",in:castFolder) }
        let art = temp.appendingPathComponent("Artwork.png")
        let canvas = CGContext(data:nil,width:2000,height:1000,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        canvas.setFillColor(CGColor(red:0.1,green:0.7,blue:0.4,alpha:1))
        canvas.fill(CGRect(x:0,y:0,width:2000,height:1000))
        let encoded = NSMutableData()
        let encoder = CGImageDestinationCreateWithData(encoded,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(encoder,canvas.makeImage()!,nil)
        assert(CGImageDestinationFinalize(encoder))
        try (encoded as Data).write(to:art)
        let originalCover = library.defaultArtworkURL(game)
        try fm.createDirectory(at:originalCover.deletingLastPathComponent(),withIntermediateDirectories:true)
        try (encoded as Data).write(to:originalCover)
        try library.setArtwork(art,for:game)
        let custom = library.artworkURL(game)
        let customBytes = try Data(contentsOf:custom)
        let preview = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(custom as CFURL,nil)!,0,nil)!
        assert(preview.width == 1120 && preview.height == 560, "Artwork must retain its aspect ratio within a bounded size")
        assert(custom == library.customArtworkURL(game))
        try fm.removeItem(at:art)
        assert(GameLibrary(root:library.root).artworkURL(game) == custom, "Artwork must survive relaunch and moving the original")
        try Data("invalid image".utf8).write(to:art)
        mustFail { try library.setArtwork(art,for:game) }
        let afterInvalid = try Data(contentsOf:custom)
        let afterDefault = try Data(contentsOf:originalCover)
        assert(afterInvalid == customBytes && afterDefault == encoded as Data, "Invalid images and customization must preserve existing artwork")
        mustFail { try library.setArtwork(source,for:game) }
        mustFail { try library.setArtwork(URL(string:"https://example.com/image.png")!,for:game) }
        let jpeg = NSMutableData()
        let jpegEncoder = CGImageDestinationCreateWithData(jpeg,"public.jpeg" as CFString,1,nil)!
        CGImageDestinationAddImage(jpegEncoder,canvas.makeImage()!,[kCGImagePropertyOrientation:6] as CFDictionary)
        assert(CGImageDestinationFinalize(jpegEncoder))
        try (jpeg as Data).write(to:art)
        try library.setArtwork(art,for:game)
        let rotated = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(custom as CFURL,nil)!,0,nil)!
        assert(rotated.width == 560 && rotated.height == 1120, "Replacement artwork must honor photo orientation")
        let oversized = try FileHandle(forWritingTo:art)
        try oversized.truncate(atOffset:50 * 1024 * 1024 + 1); try oversized.close()
        mustFail { try library.setArtwork(art,for:game) }
        try library.restoreArtwork(game)
        assert(library.artworkURL(game) == originalCover)
        try library.restoreArtwork(game)
        print("PASS: custom artwork replacement, resizing, photo orientation, persistence, original-file independence, invalid/oversized-image preservation, and default restoration")
        mustFail { _ = try GameLibrary.contained("../outside", in:temp) }
        mustFail { _ = try GameLibrary.contained("/etc/passwd", in:temp) }
        mustFail { _ = try library.inspect(temp) }
        mustFail { _ = try library.importGame(standalone, entry:"missing.swf") }
        let invalid = temp.appendingPathComponent("broken.swf")
        try Data("not a Flash movie".utf8).write(to:invalid)
        mustFail { try GameLibrary.validateMovie(invalid) }
        let zip = temp.appendingPathComponent("game.zip")
        try Data().write(to:zip)
        mustFail { _ = try library.inspect(zip) }
        let jar = temp.appendingPathComponent("Test Game.JAR")
        try Data([0x50,0x4b,0x03,0x04]).write(to:jar)
        let javaPlan = try library.inspect(jar)
        let javaGame = try library.importGame(javaPlan,entry:"Test Game.JAR")
        assert(javaGame.isJava && javaPlan.movies == ["Test Game.JAR"])
        try library.save([game,javaGame])
        let mixed = try library.load()
        assert(mixed == [game,javaGame] && !mixed[0].isJava && mixed[1].isJava)
        try Data("broken jar".utf8).write(to:jar)
        mustFail { try GameLibrary.validateGame(jar) }
        let html = temp.appendingPathComponent("Canvas Game.HTM")
        try Data("<!doctype html><canvas></canvas>".utf8).write(to:html)
        let htmlPlan = try library.inspect(html)
        let htmlGame = try library.importGame(htmlPlan, entry:htmlPlan.movies[0])
        assert(htmlGame.isHTML && !htmlGame.isJava && htmlGame.format == "HTML5")
        try library.save([game, javaGame, htmlGame])
        let formats = try library.load().map(\.format)
        assert(formats == ["SWF", "JAVA", "HTML5"])
        try Data().write(to:html)
        mustFail { try GameLibrary.validateGame(html) }
        for (extensionName, signature, codec) in [("DCR", "XFIR", "MDGF"), ("dir", "RIFX", "MV93"), ("dxr", "XFIR", "39VM")] {
            let shockwave = temp.appendingPathComponent("Game.\(extensionName)")
            let header = Data(signature.utf8) + Data([4,0,0,0]) + Data(codec.utf8)
            try header.write(to:shockwave)
            let shockwavePlan = try library.inspect(shockwave)
            let shockwaveGame = try library.importGame(shockwavePlan, entry:shockwavePlan.movies[0])
            assert(shockwaveGame.isShockwave && !shockwaveGame.isFlash && shockwaveGame.format == "SHOCKWAVE")
            try library.save([game, javaGame, htmlGame, shockwaveGame])
            let formats = try library.load().map(\.format)
            assert(formats == ["SWF", "JAVA", "HTML5", "SHOCKWAVE"])
            try Data("not a Director game".utf8).write(to:shockwave)
            mustFail { try GameLibrary.validateGame(shockwave) }
            try Data(header.prefix(9)).write(to:shockwave)
            mustFail { try GameLibrary.validateGame(shockwave) }
        }
        let linkFolder = temp.appendingPathComponent("Links")
        try fm.createDirectory(at:linkFolder, withIntermediateDirectories:true)
        try fm.createSymbolicLink(at:linkFolder.appendingPathComponent("game.swf"), withDestinationURL:odd)
        mustFail { _ = try library.inspect(linkFolder) }
        let index = library.root.appendingPathComponent("Library.json")
        let corrupt = Data("broken index".utf8)
        try corrupt.write(to:index)
        mustFail { _ = try library.load() }
        let preservedData = try Data(contentsOf:index)
        assert(preservedData == corrupt, "A damaged index must not be overwritten")
        print("PASS: folder assets, standalone files, duplicate detection, persistence, original-file independence, unusual names, invalid input, path containment, symlinks, and damaged-index preservation")
    }
}
