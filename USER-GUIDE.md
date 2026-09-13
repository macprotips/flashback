# Flashback user guide

Flashback is a native macOS library for playing supported Flash, Java, HTML5, DOS, and supported Director games. It keeps a private copy of each import, stores supported local saves per game, and runs imported games offline.

## Start here

When Flashback opens for the first time, the welcome window introduces the library and website importer:

- **Open Library** closes the welcome window and shows your collection.
- **Add from Website…** opens the website recovery workflow.
- You can also reopen the welcome window from **Help → Welcome to Flashback…**.

Flashback also asks where to keep imported games, covers, and Java, DOS, and ScummVM saves. Cancel uses the standard Application Support folder. Open **Flashback → Settings…** to see or change this location later. Flashback copies and verifies the complete library before switching and retains the previous copy. App preferences and Flash/HTML browser storage remain in macOS-managed app data.

The library sidebar contains these controls:

- **Discover** shows weekly recommendations, handpicked games, additional game sources, and the searchable Internet Archive catalog.
- **Installed Games** shows every game in your library.
- **Favorites** shows games marked with the heart button.
- **Recently Played** shows games you have opened.
- **Add Games…** imports files, folders, or ZIP archives from your Mac.
- **Add from Website…** recovers a game from a web page or direct download link.
- **Flashback Help** opens the in-app help window.

## Add a game from your Mac

Click **Add Games…**, choose a file or folder, and select **Add Game** when Flashback asks which game file to use. You can also drag a file, folder, or ZIP anywhere into the library window.

Flashback accepts:

- Flash `.swf` files and standard Windows Flash projector `.exe` files (the embedded SWF is extracted)
- Runnable Java 8 desktop `.jar` files, applet JARs, applet HTML pages with their Java files, and local `.jnlp` descriptors
- Java ME/MIDP mobile `.jar` files, including games with a `MIDlet-1` manifest
- Offline HTML or HTML5 games (`.html` or `.htm`)
- Shockwave `.dcr`, `.dir`, and `.dxr` movies
- DOS `.exe`, `.com`, and `.bat` games with their complete data folders
- Classic Director data folders recognized by the bundled ScummVM player
- ZIP archives containing a game and its supporting files

Add the complete folder or archive when a game uses separate images, sounds, levels, casts, scripts, or stylesheets. Flashback copies the files into its library; your originals are not changed. A single imported game opens automatically when the import finishes.

## Add from Website

Click **Add from Website…** in the sidebar or choose **File → Add from Website…**. Paste a game page or a direct Flash, Java, HTML5, Shockwave, or ZIP link into **Website address**, or use **Paste**, then choose **Find Games**.

1. Select the main game from the results list.
2. If the page loads its game later, click **Look Deeper** to run the page scripts and scan again.
3. Click **Recover Game**. Flashback downloads the game and available supporting files.
4. Review the game name, file count, source, and any unavailable references.
5. Use **Save Report…** if you want a copy of the recovery details.
6. Choose **Back** to select another result, or **Add to Library** to finish.
7. When the import is complete, choose **Play Game** or **Done**.

Use **Cancel** while Flashback is scanning or downloading. Recovery cannot restore files that have been removed from the site, bypass sign-in requirements, or replace services that require an internet connection. Only recover games you have the right to use.

## Discover games

Choose **Discover** to see three **Top games this week**. The selection changes every Monday and stays still while you browse. Choose **Browse all 24 featured games** to expand the rest of the week's selection. Enter a title, select **All**, **Flash**, or **Shockwave**, and click **Search** to search the Internet Archive. Open a result card to read its description, source information, compatibility notes, artwork, and available files.

**Browse more sources** opens the Internet Archive search or external pages at DOS Games Archive, DOSGames.com, itch.io, GOG, and ScummVM. **Handpicked games** provides direct source-page shortcuts. Download a supported game folder or ZIP from its source and add it with **Add Games…**. Flashback does not copy or bundle the games shown by these links, and availability can change at the source.

- **Download to Library** downloads the selected game and its listed supporting files.
- **Cancel** stops an active download.
- **View on Internet Archive** opens the source item in your browser.
- **Try Again** repeats a failed request.
- **Keep Looking** or **Load More** requests another page of results.
- After a game is downloaded, **Show in Library** returns to its library card and **Play** launches it.

Discover filters listings marked as adult or NSFW. A listing may still need unavailable servers or unsupported player features; compatibility notes describe only the interactions that have been checked.

## Manage your library

Click a game card to play it. The heart button adds or removes the game from **Favorites**. The search field filters the current library view; **Clear Search** removes the current search.

Right-click a game card for these actions:

- **Play** launches the game.
- **Quit Game** stops a running Java, DOS, or ScummVM game.
- **Add to Favorites** or **Remove from Favorites** changes its favorite status.
- **Rename…** changes the library name.
- **Change Artwork…** chooses a cover image from your Mac. You can also drag an image onto the card.
- **Restore Default Artwork** removes custom artwork and returns to the default cover or placeholder.
- **Website Details…** reopens the recovery report for a website import.
- **Open Source Page** opens the original source page for a website import.
- **Show Game Files** opens Flashback’s private copy in Finder.
- **Remove from Library…** moves Flashback’s copy to the Trash. Your original files and supported saved data remain on your Mac.

