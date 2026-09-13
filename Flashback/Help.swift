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
                    Text("Choose Discover in the sidebar to see three top games for the week. Browse all 24 featured games, explore more sources, or use the handpicked game links. The selection changes every Monday and stays still while you browse. Source links open the provider’s page; download a supported DOS folder or ZIP there, then use Add Games. Archive cards provide descriptions and downloads inside Flashback.")
                    Text("Discover hides listings marked as adult or NSFW before showing cards or artwork. The filter uses titles, tags, descriptions, and file names; it can miss content that is not labelled. Keep Looking continues past a page with no visible results.")
                    Text("Flashback does not bundle games from Discover. Availability, download terms, and store requirements can change. A Tested label and other compatibility notes describe only the gameplay that Flashback has checked.")
                    Text("Archive artwork becomes the game’s default cover. Your custom artwork takes priority. Other games may need unavailable servers or unsupported features.")
                }
                section("Import from a website") {
                    Text("Choose File → Add from Website and paste a game page or direct download address. Find Games locates game files; Look Deeper checks content loaded by the page’s scripts. Select a result, recover its files, and review the report before adding it.")
                    Text("Removed files, sign-in requirements, and games that depend on live servers may prevent recovery.")
                    Text("Right-click an imported game and choose Website Details to reopen its report.")
                }
                section("Supported games") {
                    definition("Flash", ".swf files and standard Flash projector .exe files. Pause, restart, per-game volume, and full screen are available in the player.")
                    definition("Java", "Java 8 desktop games, applets with their HTML/JAR files, local JNLP descriptors, and Java ME/MIDP mobile games. Include companion JARs and assets. Native libraries and unrestricted permissions are not supported. Games open in their own windows.")
                    definition("DOS", "Original DOS EXE, COM, or BAT games with their complete data folders and DOS filenames. A private writable game copy retains saves.")
                    definition("Classic Director", "Complete game data folders recognized by ScummVM. Only detected titles are offered; compatibility varies by game and edition.")
                    definition("HTML5", "Offline .html or .htm games. Add the entire game folder. Use the game’s own pause and sound controls.")
                    definition("Shockwave", ".dcr, .dir, and .dxr movies. Support is experimental; some games and Xtras are not supported. Include external cast files, sounds, and levels.")
                }
                section("DOS settings and recovery") {
                    Text("Right-click a DOS game and choose DOS Settings. Choose its starting program, run a setup utility, adjust speed and per-game volume, or attach a CD or floppy image. Close the game before changing settings.")
                    Text("The Controls & Help tab lists DOS shortcuts, including Option–Return for full screen and Command–F10 to release the mouse. These apply to the DOS game window; other players have different controls.")
                    Text("Saves & Recovery opens the actual writable game files and lets you back them up, restore a backup, or reset to the original game data. Reset and restore keep a backup of the previous data. Use each game's own Save and Load commands; DOS save states are not provided.")
                }
                section("Organize your library") {
                    Text("Click a game’s cover to play. Use the heart to mark a favorite. Search by name, or choose Recently Played to return to a game. Right-click a game to rename it, show its files, or remove it from the library.")
                    Text("Choose Flashback → Settings to see or change where imported games, covers, and Java, DOS, and ScummVM saves are stored. Flashback verifies a copied library and keeps the previous copy. App preferences and Flash/HTML browser storage remain in macOS-managed app data.")
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
                    shortcut("Settings", "⌘,")
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
