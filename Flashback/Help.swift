// SPDX-License-Identifier: GPL-3.0-only
import Cocoa
import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text("Flashback Help").font(.system(size:24,weight:.semibold)).padding(.bottom,4)
                section("Add games from your Mac") {
                    Text("Choose File → Add Games, or drop a file, folder, or ZIP into the library. Add the entire folder when a game includes graphics, sounds, or levels. If several game files are found, choose the one that starts the game.")
                    Text("Flashback keeps its own copy. A single imported game opens automatically.")
                }
                section("Discover games") {
                    Text("Choose Discover in the sidebar to browse Internet Archive. Search for a game, choose All, Flash, or Shockwave, and open a card for its description and downloads. Download to Library keeps the game and its supporting files on your Mac. When it finishes, choose Play or Show in Library.")
                    Text("Discover hides listings marked as adult or NSFW before showing cards or artwork. The filter uses titles, tags, descriptions, and file names; it can miss content that is not labelled. Keep Looking continues past a page with no visible results.")
                    Text("Archive artwork becomes the game’s default cover. Your custom artwork takes priority. Compatibility notes describe only the gameplay that has been checked; other games may need unavailable servers or unsupported features.")
                }
                section("Import from a website") {
                    Text("Choose File → Add from Website and paste a game page or direct download address. Find Games locates game files; Look Deeper checks content loaded by the page’s scripts. Select a result, recover its files, and review the report before adding it.")
                    Text("Only extract copyright-free games. Removed files, sign-in requirements, and games that depend on live servers may prevent recovery.")
                    Text("Right-click an imported game and choose Website Details to reopen its report.")
                }
                section("Supported games") {
                    definition("Flash", ".swf files. Pause, restart, mute, and full screen are available in the player.")
                    definition("Java", "Runnable Java 8 desktop .jar games. Applet-only pages, JNLP launchers, and mobile Java games are not supported. Games open in their own windows; use their own controls.")
                    definition("HTML5", "Offline .html or .htm games. Add the entire game folder. Use the game’s own pause and sound controls.")
                    definition("Shockwave", ".dcr, .dir, and .dxr movies. Support is experimental; some games and Xtras are not supported. Include external cast files, sounds, and levels.")
                }
                section("Organize your library") {
                    Text("Click a game’s cover to play. Use the heart to mark a favorite. Search by name, or choose Recently Played to return to a game. Right-click a game to rename it, show its files, or remove it from the library.")
                    Text("Removing a game moves Flashback’s copy to the Trash. Your original files and supported saved data are kept.")
                    Text("Drag an image onto a game's card to use it as that game's artwork, or right-click the game and choose Change Artwork to select an image from your Mac. Your choice is kept when you play or reopen Flashback. Restore Default Artwork brings back the original cover, or the placeholder until a screenshot is captured.")
                }
                section("Playing and saving") {
                    Text("Games run on this Mac with network access blocked. Flash local saves and HTML local storage are kept per game. Flashback does not add save states to games that never supported saving. Java games that depend on browser cookies or external files may not save progress.")
                    Text("Restarting can discard unsaved progress. Closing Flashback also closes its Java games.")
                }
                section("Keyboard shortcuts") {
                    shortcut("Add Games", "⌘O")
                    shortcut("Add from Website", "⇧⌘O")
                    shortcut("Show Library", "⌘L")
                    shortcut("Find Game", "⌘F")
                    shortcut("Full Screen", "⌃⌘F")
                    shortcut("Close Window", "⌘W")
                }
                Divider()
                Text("Flashback is free software under GPLv3, without warranty. Choose Flashback → Licenses and Source for the license, player credits, and corresponding source.")
                    .font(.system(size:12)).foregroundStyle(.secondary)
            }.font(.system(size:13)).textSelection(.enabled).lineSpacing(3)
                .padding(28).frame(maxWidth:700,alignment:.leading).frame(maxWidth:.infinity,alignment:.center)
        }.background(Palette.background)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment:.leading,spacing:9) {
            Text(title).font(.system(size:15,weight:.semibold))
            content().foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }
    }
    private func definition(_ title: String, _ detail: String) -> some View {
        Text("\(Text(title + ": ").fontWeight(.medium).foregroundColor(.primary))\(detail)")
    }
    private func shortcut(_ title: String, _ keys: String) -> some View {
        HStack { Text(title); Spacer(); Text(keys).font(.system(size:13,design:.monospaced)).foregroundStyle(.primary) }
    }
}

@MainActor final class HelpWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    init() {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:640,height:660),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "Flashback Help"; window.minSize = NSSize(width:520,height:400); window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:HelpView())
        super.init(window:window); window.delegate = self; window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func windowWillClose(_ notification: Notification) { onClose?() }
}
