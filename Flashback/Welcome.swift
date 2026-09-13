// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import SwiftUI

struct WelcomeView: View {
    let start: () -> Void
    let website: () -> Void

    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:17) {
                Image(nsImage:BrandArtwork.mark(size:48)).foregroundStyle(.primary).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:6) {
                    Text("Welcome to Flashback").font(.system(size:25,weight:.semibold))
                    Text("Play your collection of classic games on Mac.")
                        .font(.system(size:13)).foregroundStyle(.secondary)
                }
            }.padding(.bottom,30)
            VStack(alignment:.leading,spacing:25) {
                feature("Play classic games",icon:"gamecontroller") {
                    HStack(alignment:.top,spacing:23) {
                        format("Flash",detail:".swf")
                        format("Java",detail:"Apps, applets, mobile")
                        format("HTML5",detail:".html")
                        format("Shockwave",detail:"Experimental")
                    }.padding(.vertical,2)
                    Text("DOS and detected classic Director games are also supported. Add a game file, folder, or ZIP to include its graphics and sounds.")
                }
                feature("Import from a website",icon:"globe") {
                    Text("Paste a game page. Review the recovered files, then add the game to your library.")
                }
                feature("Keep your library organized",icon:"square.grid.2x2") {
                    Text("Search, save favorites, and find recently played games. Full screen and supported local saves are built in.")
                }
            }
            Divider().padding(.top,28).padding(.bottom,20)
            HStack(spacing:12) {
                Text("No games are included.").font(.system(size:11)).foregroundStyle(.secondary)
                Spacer(minLength:0)
                Button("Add from Website…",action:website).buttonStyle(.bordered).accessibilityIdentifier("welcome-website")
                Button("Open Library",action:start).buttonStyle(.borderedProminent).tint(Palette.action)
                    .keyboardShortcut(.defaultAction).accessibilityIdentifier("welcome-start")
            }.controlSize(.large)
        }.padding(32).frame(width:620).background(Palette.background).tint(Palette.accent)
    }
    private func feature<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment:.top,spacing:16) {
            Image(systemName:icon).font(.system(size:21,weight:.regular)).foregroundStyle(.secondary)
                .frame(width:28,height:24).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:7) {
                Text(title).font(.system(size:14,weight:.semibold)).foregroundStyle(.primary)
                content().font(.system(size:13)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private func format(_ name: String, detail: String) -> some View {
        VStack(alignment:.leading,spacing:3) {
            Text(name).font(.system(size:12,weight:.medium)).foregroundStyle(.primary)
            Text(detail).font(.system(size:11)).foregroundStyle(.secondary)
        }.accessibilityElement(children:.combine)
    }
}

@MainActor final class WelcomeWindow: NSWindowController, NSWindowDelegate {
    static let completedKey = "WelcomeCompleted"
    var onClose: (() -> Void)?

    init(start: @escaping () -> Void, website: @escaping () -> Void) {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:520),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init(window:window)
        window.title = "Welcome to Flashback"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        let view = NSHostingView(rootView:WelcomeView(start:{ [weak self] in self?.close(); start() },
                                                     website:{ [weak self] in self?.close(); website() }))
        window.contentView = view
        window.setContentSize(view.fittingSize)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { onClose?() }
}
