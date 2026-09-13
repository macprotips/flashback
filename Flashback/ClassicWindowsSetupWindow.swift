// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import SwiftUI

@MainActor private final class ClassicWindowsSetupContext: ObservableObject {
    @Published var pendingGame: Game?
    init(pendingGame: Game?) { self.pendingGame = pendingGame }
}

@MainActor final class ClassicWindowsSetupWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let context: ClassicWindowsSetupContext

    init(storageRoot: URL, resources: URL, pendingGame: Game? = nil) {
        context = ClassicWindowsSetupContext(pendingGame:pendingGame)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:520),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title = "Classic Windows Setup"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:ClassicWindowsSetupPanel(storageRoot:storageRoot,resources:resources,context:context))
        super.init(window:window)
        window.delegate = self
        window.center()
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) is not supported") }
    func setPendingGame(_ game: Game) { context.pendingGame = game }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

private struct ClassicWindowsSetupPanel: View {
    let storageRoot: URL
    let resources: URL
    @ObservedObject var context: ClassicWindowsSetupContext
    @StateObject private var installer = ClassicWindowsInstaller()
    @State private var installation: ClassicWindowsBaseInstallation = .notStarted()
    @State private var stateError: String?

    private var disk: URL { storageRoot.appendingPathComponent("ClassicWindows/Windows98/Windows98.img") }
    private var store: ClassicWindowsBaseInstallationStore { ClassicWindowsBaseInstallationStore(storageRoot:storageRoot) }

    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if let pending = context.pendingGame {
                Label("\(pending.title) needs Windows 98",systemImage:"sparkles.rectangle.stack")
                    .font(.headline).padding(.horizontal,24).padding(.top,20)
                Text("Flashback will keep this game selected while you complete the one-time Windows setup.")
                    .font(.callout).foregroundStyle(.secondary).padding(.horizontal,24)
            }
            if installation.state != .ready {
                ClassicWindowsSetupView(storageRoot:storageRoot) { media in
                    Task {
                        do {
                            let resume = FileManager.default.fileExists(atPath:disk.path)
                            installation = try await store.beginSetup(mediaImage:media,resumeDisk:resume ? disk : nil)
                            await installer.start(media:media,storage:storageRoot,resources:resources,resume:resume)
                        } catch { stateError = error.localizedDescription }
                    }
                }
                .disabled(installer.running)
            }
            if !installer.status.isEmpty {
                Text(installer.status).font(.callout).foregroundStyle(.secondary).padding(.horizontal,24)
            }
            if installation.state == .installing && !installer.running && FileManager.default.fileExists(atPath:disk.path) {
                Divider().padding(.horizontal,24)
                Text("When the Windows desktop is working").font(.headline).padding(.horizontal,24)
                Text("Shut down Windows from its Start menu, close the emulator window, then confirm here. Flashback will verify and keep the installed disk.")
                    .font(.callout).foregroundStyle(.secondary).padding(.horizontal,24)
                Button("Windows Desktop Is Ready") { markReady() }.padding(.horizontal,24)
            }
            if installation.state == .ready {
                Label("Windows 98 is ready",systemImage:"checkmark.circle.fill")
                    .foregroundStyle(.green).padding(.horizontal,24)
                if let pending = context.pendingGame {
                    Text("The Windows environment is ready for \(pending.title). Per-game installation is the next guided step and remains disabled until its private-disk checks pass.")
                        .font(.callout).foregroundStyle(.secondary).padding(.horizontal,24)
                }
            }
            if let stateError { Text(stateError).foregroundStyle(.red).padding(.horizontal,24) }
            Text("Flashback chooses the storage, disk, memory, sound, display, and input defaults. Windows may restart several times; enter your own product key when Windows asks.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal,24)
        }
        .padding(.bottom,24).frame(minWidth:620,minHeight:500)
        .task { await loadState() }
    }

    private func loadState() async {
        do { installation = try await store.installation() }
        catch { stateError = error.localizedDescription }
    }
    private func markReady() {
        Task {
            do { installation = try await store.markReady(installedDisk:disk); stateError = nil }
            catch { stateError = error.localizedDescription }
        }
    }
}
