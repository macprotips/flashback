// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@main enum ClassicWindowsImportChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Flashback-classic-import-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:root) }
        let iso = root.appendingPathComponent("Game Disc.ISO")
        var isoBytes = Data(repeating:0,count:17 * 2048)
        isoBytes[16 * 2048] = 1
        isoBytes.replaceSubrange((16 * 2048 + 1)..<(16 * 2048 + 6),with:Data("CD001".utf8))
        isoBytes[16 * 2048 + 6] = 1
        try isoBytes.write(to:iso)
        guard ClassicWindowsImport.directRequest(iso)?.kind == .discImage else { fatalError("ISO was not routed") }
        let pe = root.appendingPathComponent("SETUP.EXE")
        var bytes = Data(repeating:0,count:72); bytes[0] = 0x4d; bytes[1] = 0x5a; bytes[60] = 64
        bytes.replaceSubrange(64..<68,with:[0x50,0x45,0,0]); try bytes.write(to:pe)
        guard ClassicWindowsImport.isWindowsExecutable(pe),
              ClassicWindowsImport.requestAfterStandardImportFailed(pe)?.kind == .executable,
              ClassicWindowsImport.requestAfterStandardImportFailed(root)?.kind == .folder else { fatalError("Windows PE was not routed") }
        let dos = root.appendingPathComponent("GAME.EXE"); try Data(repeating:0,count:72).write(to:dos)
        guard !ClassicWindowsImport.isWindowsExecutable(dos) else { fatalError("DOS input was misclassified") }
        let library = GameLibrary(root:root.appendingPathComponent("Library"))
        let imported = try library.importClassicWindows(ClassicWindowsImportRequest(source:iso,kind:.discImage))
        guard imported.isClassicWindows, imported.format == "WINDOWS 98",
              try library.classicWindowsManifest(for:imported).0.payload == "Media/Game Disc.ISO" else { fatalError("Windows game was not preserved in the library") }
        let duplicate = try library.importClassicWindows(ClassicWindowsImportRequest(source:iso,kind:.discImage))
        guard duplicate.id == imported.id else { fatalError("Windows game duplicate was not stable") }
        try library.save([imported])
        let restored = try library.load()
        guard restored == [imported], restored[0].isClassicWindows else { fatalError("Windows game did not survive a library reload") }
        print("ClassicWindowsImportChecks passed")
    }
}
