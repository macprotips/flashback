// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class ClassicWindowsSetupModel: ObservableObject {
    enum Phase: Equatable { case checking, needsMedia, importing, ready(URL), failed(String) }
    @Published private(set) var phase: Phase = .checking
    private let setup: ClassicWindowsSetup
    private let onMediaReady: (URL) -> Void
    private var importTask: Task<Void, Never>?

    init(storageRoot: URL, onMediaReady: @escaping (URL) -> Void = { _ in }) {
        setup = ClassicWindowsSetup(storageRoot: storageRoot)
        self.onMediaReady = onMediaReady
        Task { await refresh() }
    }

    func refresh() async {
        do {
            let image = try await setup.selectedValidatedImage()
            phase = .ready(image)
        } catch { phase = .needsMedia }
    }

    func importImage(_ url: URL) {
        guard importTask == nil else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        phase = .importing
        importTask = Task { @MainActor [weak self] in
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
                self?.importTask = nil
            }
            guard let self else { return }
            do {
                _ = try await self.setup.importISO(at: url)
                let image = try await self.setup.selectedValidatedImage()
                self.phase = .ready(image)
            } catch { self.phase = .failed(error.localizedDescription) }
        }
    }

    func cancelImport() { importTask?.cancel() }

    func continueSetup() {
        guard case let .ready(image) = phase else { return }
        onMediaReady(image)
    }

    func clear() {
        Task {
            do { try await setup.clearImportedMedia(); phase = .needsMedia }
            catch { phase = .failed(error.localizedDescription) }
        }
    }
}

@MainActor private final class ClassicWindowsSetupFilePicker: ObservableObject {
    @Published var isShowing = false
}

struct ClassicWindowsSetupView: View {
    @StateObject private var model: ClassicWindowsSetupModel
    @StateObject private var filePicker = ClassicWindowsSetupFilePicker()

    init(storageRoot: URL, onMediaReady: @escaping (URL) -> Void = { _ in }) {
        _model = StateObject(wrappedValue: ClassicWindowsSetupModel(storageRoot: storageRoot, onMediaReady: onMediaReady))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up Windows 98").font(.title2.weight(.semibold))
            Text("Choose your own Windows 98 ISO. Flashback checks for the setup files and copies the image into your game storage before setup begins.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal:false,vertical:true)
            content
        }
        .padding(24)
        .frame(maxWidth: 540, alignment: .leading)
        .fileImporter(isPresented: $filePicker.isShowing, allowedContentTypes: [UTType(filenameExtension: "iso") ?? .data], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first { model.importImage(url) }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .checking: ProgressView("Checking setup media…")
        case .importing:
            ProgressView("Copying your ISO into game storage…")
            Button("Cancel import", role: .cancel, action: model.cancelImport)
        case let .ready(url):
            Label("Windows 98 setup media is ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
            Text("Windows is not installed yet.").foregroundStyle(.secondary)
            Button("Continue Setup", action: model.continueSetup)
            Button("Remove setup media", role: .destructive, action: model.clear)
        case .needsMedia, .failed:
            if case let .failed(message) = model.phase { Text(message).foregroundStyle(.red) }
            VStack(spacing: 10) {
                Image(systemName: "opticaldisc").font(.system(size: 34)).foregroundStyle(.secondary)
                Text("Drop a Windows 98 ISO here")
                Button("Choose ISO…") { filePicker.isShowing = true }
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [6])))
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                    let url = (value as? URL) ?? (value as? Data).flatMap { URL(dataRepresentation:$0,relativeTo:nil) }
                    guard let url else { return }
                    Task { @MainActor in model.importImage(url) }
                }
                return true
            }
        }
    }
}
