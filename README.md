# Flashback

Flashback is a native macOS library for playing classic Flash, Shockwave,
Java, and offline HTML games.

It runs on macOS 13 and later, with native Apple Silicon and Intel support.
The app bundles the required players, so no browser plug-in, separate Java
installation, or package manager is needed.

## Status

Flashback is beta software. Compatibility varies by game and runtime; the
documented checks cover specific opening interactions rather than complete
games.

Claude was used as a development aid for parts of the implementation and
documentation. The project author reviewed and maintains the resulting work.

## User guide

See the [Flashback user guide](USER-GUIDE.md) for importing games, using
**Add from Website…**, browsing **Discover**, managing library cards, and
using every app button and keyboard shortcut.

## Features

- Import SWF, JAR, HTML, Shockwave movies, folders, and ZIP archives.
- Recover games and launch settings from archived web pages.
- Keep each game's files, artwork, and local storage isolated.
- Browse a curated catalog of archived Flash and Shockwave games.
- Run imported games offline, with remote game requests blocked.
- Use native pause, restart, mute, full-screen, and library controls.

Shockwave support is a work in progress. The compatibility report records the
tested titles and the boundaries of the current runtime.

## License

Flashback's original source, documentation, and artwork are licensed under
the [GNU General Public License v3.0](LICENSE). Third-party runtimes and
game files retain their own licenses and copyrights; see
[Flashback/Licenses](Flashback/Licenses) for the bundled notices.

The repository also retains the original TextTwist 2 Mac bundle as a separate
legacy project. It is independent of Flashback's build and release.
