// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import SwiftUI
import UniformTypeIdentifiers

struct DOSDiscsView: View {
  let game: Game
  @ObservedObject var model: LibraryModel
  let locked: Bool
  @State private var discs: [DOSDisc] = []
  @State private var busy = false
  @State private var message = ""
  @State private var errorText: String?
  private var saves: URL { model.library.root.appendingPathComponent("Native Saves/" + game.id) }
  private var unavailable: Bool { locked || busy || model.dosMaintenance.contains(game.id) }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        discCard("Attach media") {
          Text(
            "Attach a game’s CD or floppy images before launching. Flashback makes a private copy for this game."
          ).discCaption
          HStack {
            Button("Add CD Images…") { choose(.cd) }
            Button("Add Floppy Images…") { choose(.floppy) }
          }.disabled(unavailable)
        }
        discCard("Attached media") {
          if discs.isEmpty {
            Text("No discs attached yet.").discCaption.padding(.vertical, 4)
          } else {
            ForEach(Array(discs.enumerated()), id: \.offset) { index, disc in
              VStack(alignment: .leading, spacing: 9) {
                HStack {
                  Label(
                    disc.kind == .cd ? "CD drive D:" : "Floppy drive A:",
                    systemImage: disc.kind == .cd ? "opticaldisc" : "externaldrive"
                  ).font(.subheadline.weight(.semibold))
                  Spacer()
                  Button("Detach") { detach(index) }.disabled(unavailable)
                }
                ForEach(Array(disc.files.enumerated()), id: \.offset) { offset, file in
                  HStack(spacing: 9) {
                    Text("\(offset + 1)").font(.caption.monospacedDigit()).foregroundStyle(
                      .secondary
                    ).frame(width: 16, alignment: .trailing)
                    Text(URL(fileURLWithPath: file).lastPathComponent).lineLimit(1).truncationMode(
                      .middle
                    ).help(file)
                    Spacer(minLength: 8)
                    Button {
                      move(index, offset, -1)
                    } label: {
                      Image(systemName: "chevron.up")
                    }.buttonStyle(.borderless).disabled(unavailable || offset == 0).help(
                      "Move earlier")
                    Button {
                      move(index, offset, 1)
                    } label: {
                      Image(systemName: "chevron.down")
                    }.buttonStyle(.borderless).disabled(
                      unavailable || offset == disc.files.count - 1
                    ).help("Move later")
                  }
                }
              }.padding(12).background(
                RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .underPageBackgroundColor)))
            }
          }
        }
        if busy { ProgressView("Copying disc images…") }
        if !message.isEmpty { Text(message).discCaption }
        Text(
          "Use Command–F4 in the DOS window to cycle through attached images in order. CDs support ISO or CUE with companion tracks; floppies support IMG or IMA."
        ).discCaption
        Text("Detaching keeps copied media in Show Save Files → Media.").discCaption
      }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
    }
    .task { reload() }
    .alert(
      "Game discs",
      isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
    ) {
      Button("OK") { errorText = nil }
    } message: {
      Text(errorText ?? "")
    }
  }
  private func discCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 13) {
      Text(title).font(.headline)
      content()
    }
    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    .overlay(
      RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor).opacity(0.35)))
  }
  private func reload() {
    do { discs = try DOSDiscs.load(from: saves) } catch { errorText = error.localizedDescription }
  }
  private func choose(_ kind: DOSDiscKind) {
    guard !unavailable else { return }
    let panel = NSOpenPanel()
    panel.title = kind == .cd ? "Add CD Images" : "Add Floppy Images"
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = (kind == .cd ? ["iso", "cue"] : ["img", "ima"]).compactMap {
      UTType(filenameExtension: $0)
    }
    panel.message =
      "Select images for this game. They are initially ordered by filename; use the arrows to change their order."
    guard panel.runModal() == .OK else { return }
    let urls = panel.urls.sorted {
      $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
    let saves = saves
    busy = true
    model.dosMaintenance.insert(game.id)
    Task {
      do {
        let result = try await Task.detached(priority: .userInitiated) {
          let imported = try DOSDiscs.importMedia(urls: urls, into: saves, kind: kind)
          var records = try DOSDiscs.load(from: saves)
          if let index = records.firstIndex(where: { $0.kind == kind }) {
            records[index] = DOSDisc(kind: kind, files: records[index].files + imported.files)
          } else {
            records.append(imported)
          }
          try DOSDiscs.save(records, to: saves)
          return records
        }.value
        discs = result
        message = "Discs attached for the next launch."
      } catch { errorText = error.localizedDescription }
      busy = false
      model.dosMaintenance.remove(game.id)
    }
  }
  private func detach(_ index: Int) {
    guard !unavailable else { return }
    var next = discs
    next.remove(at: index)
    do {
      try DOSDiscs.save(next, to: saves)
      discs = next
      message = "Media detached. Its private copy is still in the save folder."
    } catch { errorText = error.localizedDescription }
  }
  private func move(_ index: Int, _ offset: Int, _ delta: Int) {
    guard !unavailable else { return }
    var files = discs[index].files
    files.swapAt(offset, offset + delta)
    var next = discs
    next[index] = DOSDisc(kind: next[index].kind, files: files)
    do {
      try DOSDiscs.save(next, to: saves)
      discs = next
      message = "Disc order saved."
    } catch { errorText = error.localizedDescription }
  }
}

extension View {
  fileprivate var discCaption: some View {
    font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
  }
}
