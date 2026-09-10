# Downloaded internet games

**173 game entries, about 1.99 GB**. The latest addition is a [105-game Shockwave compatibility corpus](Shockwave%20Games/Shockwave%20Compatibility%20Corpus/README.md), bringing Shockwave coverage to 108 titles. It includes complete preserved packages, asset inventories, source hashes, and existing test probes. Earlier downloads and their import instructions remain below. Most files came from Internet Archive or its Wayback Machine; other sources are recorded in the manifest.

[Browse every game](CATALOG.md) · [Read the research and starter picks](RESEARCH.md) · [Exact sources and checksums](sources.json)

| Format | Recent curated/download additions | Total | How to use it |
| --- | ---: | ---: | --- |
| Flash | 49 | 58 | Import the `.swf` into Flashback |
| Java desktop | 4 | 4 | Import the runnable JAR or complete package, as below |
| Java applet | 2 | 2 | Preserved for a legacy applet runtime; unsupported by Flashback |
| Shockwave | 108 | 108 | Import the movie with its support files; experimental compatibility |
| Windows | 0 | 1 | Icy Tower 1.0 needs Windows or a compatible Windows runtime |

## New Shockwave corpus

Start with the [corpus index](Shockwave%20Games/Shockwave%20Compatibility%20Corpus/INDEX.md). Import whole game folders to keep casts, models, and HTML launch settings together. All 105 new entries are marked **NOT_TESTED**; file integrity checks do not establish gameplay compatibility. The emulator was not changed by this download task.

## Start here

Try **Bloons Tower Defense, Motherload, Line Rider, The Impossible Quiz, Portal: The Flash Version, Alien Hominid, Learn to Fly, Papa's Pizzeria, Bloxorz,** and **Fireboy and Watergirl: The Forest Temple**. Your previously downloaded **Fancy Pants Worlds 1–3** and **Age of War** are also in the catalog.

## Importing into Flashback

Use **Add Games / ⌘O**, or drag a game into Flashback. The current app supports SWF files, runnable desktop JARs, folders, ZIPs, and experimental Shockwave movies. These are import instructions; gameplay has not been tested.

- **Flash:** Import each game's `.swf`. Most downloads are unchanged archived SWFs. For **N 1.4**, the SWF was extracted verbatim from its original Windows Flash projector; its original ZIP, license, and documentation are also preserved.
- **Need for Madness:** Import `Java Classics/Need for Madness/Need for Madness - Original.zip`, or the complete `Game/Need for Madness` folder inside it, then select **Game.jar**. Keep its data, music, and stages together. Importing only Game.jar omits game assets.
- **World of Sand:** Import `Java Classics/World of Sand/World of Sand.jar`. This is Androdome's desktop preservation adaptation of the original applet.
- **Jet Slalom:** Import `Java Classics/Jet Slalom - Original/Jet Slalom - Desktop.jar`. The untouched original JAR is also preserved; the desktop copy only adds a manifest pointing to its existing launch method. See the included notes for the original desktop mode’s sound limitation.
- **Minicraft:** Import `Java Classics/Minicraft/Minicraft - Desktop.jar`. This copy adds a manifest entry pointing to the desktop launch method already present in the original game. Every class and resource is unchanged. The original JAR is included separately.
- **Powder Game 7.7.2 and Minecraft 4k:** These are applet-only JARs in `Java Applets`. Flashback cannot launch them. They need a legacy applet environment, which has not been installed. Minecraft 4k is a small competition experiment, distinct from full Minecraft.
- **Snowcraft:** Import `Shockwave Games/Shockwave Classics/Snowcraft/Snowcraft.dcr`.
- **LEGO Supersonic RC:** Import its **Game folder**, selecting `game.dcr`. Keep `GUILibrary.cct` alongside it. Its Shockwave 3D behavior is untested.
- **LEGO Junkbot:** Import its **Game folder**, selecting `junkbot2_13g_asp.dcr`. The preserved package includes server-based save helpers; a standalone movie import does not reproduce that server behavior. Save progression is unverified.
- **Icy Tower:** Unzip the original Windows package and keep its `icytower1.0` folder intact. Run `icytower.exe` in Windows or a compatible Windows runtime. Flashback does not run Windows executables. Controls: arrows to move, Space to jump, Esc to pause.

The selected **Tanks** is 2DPlay's turn-based artillery game. **Bubble Trouble 2** is the creator's **Bubble Struggle 2: Rebubbled** hosting build. Those titles were resolved from your earlier request.

## What was verified

All 58 SWFs passed signature and full uncompressed-length checks. Internet Archive downloads were compared with published byte counts and MD5 hashes; Wayback downloads were compared with indexed SHA-1 digests. ZIP and JAR contents passed CRC checks, and the three earlier Shockwave movies passed format-signature checks; verification of the additional corpus is documented in its guide. Original packages were retained when extracting or preparing a convenience copy.

`SHA256SUMS.txt` covers 1207 tracked game, archive, support, and package-note files. It does not include unrelated files you may have extracted separately. `sources.json` records each exact download URL, file size, hashes, and any transformation.

**These checks establish file integrity, not playability.** Gameplay, saves, and old online services have not been tested. Shockwave support is experimental, and the two legacy applets are preserved downloads rather than Flashback-ready games.
