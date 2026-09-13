// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@main struct StorageLocationChecks {
 static func main() throws {
  let fm = FileManager.default, temp = fm.temporaryDirectory.appendingPathComponent("StorageLocationChecks-" + UUID().uuidString); defer { try? fm.removeItem(at: temp) }; try fm.createDirectory(at: temp, withIntermediateDirectories: true)
  let defaults = UserDefaults(suiteName: "StorageLocationChecks-" + UUID().uuidString)!; let service = StorageLocation(defaults: defaults)
  defaults.set(Data("corrupt".utf8), forKey:StorageLocation.bookmarkKey)
  guard service.selectedRootPreflight() == nil else { throw StorageLocationError(message:"corrupt bookmark was accepted") }
  let source = temp.appendingPathComponent("old"), destination = temp.appendingPathComponent("new"); try fm.createDirectory(at: source, withIntermediateDirectories: true); try Data("save".utf8).write(to: source.appendingPathComponent("Library.json"))
  _ = try service.select(destination, movingFrom: source)
  guard fm.fileExists(atPath: source.appendingPathComponent("Library.json").path), fm.fileExists(atPath: destination.appendingPathComponent("Library.json").path), service.resolvedRoot().standardizedFileURL.resolvingSymlinksInPath() == destination.standardizedFileURL.resolvingSymlinksInPath() else { throw StorageLocationError(message:"migration did not preserve and select both roots") }
  do { _ = try service.select(destination.appendingPathComponent("nested"), movingFrom: destination); throw StorageLocationError(message:"nested storage accepted") } catch is StorageLocationError {}
  let missing = temp.appendingPathComponent("missing"); try fm.createDirectory(at:missing, withIntermediateDirectories:true)
  defaults.set(try missing.bookmarkData(options:[.withSecurityScope], includingResourceValuesForKeys:nil, relativeTo:nil), forKey:StorageLocation.bookmarkKey)
  try fm.removeItem(at:missing)
  guard service.selectedRootPreflight() == nil else { throw StorageLocationError(message:"missing selected storage was accepted") }
  print("StorageLocationChecks passed")
 }
}
