// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

/// A deliberately small, fail-closed registry for launch quirks that are
/// unique to one known Shockwave movie. A displayed title is never an input to
/// matching: a profile can activate only for the SHA-256 of the imported entry.
struct ShockwaveCompatibility {
    struct Profile: Equatable {
        let id: String
        let entrySHA256: String
        let parameters: [String:String]
    }

    struct Applied: Equatable {
        let id: String
        let entrySHA256: String
        let parameters: [String:String]
    }

    private struct Registry: Decodable {
        let version: Int
        let profiles: [ProfileRecord]
    }

    private struct ProfileRecord: Decodable {
        let id: String
        let entrySHA256: String
        let parameters: [String:String]
    }

    private let profilesByHash: [String:Profile]
    let loadError: String?

    static let shared = ShockwaveCompatibility(bundle: .main)

    init(bundle: Bundle) {
        guard let url = bundle.url(forResource:"shockwave-compat-profiles", withExtension:"json") else {
            profilesByHash = [:]
            loadError = "Shockwave compatibility profiles are unavailable."
            return
        }
        do {
            self = try Self(data:Data(contentsOf:url))
        } catch {
            profilesByHash = [:]
            loadError = "Shockwave compatibility profiles were rejected: \(error.localizedDescription)"
        }
    }

    init(data: Data) throws {
        guard data.count <= 1_048_576 else { throw CompatibilityError.invalidRegistry("Registry is too large") }
        let registry = try JSONDecoder().decode(Registry.self,from:data)
        guard registry.version == 1 else { throw CompatibilityError.invalidRegistry("Unsupported registry version") }
        guard registry.profiles.count <= 128 else { throw CompatibilityError.invalidRegistry("Too many profiles") }
        var byHash: [String:Profile] = [:]
        var ids = Set<String>()
        for record in registry.profiles {
            let profile = try Self.validate(record)
            guard ids.insert(profile.id).inserted else { throw CompatibilityError.invalidRegistry("Duplicate profile id") }
            guard byHash[profile.entrySHA256] == nil else { throw CompatibilityError.invalidRegistry("Duplicate entry hash") }
            byHash[profile.entrySHA256] = profile
        }
        profilesByHash = byHash
        loadError = nil
    }

    func profile(forEntry file: URL) -> Applied? {
        guard let hash = Self.entrySHA256(file) else { return nil }
        return profile(forEntryHash:hash)
    }

    static func entrySHA256(_ file: URL) -> String? { try? hash(file) }

    func profile(forEntryHash hash: String) -> Applied? {
        guard let profile = profilesByHash[hash] else { return nil }
        return Applied(id:profile.id,entrySHA256:profile.entrySHA256,parameters:profile.parameters)
    }

    private static func validate(_ record: ProfileRecord) throws -> Profile {
        guard matches(record.id,"[a-z0-9][a-z0-9._-]{0,63}") else {
            throw CompatibilityError.invalidRegistry("Unsafe profile id")
        }
        guard matches(record.entrySHA256,"[0-9a-f]{64}") else {
            throw CompatibilityError.invalidRegistry("Invalid entry hash")
        }
        guard record.parameters.count <= 32 else { throw CompatibilityError.invalidRegistry("Too many parameter overrides") }
        for (name,value) in record.parameters {
            guard matches(name,"[A-Za-z][A-Za-z0-9_.-]{0,127}"),
                  name.caseInsensitiveCompare("src") != .orderedSame,
                  !value.contains(where:{ $0 == "\0" || $0.isNewline }), value.utf8.count <= 4096 else {
                throw CompatibilityError.invalidRegistry("Unsafe parameter override")
            }
        }
        return Profile(id:record.id,entrySHA256:record.entrySHA256,parameters:record.parameters)
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of:"^(?:\(pattern))$",options:.regularExpression) == value.startIndex..<value.endIndex
    }

    private static func hash(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom:file)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount:65_536), !data.isEmpty { digest.update(data:data) }
        return digest.finalize().map { String(format:"%02x",$0) }.joined()
    }

    enum CompatibilityError: LocalizedError {
        case invalidRegistry(String)
        var errorDescription: String? {
            switch self { case .invalidRegistry(let message): return message }
        }
    }

    /// Small authored checks for the most important safety boundary. These run
    /// in the build before the app is packaged, without using a real game.
    static func authoredChecks() throws {
        let entry = Data("profile-test-entry".utf8)
        let hash = SHA256.hash(data:entry).map { String(format:"%02x",$0) }.joined()
        let registry = """
        {"version":1,"profiles":[{"id":"test.launch-parameters","entrySHA256":"\(hash)","parameters":{"sw1":"#start","basePath":"assets"}}]}
        """
        let loaded = try Self(data:Data(registry.utf8))
        guard loaded.profile(forEntryHash:hash) == Applied(id:"test.launch-parameters",entrySHA256:hash,parameters:["sw1":"#start","basePath":"assets"]) else {
            throw CompatibilityError.invalidRegistry("Matching profile was not applied")
        }
        let controlHash = SHA256.hash(data:Data("profile-control-entry".utf8)).map { String(format:"%02x",$0) }.joined()
        guard loaded.profile(forEntryHash:controlHash) == nil else {
            throw CompatibilityError.invalidRegistry("Profile activated for a non-matching entry")
        }
        let duplicate = """
        {"version":1,"profiles":[{"id":"first","entrySHA256":"\(hash)","parameters":{}},{"id":"second","entrySHA256":"\(hash)","parameters":{}}]}
        """
        guard (try? Self(data:Data(duplicate.utf8))) == nil else {
            throw CompatibilityError.invalidRegistry("Duplicate hashes were accepted")
        }
        let unsafe = """
        {"version":1,"profiles":[{"id":"unsafe","entrySHA256":"\(hash)","parameters":{"src":"different.dcr"}}]}
        """
        guard (try? Self(data:Data(unsafe.utf8))) == nil else {
            throw CompatibilityError.invalidRegistry("Unsafe parameters were accepted")
        }
        guard (try? Self(data:Data("{\"version\":\"one\",\"profiles\":[]}".utf8))) == nil else {
            throw CompatibilityError.invalidRegistry("Malformed registry was accepted")
        }
    }
}

#if SHOCKWAVE_COMPAT_CHECK
@main enum ShockwaveCompatibilityChecks {
    static func main() throws {
        try ShockwaveCompatibility.authoredChecks()
        print("PASS: Shockwave compatibility profiles require an exact entry SHA-256 and reject duplicate or unsafe profiles")
    }
}
#endif
