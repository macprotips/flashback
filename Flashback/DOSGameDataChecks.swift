import Foundation
@main struct DOSGameDataChecks {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DOS-data-" + UUID().uuidString)
        defer { try? fm.removeItem(at:root) }
        let saves = root.appendingPathComponent("Saves"), original = root.appendingPathComponent("Original")
        try fm.createDirectory(at:original,withIntermediateDirectories:true)
        try Data("original".utf8).write(to:original.appendingPathComponent("SAVE.DAT"))
        _ = try DOSGameData.replace(in:saves,with:original)
        let working = saves.appendingPathComponent("Files/SAVE.DAT")
        try Data("progress".utf8).write(to:working)
        let snapshot = try DOSGameData.backup(in:saves)
        _ = try DOSGameData.replace(in:saves,with:original)
        guard try String(contentsOf:working,encoding:.utf8) == "original", try String(contentsOf:snapshot.appendingPathComponent("SAVE.DAT"),encoding:.utf8) == "progress" else { fatalError("reset did not preserve snapshot") }
        _ = try DOSGameData.replace(in:saves,with:snapshot)
        guard try String(contentsOf:working,encoding:.utf8) == "progress", try DOSGameData.backups(in:saves).count == 3 else { fatalError("restore failed") }
        try fm.createSymbolicLink(at:original.appendingPathComponent("ESCAPE"),withDestinationURL:root)
        do { _ = try DOSGameData.replace(in:saves,with:original); fatalError("accepted symbolic link") } catch is LibraryError { }
        guard try String(contentsOf:working,encoding:.utf8) == "progress" else { fatalError("failed restore changed current data") }
        print("PASS: backup, reset, restore, previous-data preservation, rejected link leaves current data intact")
    }
}
