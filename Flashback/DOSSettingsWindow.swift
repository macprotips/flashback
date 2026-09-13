// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import SwiftUI

@MainActor final class DOSSettingsWindow: NSWindowController, NSWindowDelegate {
  var onClose: (() -> Void)?
  init(game: Game, model: LibraryModel) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "DOS Settings"
    window.minSize = NSSize(width: 720, height: 580)
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.contentView = NSHostingView(rootView: DOSSettingsView(game: game, model: model))
    super.init(window: window)
    window.delegate = self
    window.center()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  func windowWillClose(_ notification: Notification) { onClose?() }
}

private enum DOSPage: String, CaseIterable, Identifiable {
  case game = "Game"
  case discs = "Discs"
  case saves = "Saves"
  case help = "Help"
  var id: String { rawValue }
  var icon: String {
    switch self {
    case .game: "gamecontroller"
    case .discs: "opticaldisc"
    case .saves: "externaldrive"
    case .help: "questionmark.circle"
    }
  }
}

private struct DOSSettingsView: View {
  let game: Game
  @ObservedObject var model: LibraryModel
  @State private var page: DOSPage = .game
  @State private var options = DOSOptions.defaults
  @State private var volume = 1.0
  @State private var entries: [String] = []
  @State private var setupEntry = ""
  @State private var arguments = ""
  @State private var backups: [URL] = []
  @State private var selectedBackup = ""
  @State private var message = ""
  @State private var busy = false
  @State private var loaded = false
  @State private var confirmReset = false
  @State private var confirmRestore = false
  @State private var errorText: String?
  private let purple = Color(red: 0.43, green: 0.24, blue: 0.74)
  private var saves: URL { model.library.root.appendingPathComponent("Native Saves/" + game.id) }
  private var running: Bool { model.nativeSessions[game.id] != nil }
  private var locked: Bool {
    running || busy || !model.canWrite || model.dosMaintenance.contains(game.id)
  }

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      VStack(spacing: 0) {
        header
        Divider()
        detail.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(minWidth: 720, minHeight: 580).tint(purple).task { await refresh() }
    .alert(
      "DOS settings",
      isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
    ) {
      Button("OK") { errorText = nil }
    } message: {
      Text(errorText ?? "")
    }
    .confirmationDialog(
      "Start with the original game data?", isPresented: $confirmReset, titleVisibility: .visible
    ) {
      Button("Back Up Current Data and Reset") {
        replaceData(with: model.library.folder(for: game))
      }
    } message: {
      Text("The current game files and saves will be kept in a backup. DOS settings are kept.")
    }
    .confirmationDialog(
      "Restore this backup?", isPresented: $confirmRestore, titleVisibility: .visible
    ) {
      Button("Back Up Current Data and Restore") {
        if let source = backups.first(where: { $0.path == selectedBackup }) {
          replaceData(with: source)
        }
      }
    } message: {
      Text(
        "Your current game files and saves will be backed up before the selected backup replaces them."
      )
    }
  }
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("DOS GAME").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(
        .horizontal, 18
      ).padding(.top, 20).padding(.bottom, 6)
      ForEach(DOSPage.allCases) { item in
        Button {
          page = item
        } label: {
          Label(item.rawValue, systemImage: item.icon).frame(
            maxWidth: .infinity, alignment: .leading
          ).padding(.horizontal, 12).padding(.vertical, 8)
        }.buttonStyle(.plain).foregroundStyle(page == item ? .white : .primary).background(
          RoundedRectangle(cornerRadius: 7).fill(page == item ? purple : .clear)
        ).padding(.horizontal, 8)
      }
      Spacer()
      if busy { ProgressView().controlSize(.small).padding(18) }
    }.frame(width: 158).background(Color(nsColor: .windowBackgroundColor))
  }
  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(game.title).font(.title2.weight(.semibold)).lineLimit(1).truncationMode(.tail)
      Text(
        running
          ? "Close the game before changing settings or game data."
          : "Changes apply the next time you play."
      ).font(.callout).foregroundStyle(running ? .orange : .secondary).fixedSize(
        horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 26).padding(
      .vertical, 18)
  }
  @ViewBuilder private var detail: some View {
    switch page {
    case .game: gameSettings
    case .discs: DOSDiscsView(game: game, model: model, locked: locked)
    case .saves: saveSettings
    case .help: DOSControlsView()
    }
  }
  private var gameSettings: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          DOSCard("Performance & display") {
            Picker(
              "CPU speed",
              selection: Binding(
                get: {
                  if case .fixed = options.speed { return true }
                  return false
                }, set: { options.speed = $0 ? .fixed(3000) : .automatic })
            ) {
              Text("Automatic").tag(false)
              Text("Fixed").tag(true)
            }
            if case .fixed(let cycles) = options.speed {
              HStack {
                Text("Cycles")
                Spacer()
                TextField(
                  "Cycles", value: Binding(get: { cycles }, set: { options.speed = .fixed($0) }),
                  format: .number
                ).multilineTextAlignment(.trailing).frame(width: 120)
              }
              Text("Start around 3,000. Lower it if timing runs too fast.").caption
            }
            Toggle("Start in full screen", isOn: $options.fullscreen)
          }
          DOSCard("Sound & input") {
            Toggle("Sound enabled", isOn: $options.soundEnabled)
            HStack {
              Text("Game volume")
              Slider(value: $volume, in: 0...1).accessibilityLabel("Game volume")
              Text("\(Int((volume * 100).rounded()))%").monospacedDigit().frame(
                width: 38, alignment: .trailing)
            }.disabled(!options.soundEnabled)
            Picker("MIDI music", selection: $options.midi) {
              Text("Mac synthesizer (General MIDI)").tag(DOSOptions.MIDI.coreaudio)
              Text("Off / use AdLib in game setup").tag(DOSOptions.MIDI.none)
            }.disabled(!options.soundEnabled)
            if options.midi == .coreaudio && options.soundEnabled {
              Text("Mac synthesizer MIDI follows your Mac’s output volume.").caption
            }
            Toggle("Capture mouse on click", isOn: $options.mouseCapture)
            Text("Release or capture the pointer with Command–F10.").caption
          }
          DisclosureGroup("Advanced launch options") {
            VStack(alignment: .leading, spacing: 12) {
              Picker(
                "Play starts",
                selection: Binding(
                  get: { options.launchEntry ?? game.entry },
                  set: { options.launchEntry = $0 == game.entry ? nil : $0 })
              ) {
                ForEach(Array(Set(entries + [game.entry])).sorted(), id: \.self) {
                  Text($0).tag($0)
                }
              }
              TextField(
                "Launch arguments", text: $arguments, prompt: Text("Optional, separated by spaces"))
              Text(
                "Use simple arguments such as -nosound or /level:2. Quotes and command chaining are not supported."
              ).caption
            }.padding(.top, 8)
          }.padding(.horizontal, 4)
          DisclosureGroup("Setup tools") {
            VStack(alignment: .leading, spacing: 10) {
              Picker("Program", selection: $setupEntry) {
                Text("Choose a program").tag("")
                ForEach(entries, id: \.self) { Text($0).tag($0) }
              }
              HStack {
                Button("Run Selected Program") { launch(.program(setupEntry)) }.disabled(
                  setupEntry.isEmpty)
                Button("Open DOS Prompt") { launch(.prompt) }
              }
              Text(
                "Setup uses the same writable files as Play. Attached discs are available at the DOS prompt."
              ).caption
            }.padding(.top, 8)
          }.padding(.horizontal, 4)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).disabled(locked || !loaded)
      }
      Divider()
      if !message.isEmpty {
        Text(message).font(.caption).foregroundStyle(.secondary).frame(
          maxWidth: .infinity, alignment: .leading
        ).padding(.horizontal, 24).padding(.top, 8)
      }
      HStack {
        Button("Restore Defaults") {
          options = .defaults
          volume = 1
          arguments = ""
        }
        Spacer()
        Button("Save Settings") { saveOptions() }.buttonStyle(.borderedProminent).tint(purple)
      }.padding(.horizontal, 24).padding(.vertical, 14).disabled(locked || !loaded)
    }
  }
  private var saveSettings: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        DOSCard("Game saves") {
          Text(
            "Use the game’s own Save and Load commands. Flashback keeps its writable C: drive between sessions; it does not provide emulator save states."
          ).caption
          HStack {
            Button("Show Save Files") { revealSaves() }
            Button("Back Up Game Data") { snapshot() }.disabled(
              locked
                || !FileManager.default.fileExists(
                  atPath: saves.appendingPathComponent("Files").path)
            )
          }
        }
        DOSCard("Restore a backup") {
          Picker("Saved backup", selection: $selectedBackup) {
            Text("Choose a backup").tag("")
            ForEach(backups, id: \.path) { Text($0.lastPathComponent).tag($0.path) }
          }
          Button("Restore Selected Backup…") { confirmRestore = true }.disabled(
            locked || selectedBackup.isEmpty)
          Text("Current files are backed up before this restore replaces them.").caption
        }
        DOSCard("Start fresh") {
          Button("Reset Game Data…", role: .destructive) { confirmReset = true }.disabled(locked)
          Text(
            "Reset keeps a backup of your current files. Settings and attached discs stay in place."
          ).caption
        }
        if !message.isEmpty { Text(message).caption }
      }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private func refresh() async {
    busy = true
    let saves = saves
    let source = model.library.folder(for: game)
    do {
      let result = try await Task.detached(priority: .userInitiated) {
        let working = saves.appendingPathComponent("Files")
        return (
          try DOSOptions.load(from: saves),
          try DOSOptions.executableEntries(
            in: FileManager.default.fileExists(atPath: working.path) ? working : source),
          try DOSGameData.backups(in: saves)
        )
      }.value
      options = result.0
      volume = model.games.first(where: { $0.id == game.id })?.playbackVolume ?? game.playbackVolume
      arguments = options.launchArguments.joined(separator: " ")
      entries = result.1
      backups = result.2
      setupEntry =
        entries.first(where: {
          ["setup", "install", "setsound", "sound"].contains(
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.lowercased())
        }) ?? ""
      loaded = true
    } catch {
      errorText = error.localizedDescription
      loaded = true
    }
    busy = false
  }
  @discardableResult private func saveOptions() -> Bool {
    guard !locked else { return false }
    do {
      options.launchArguments = arguments.split(whereSeparator: { $0.isWhitespace }).map(
        String.init)
      try options.save(to: saves)
      model.setVolume(volume, for: game)
      message = "Settings saved for the next launch."
      return true
    } catch {
      errorText = error.localizedDescription
      return false
    }
  }
  private func launch(_ mode: DOSLaunchMode) {
    guard saveOptions() else { return }
    model.play(game, dosMode: mode)
  }
  private func revealSaves() {
    do {
      try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
      NSWorkspace.shared.open(saves)
    } catch { errorText = error.localizedDescription }
  }
  private func snapshot() {
    guard !locked else { return }
    busy = true
    model.dosMaintenance.insert(game.id)
    let saves = saves
    Task {
      do {
        let result = try await Task.detached { try DOSGameData.backup(in: saves) }.value
        backups = try DOSGameData.backups(in: saves)
        selectedBackup = result.path
        message = "Game data backed up."
      } catch { errorText = error.localizedDescription }
      busy = false
      model.dosMaintenance.remove(game.id)
    }
  }
  private func replaceData(with source: URL) {
    guard !locked else { return }
    busy = true
    model.dosMaintenance.insert(game.id)
    let saves = saves
    Task {
      do {
        _ = try await Task.detached { try DOSGameData.replace(in: saves, with: source) }.value
        message = "Game data replaced. Your previous data is available under Saved backup."
      } catch { errorText = error.localizedDescription }
      busy = false
      model.dosMaintenance.remove(game.id)
      await refresh()
    }
  }
}
private struct DOSCard<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content
  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      Text(title).font(.headline)
      content
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(
      RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor))
    ).overlay(
      RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor).opacity(0.35)))
  }
}
extension View {
  fileprivate var caption: some View {
    font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
  }
}
struct DOSControlsView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        DOSCard("While the DOS game window is active") {
          Text("Hold Fn too if an F-key controls brightness or volume.").caption
          Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 9) {
            row("Full screen", "Option–Return")
            row("Pause / resume", "Command–P")
            row("Release / capture mouse", "Command–F10")
            row("Remap keyboard or controller", "Command–F1")
            row("Slower / faster CPU", "Command–F11 / F12")
            row("Next attached disc", "Command–F4")
            row("Mute emulator audio", "Command–F8")
            row("Screenshot", "Command–F5")
          }
        }
        DOSCard("If a game won’t start") {
          Text(
            "Choose the correct program in Game, or run SETUP to select sound and graphics. Attach required media in Discs, then relaunch."
          ).caption
          Text("The latest launch log, captures, and control mappings are in Show Save Files.")
            .caption
          Text(
            "Connect controllers before launching, then use Command–F1 to map their buttons. The Mac MIDI synthesizer has separate audio; silence it with the game’s music setting or turn Sound off before relaunching."
          ).caption
        }
      }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  private func row(_ a: String, _ k: String) -> some View {
    GridRow {
      Text(a)
      Text(k).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
    }
  }
}
