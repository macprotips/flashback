# Flashback user guide

Flashback is a native macOS library for playing supported Flash, Java, HTML5, and Shockwave games. It keeps a private copy of each import, stores supported local saves per game, and runs imported games offline.

## Start here

When Flashback opens for the first time, the welcome window explains the three ways to begin:

- **Open Library** closes the welcome window and shows your collection.
- **Add from Website…** opens the website recovery workflow.
- You can also reopen the welcome window from **Help → Welcome to Flashback…**.

The library sidebar contains these controls:

- **Discover** browses the searchable Internet Archive catalog.
- **Installed Games** shows every game in your library.
- **Favorites** shows games marked with the heart button.
- **Recently Played** shows games you have opened.
- **Add Games…** imports files, folders, or ZIP archives from your Mac.
- **Add from Website…** recovers a game from a web page or direct download link.
- **Flashback Help** opens the in-app help window.

## Add a game from your Mac

Click **Add Games…**, choose a file or folder, and select **Add Game** when Flashback asks which game file to use. You can also drag a file, folder, or ZIP anywhere into the library window.

Flashback accepts:

- Flash `.swf` files
- Runnable Java 8 desktop `.jar` files
- Java ME/MIDP mobile `.jar` files, including games with a `MIDlet-1` manifest
- Offline HTML or HTML5 games (`.html` or `.htm`)
- Shockwave `.dcr`, `.dir`, and `.dxr` movies
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

Choose **Discover**, enter a title, select a format from the **Format** menu, and click **Search**. Open a result card to read its description, rights information, compatibility notes, artwork, and available files.

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
- **Quit Game** stops a running Java game.
- **Add to Favorites** or **Remove from Favorites** changes its favorite status.
- **Rename…** changes the library name.
- **Change Artwork…** chooses a cover image from your Mac. You can also drag an image onto the card.
- **Restore Default Artwork** removes custom artwork and returns to the default cover or placeholder.
- **Website Details…** reopens the recovery report for a website import.
- **Open Source Page** opens the original source page for a website import.
- **Show Game Files** opens Flashback’s private copy in Finder.
- **Remove from Library…** moves Flashback’s copy to the Trash. Your original files and supported saved data remain on your Mac.

## Play and save

Flash games provide **Pause**, **Restart**, **Mute**, and **Unmute** controls, plus full screen. HTML and Shockwave games provide restart and full screen; use the game’s own controls for pausing and sound. Java desktop and Java ME games open in separate windows and use their own controls. **Restart** can discard unsaved progress, and closing Flashback closes running Java games.

The player toolbar’s **Library** button returns to the collection. If a player cannot open a game, **Try Again** starts it again; when a restart needs confirmation, choose **Cancel** or **Restart**.

Flash local saves and HTML local storage are kept separately for each game. Flashback does not create save states for games that never supported saving. Games that depend on browser cookies, hard-coded external paths, or live services may not preserve progress offline.

Java ME games run in a phone-sized emulated screen. The bundled player maps the number keys and arrow keys to the phone keypad; its support depends on the APIs used by each game. Java ME settings and record-store data are kept in that game’s private save folder.

## Menus and shortcuts

The same common actions are available from the macOS menus:

- **File:** **Add Games…**, **Add from Website…**, **Show Library**, **Close Window**
- **Edit:** **Find Game…**
- **Window:** **Enter Full Screen**
- **Help:** **Welcome to Flashback…**, **Flashback Help**
- **Flashback:** **About Flashback**, **Licenses and Source…**, **Quit Flashback**

Shortcuts:

| Action | Shortcut |
| --- | --- |
| Add Games | `⌘O` |
| Add from Website | `⇧⌘O` |
| Find Game | `⌘F` |
| Show Library | `⌘L` |
| Full Screen | `⌃⌘F` |
| Close Window | `⌘W` |

For licensing, bundled player credits, and source notices, choose **Flashback → Licenses and Source…**.
