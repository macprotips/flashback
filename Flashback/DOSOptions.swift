// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The small, supported subset of DOSBox Staging 0.83 settings that can vary
/// per imported game. This is deliberately not a general DOSBox config editor.
struct DOSOptions: Codable, Equatable, Sendable {
    enum Speed: Codable, Equatable, Sendable {
        case automatic
        case fixed(Int)

        private enum CodingKeys: String, CodingKey { case kind, cycles }
        private enum Kind: String, Codable { case automatic, fixed }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy:CodingKeys.self)
            switch try values.decode(Kind.self, forKey:.kind) {
            case .automatic: self = .automatic
            case .fixed: self = .fixed(try values.decode(Int.self, forKey:.cycles))
            }
            try validate()
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy:CodingKeys.self)
            switch self {
            case .automatic: try values.encode(Kind.automatic, forKey:.kind)
            case .fixed(let cycles):
                try values.encode(Kind.fixed, forKey:.kind)
                try values.encode(cycles, forKey:.cycles)
            }
        }

        func validate() throws {
            if case .fixed(let cycles) = self,
               !(DOSOptions.minimumCycles...DOSOptions.maximumCycles).contains(cycles) {
                throw LibraryError("DOS CPU speed must be between \(DOSOptions.minimumCycles) and \(DOSOptions.maximumCycles) cycles.")
            }
        }
    }

    enum MIDI: String, Codable, Equatable, Sendable {
        case none
        case coreaudio
    }

    static let minimumCycles = 50
    static let maximumCycles = 2_000_000
    static let defaults = DOSOptions()

    var speed: Speed = .automatic
    var fullscreen = false
    var soundEnabled = true
    /// macOS's built-in DLS synthesizer; no external sound font or ROM is used.
    var midi: MIDI = .coreaudio
    /// When off, use DOSBox Staging's `seamless` mode instead of its default
    /// click-to-capture mode.
    var mouseCapture = true
    /// A per-game replacement for the library entry, such as a setup program.
    /// It remains constrained to a verified DOS 8.3 executable at launch.
    var launchEntry: String?
    /// Pre-tokenized DOS arguments. No shell-style parsing is performed.
    var launchArguments: [String] = []

    init(speed: Speed = .automatic, fullscreen: Bool = false, soundEnabled: Bool = true,
         midi: MIDI = .coreaudio, mouseCapture: Bool = true, launchEntry: String? = nil,
         launchArguments: [String] = []) {
        self.speed = speed
        self.fullscreen = fullscreen
        self.soundEnabled = soundEnabled
        self.midi = midi
        self.mouseCapture = mouseCapture
        self.launchEntry = launchEntry
        self.launchArguments = launchArguments
    }

    private enum CodingKeys: String, CodingKey { case speed, fullscreen, soundEnabled, midi, mouseCapture, launchEntry, launchArguments }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        speed = try values.decode(Speed.self, forKey:.speed)
        fullscreen = try values.decode(Bool.self, forKey:.fullscreen)
        soundEnabled = try values.decode(Bool.self, forKey:.soundEnabled)
        midi = try values.decodeIfPresent(MIDI.self, forKey:.midi) ?? .coreaudio
        mouseCapture = try values.decode(Bool.self, forKey:.mouseCapture)
        launchEntry = try values.decodeIfPresent(String.self, forKey:.launchEntry)
        launchArguments = try values.decodeIfPresent([String].self, forKey:.launchArguments) ?? []
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy:CodingKeys.self)
        try values.encode(speed, forKey:.speed)
        try values.encode(fullscreen, forKey:.fullscreen)
        try values.encode(soundEnabled, forKey:.soundEnabled)
        try values.encode(midi, forKey:.midi)
        try values.encode(mouseCapture, forKey:.mouseCapture)
        try values.encodeIfPresent(launchEntry, forKey:.launchEntry)
        try values.encode(launchArguments, forKey:.launchArguments)
    }

    static func optionsURL(in saves: URL) -> URL {
        saves.appendingPathComponent("dos-options.json")
    }

    static func load(from saves: URL) throws -> Self {
        let file = optionsURL(in:saves)
        guard FileManager.default.fileExists(atPath:file.path) else { return .defaults }
        let info = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 16_384 else {
            throw LibraryError("The DOS settings file is invalid or too large. Use Restore Default Settings, then Save Settings.")
        }
        do { return try JSONDecoder().decode(Self.self, from:Data(contentsOf:file)) }
        catch let error as LibraryError { throw error }
        catch { throw LibraryError("The DOS options for this game are damaged. Open DOS Settings, choose Restore Default Settings, then Save Settings.") }
    }

    func save(to saves: URL) throws {
        try validate()
        try FileManager.default.createDirectory(at:saves,withIntermediateDirectories:true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(self).write(to:Self.optionsURL(in:saves),options:.atomic)
    }

    /// Settings use current DOSBox Staging 0.83 names: `[sdl] fullscreen`,
    /// `[mixer] nosound`, `[mouse] mouse_capture`, and `[cpu] cpu_cycles`.
    /// Automatic speed intentionally omits `cpu_cycles`, retaining Staging's
    /// bundled default rather than using its unsafe `max` option.
    func configText(saves: URL? = nil) throws -> String {
        try validate()
        var cpu = "[cpu]"
        if case .fixed(let cycles) = speed { cpu += "\ncpu_cycles = \(cycles)" }
        let mapper = try saves.map { try safeConfigPath($0.appendingPathComponent("mapper.map")) }
        let captures = try saves.map { try safeConfigPath($0.appendingPathComponent("Captures",isDirectory:true)) }
        let mapperSetting = mapper.map { "\nmapperfile = \($0)" } ?? ""
        let captureSetting = captures.map { "[capture]\ncapture_dir = \($0)\n" } ?? ""
        return """
        [sdl]
        fullscreen = \(fullscreen ? "true" : "false")
        window_size = 960x720
        \(mapperSetting)
        [dosbox]
        machine = svga_s3
        memsize = 16
        \(cpu)
        [mixer]
        nosound = \(soundEnabled ? "false" : "true")
        [mouse]
        mouse_capture = \(mouseCapture ? "onclick" : "seamless")
        \(captureSetting)
        [midi]
        mididevice = \(soundEnabled ? midi.rawValue : MIDI.none.rawValue)
        [ipx]
        ipx = false
        [autoexec]
        """
    }

    func validate() throws {
        try speed.validate()
        if let launchEntry, !Self.isDOSPath(launchEntry) {
            throw LibraryError("The selected DOS program must use safe 8.3 path components.")
        }
        guard launchArguments.count <= 16,
              launchArguments.allSatisfy(Self.isSafeArgument) else {
            throw LibraryError("DOS launch arguments must be up to 16 simple tokens without spaces or command characters.")
        }
    }

    private static func isSafeArgument(_ argument: String) -> Bool {
        guard !argument.isEmpty, argument.utf8.count <= 64 else { return false }
        return argument.range(of:#"^[A-Za-z0-9_./:=+-]+$"#,options:.regularExpression) != nil
    }

    private func safeConfigPath(_ path: URL) throws -> String {
        let value = path.standardizedFileURL.resolvingSymlinksInPath().path
        guard value.rangeOfCharacter(from:CharacterSet(charactersIn:"\"\n\r")) == nil else {
            throw LibraryError("The save folder path contains characters DOSBox cannot use.")
        }
        return value
    }

    /// Lists actual DOS executables from the private working copy. Returned
    /// paths are relative, slash-separated, and safe to use as launch targets.
    static func executableEntries(in working: URL) throws -> [String] {
        let root = working.standardizedFileURL.resolvingSymlinksInPath()
        let keys: [URLResourceKey] = [.isRegularFileKey,.isSymbolicLinkKey]
        guard let scan = FileManager.default.enumerator(at:root,includingPropertiesForKeys:keys,
                                                          options:[.skipsHiddenFiles,.skipsPackageDescendants]) else {
            throw LibraryError("The DOS game files could not be opened.")
        }
        var entries: [String] = []
        var count = 0
        for case let file as URL in scan {
            count += 1
            guard count <= 30_000 else { throw LibraryError("This DOS game folder has too many files to list.") }
            let values = try file.resourceValues(forKeys:Set(keys))
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            let canonical = file.standardizedFileURL.resolvingSymlinksInPath()
            guard canonical.path.hasPrefix(root.path + "/") else { continue }
            let relative = String(canonical.path.dropFirst(root.path.count + 1))
            guard isDOSPath(relative), try LegacyImport.isDOS(canonical) else { continue }
            entries.append(relative)
        }
        return entries.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func isDOSPath(_ path: String) -> Bool {
        let components = path.split(separator:"/",omittingEmptySubsequences:false).map(String.init)
        guard !components.isEmpty else { return false }
        // These paths are eventually interpreted by DOS's command processor,
        // so accept only plain 8.3 components, not DOS metacharacters.
        let name = #"^[A-Za-z0-9_~-]{1,8}(\.[A-Za-z0-9_~-]{1,3})?$"#
        guard components.allSatisfy({ $0.range(of:name,options:.regularExpression) != nil }) else { return false }
        return ["exe","com","bat"].contains((components.last! as NSString).pathExtension.lowercased())
    }
}

enum DOSLaunchMode: Codable, Equatable, Sendable {
    case game
    case prompt
    case program(String)

    private enum CodingKeys: String, CodingKey { case kind, program }
    private enum Kind: String, Codable { case game, prompt, program }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy:CodingKeys.self)
        switch try values.decode(Kind.self,forKey:.kind) {
        case .game: self = .game
        case .prompt: self = .prompt
        case .program: self = .program(try values.decode(String.self,forKey:.program))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy:CodingKeys.self)
        switch self {
        case .game: try values.encode(Kind.game,forKey:.kind)
        case .prompt: try values.encode(Kind.prompt,forKey:.kind)
        case .program(let program):
            try values.encode(Kind.program,forKey:.kind)
            try values.encode(program,forKey:.program)
        }
    }
}