## Play and save

Flash games provide **Pause**, **Restart**, **Mute**, and **Unmute** controls, plus full screen. HTML and Shockwave games provide restart and full screen; use the game’s own controls for pausing and sound. Java, DOS, and ScummVM games open in separate windows and use their own controls. **Restart** can discard unsaved progress, and closing Flashback closes running Java and native games.

The player toolbar’s **Library** button returns to the collection. If a player cannot open a game, **Try Again** starts it again; when a restart needs confirmation, choose **Cancel** or **Restart**.

For a Shockwave game, the clipboard button copies a compatibility report with the exact entry hash, active compatibility profile, runtime state, recent console output, errors, and call stack. If a game opens but cannot be proved playable by the automated checks, reproduce the first broken action, copy this report immediately, and include what you expected to happen, what happened instead, and the last input you used. The report contains diagnostics rather than game files or save data.

Flash local saves and HTML local storage are kept separately for each game. Flashback does not create save states for games that never supported saving. Games that depend on browser cookies, hard-coded external paths, or live services may not preserve progress offline.

Java ME games run in a phone-sized emulated screen. To include JAD display settings, import a folder or ZIP containing both the JAR and its matching JAD with the same base filename. Those settings initialize a new game profile; later changes in the player's **Settings** menu are retained. Support depends on the APIs used by each game. Java ME settings and record-store data are kept in that game’s private save folder.

Flash games have a volume button in the player toolbar. Flashback remembers the selected level separately for each game. For DOS games, open **DOS Settings** and set **Game volume**; the change applies on the next launch. Classic Director games played through ScummVM use **Game Volume…** in the library card’s shortcut menu and apply it on the next launch. Mac synthesizer MIDI from DOS games follows the Mac’s output volume.

The default Java ME controls use the arrow keys, Return for fire/confirm, Q and W for the left and right softkeys, and the numeric keypad for phone buttons. Use **Settings → Manage Inputs** to change bindings, especially on keyboards without a numeric keypad.

## Additional classic formats

**Flash projectors.** Add a standard Flash Player projector `.exe`, or a folder/ZIP containing it and its assets. Flashback extracts the embedded SWF without executing Windows code. Wrapped, encrypted, or nonstandard projectors may not be recognized; a general Windows `.exe` is not a Flash game. Features that depended on the original projector may be unsupported by Ruffle.

**Java applets.** Add the original HTML page together with its JARs or loose class tree. The page supplies the applet class, dimensions, codebase, and parameters. A standalone applet JAR can launch when its applet class is unambiguous; use the HTML page or JNLP descriptor when parameters or companion files matter. Applet initialization, start, stop, and destruction follow the player window's lifecycle. Games cannot open external web pages or contact servers.

**Java Web Start.** Add a `.jnlp` file and its local JARs, or recover it using Add from Website. Basic application and applet descriptors retain their arguments, parameters, classpath, and local codebase. Remote resources must be recovered before play. Native libraries, extension/installer descriptors, and requests for unrestricted permissions are rejected. JavaFX and Java versions newer than 8 are outside this player’s scope.

**DOS.** Add the original game folder or ZIP and select its startup EXE, COM, or BAT file. Internal paths must retain DOS 8.3 filenames; the enclosing Mac folder can have a long name. DOSBox mounts a private writable copy of the game, so its original imported files stay unchanged and ordinary DOS save files survive reopening. Configuration and network access from the host system are not exposed. This player does not run general Windows applications or boot disk images. Use the game's own setup program where supplied; Sound Blaster/OPL sound is available, while external MIDI devices are disabled.

**Classic Director through ScummVM.** Add the complete original game data folder. Flashback offers a ScummVM entry only when that engine detects the title. If a browser Shockwave entry is also present, the entry chooser lets you select the player. Recognition does not establish full-game compatibility: unsupported engine features, missing files, or an unrecognized edition can still prevent play. ScummVM configuration and supported saves are private to that library entry.

The Java and native players run offline with separate game/save access. Choosing Quit Game or quitting Flashback closes their processes; an abrupt Flashback exit also closes the supervised players. Removing a game preserves its supported saves.

## Menus and shortcuts

The same common actions are available from the macOS menus:

- **File:** **Add Games…**, **Add from Website…**, **Show Library**, **Close Window**
- **Edit:** **Find Game…**
- **Window:** **Enter Full Screen**
- **Help:** **Welcome to Flashback…**, **Flashback Help**
- **Flashback:** **About Flashback**, **Settings…**, **Licenses and Source…**, **Quit Flashback**

Shortcuts:

| Action | Shortcut |
| --- | --- |
| Add Games | `⌘O` |
| Add from Website | `⇧⌘O` |
| Find Game | `⌘F` |
| Show Library | `⌘L` |
| Full Screen | `⌃⌘F` |
| Close Window | `⌘W` |
| Settings | `⌘,` |

For licensing, bundled player credits, and source notices, choose **Flashback → Licenses and Source…**.

JNLP support requires portable local resources. Descriptors with platform-specific
resource sections or system-property overrides are rejected with an explanation.

DOS games return to their DOS prompt when they finish. Use the library card’s
Quit Game action to close DOSBox and its supervised session.

The DOS launcher also rejects filenames containing `%` or beginning with `@`,
which DOSBox interprets as command syntax.
