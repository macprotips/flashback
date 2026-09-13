// SPDX-License-Identifier: GPL-3.0-only
import Cocoa

@MainActor final class StorageSettingsWindow: NSWindowController {
    private let pathLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let changeButton = NSButton(title:"Change Location…", target:nil, action:nil)
    var change: (() -> Void)?
    var quit: (() -> Void)?
    init(path: URL) {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:560,height:190), styleMask:[.titled,.closable], backing:.buffered, defer:false)
        window.title = "Flashback Settings"; window.isReleasedWhenClosed = false
        super.init(window:window)
        pathLabel.stringValue = path.path; pathLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.stringValue = "Imported games, covers, and Java, DOS, and ScummVM saves are stored here. App preferences and Flash/HTML browser storage stay in macOS-managed app data."
        statusLabel.textColor = .secondaryLabelColor
        changeButton.target = self; changeButton.action = #selector(changeLocation)
        let stack = NSStackView(views:[NSTextField(labelWithString:"Storage Location"), pathLabel, statusLabel, changeButton])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView(); window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:24)])
        window.center()
    }
    required init?(coder:NSCoder) { fatalError() }
    @objc private func changeLocation() { change?() }
    func progress(_ text: String) { statusLabel.stringValue = text; changeButton.isEnabled = false }
    func readyToQuit() {
        statusLabel.stringValue = "Storage verified. Quit and reopen Flashback to use the new location."
        changeButton.title = "Quit Flashback"; changeButton.isEnabled = true; changeButton.action = #selector(quitFlashback)
    }
    @objc private func quitFlashback() { quit?() }
}
