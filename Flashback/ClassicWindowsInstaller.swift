// SPDX-License-Identifier: GPL-3.0-only
import Cocoa

/// Setup only. A running emulator is deliberately not an installed/ready game.
@MainActor final class ClassicWindowsInstaller: ObservableObject {
    @Published private(set) var status = ""
    @Published private(set) var running = false
    private var process: Process?
    private var parentPipe: Pipe?
    private var log: FileHandle?

    func start(media: URL, storage: URL, resources: URL, resume: Bool) async {
        guard !running else { return }
        running = true
        status = resume ? "Starting Windows setup again…" : "Preparing Windows setup…"
        do {
            let fm = FileManager.default
            let runtime = resources.appendingPathComponent("ClassicWindows/dosbox-x.app")
            let executable = runtime.appendingPathComponent("Contents/MacOS/dosbox-x")
            let helper = resources.deletingLastPathComponent().appendingPathComponent("MacOS/NativeHost")
            guard fm.isExecutableFile(atPath: executable.path), fm.isExecutableFile(atPath: helper.path) else {
                throw LibraryError("The Classic Windows runtime is missing from this development build.")
            }
            let session = storage.appendingPathComponent("ClassicWindows/Windows98", isDirectory:true)
            try fm.createDirectory(at: session, withIntermediateDirectories:true)
            let disk = session.appendingPathComponent("Windows98.img")
            let configuration = session.appendingPathComponent("setup.conf")
            let logURL = session.appendingPathComponent("setup.log")
            let paths = [disk, media, configuration, session]
            guard paths.allSatisfy({ !$0.path.unicodeScalars.contains(where:{ $0.value < 32 || $0.value == 127 || $0.value == 34 || $0.value == 37 }) }) else {
                throw LibraryError("Choose a setup storage folder without quotes, percent signs, or control characters.")
            }
            var commands: [String] = []
            if !fm.fileExists(atPath: disk.path) {
                guard !resume else { throw LibraryError("There is no Windows installation to resume.") }
                commands.append("imgmake \"\(disk.path)\" -t hd_2gig -fat 16")
            } else if !resume {
                throw LibraryError("Windows setup has already been started. Use Continue Setup to resume it.")
            }
            commands += ["imgmount c \"\(disk.path)\"", "imgmount d \"\(media.path)\" -t iso", "mount e \"\(session.path)\""]
            if resume { commands.append("boot c:") }
            else { commands += ["if exist c:\\windows\\win.com goto bootwindows", "xcopy d:\\win98 c:\\win98 /i /e", "c:", "cd \\win98", "setup /is", ":bootwindows", "if exist c:\\windows\\win.com boot c:"] }
            let config = """
            [sdl]
            ; Windows setup uses absolute desktop controls. Do not change input
            ; mode between a button-down and button-up event.
            autolock=false
            fullscreen=false
            sensitivity=100
            usesystemcursor=true
            mouse_emulation=integration
            windowresolution=original
            output=opengl
            ; Flashback owns the emulator lifecycle. A native confirmation
            ; dialog can outlive DOSBox-X and keep the private disk mounted.
            quit warning=false
            startbanner=false
            [dosbox]
            title=Flashback Windows Setup
            memsize=128
            [dos]
            ver=7.1
            hard drive data rate limit=0
            [cpu]
            core=normal
            cputype=pentium_mmx
            cycles=max
            [video]
            vmemsize=8
            [sblaster]
            sbtype=sb16vibra
            [ide, primary]
            int13fakeio=true
            int13fakev86io=true
            [ide, secondary]
            int13fakeio=true
            int13fakev86io=true
            [autoexec]
            \(commands.joined(separator:"\n"))

            """
            try Data(config.utf8).write(to:configuration, options:.atomic)
            if !fm.fileExists(atPath:logURL.path) { fm.createFile(atPath:logURL.path,contents:nil) }
            let output = try FileHandle(forWritingTo:logURL)
            try output.seekToEnd()
            let pipe = Pipe(), child = Process()
            child.executableURL = helper
            child.arguments = ["--profile",resources.appendingPathComponent("ClassicWindows.policy").path,
                               "--runtime",runtime.path,"--executable",executable.path,
                               "--game",media.deletingLastPathComponent().path,"--saves",session.path,"--",
                               "-defaultconf","-defaultmapper","-nopromptfolder","-conf",configuration.path]
            child.standardInput = pipe
            child.standardOutput = output
            child.standardError = output
            child.environment = ["PATH":"/usr/bin:/bin","LANG":"en_US.UTF-8"]
            child.terminationHandler = { [weak self] child in
                Task { @MainActor in
                    guard let self else { return }
                    self.running = false
                    self.status = child.terminationStatus == 0
                        ? "Setup window closed. Resume setup if Windows still needs to finish installing."
                        : "Setup stopped. The installation disk has been kept so you can resume. See setup.log for details."
                    try? self.log?.close(); self.log = nil; self.parentPipe = nil; self.process = nil
                }
            }
            process = child; parentPipe = pipe; log = output
            try child.run()
            status = "Complete Windows setup in the window that opens. Windows may restart several times. If the window closes early, choose Continue Setup to resume."
        } catch {
            running = false; status = error.localizedDescription
            try? log?.close(); log = nil; parentPipe = nil; process = nil
        }
    }
}
