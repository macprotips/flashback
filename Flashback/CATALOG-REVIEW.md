# Discover catalog — Flashback 1.7.0

Discover adds Internet Archive search, featured entries, Flash/Shockwave filters,
thumbnail cards, native game details, file selection, and download-to-library.
Game downloads retain source provenance and supporting files; Archive artwork is
stored as a default cover, beneath a user's custom artwork. Existing local and
website imports share the final validated library-copy path.

## Checks

The authored Archive service fixture verifies search parsing, pagination, quoted
queries, companion assets, ZIP extraction, persistent imports, duplicate identity,
checksum failures, cancellation, and rejection of private/unsafe file metadata.
The existing library/artwork, website recovery, and ZIP security checks also pass.
The native website-import regression check passes through discovery, recovery,
persistent import, offline HTML input, and its light/dark error and review states.

The native catalog check presses actual sidebar, card, download, cancel, and Play
buttons in an isolated library. It verifies a loose HTML game's script and level
file load offline and respond to input; a ZIP imports; another file with the same
basename is not mistaken for an installed game; repeated imports preserve custom
artwork and game identity; canceled downloads leave no game; pagination and failed
searches remain usable. Light/dark and compact window captures were inspected for
search results, details, downloading, unsupported items, empty/error states, and
the resulting library.

A live run searched for Alien Hominid, retrieved its metadata and thumbnail,
verified and imported its listed SWF, and opened its Flash player offline. This is
a launch check, not a gameplay-completion claim. The compatibility descriptions
for three featured Shockwave ZIPs refer to the specific SHA-1 hashes and opening
checks recorded in `SHOCKWAVE-COMPATIBILITY.md`.

Run `check-archive.sh` for the service tests. Run `archive-fixture.py ADDRESS_FILE`,
then launch the app with `--catalog-check BASE_URL OUTPUT_DIRECTORY` for the native
check. A public `https://archive.org` base instead exercises the live catalog.
The audit writes screenshots and `Result.txt` beneath the chosen output directory
and never uses the normal library. Fixtures contain authored HTML/JS and images.

## Boundaries

The catalog uses Internet Archive's public endpoints and needs a network connection.
Restricted or removed items cannot be downloaded. Loose game downloads preserve
supported companion files listed in the same Archive folder/subfolders; they do
not crawl other sites. Some games depend on unavailable services or unsupported
player features. ZIPs use the existing validated archive importer. No catalog
content is bundled in the release.


## 1.7.3 adult-content filter

Discover excludes common explicit terms from Archive queries and checks returned
titles, creators, descriptions, tags, classifications, and file names before
showing cards or loading artwork. Full metadata is checked with four concurrent
workers and reuses the bounded metadata cache. Detail and download calls enforce
the same filter. Unavailable metadata is kept out of the grid.

Pagination uses the Archive result offset, independently of how many cards are
hidden. An empty filtered page offers Keep Looking; result counts show only
visible cards. The filter has no off switch. It is based on metadata, cannot
classify unlabelled images, and does not filter locally imported or installed
games. It avoids partial-word matches and does not treat users' bookmark
collection names as content ratings.

The authored checks cover adult flags, Unicode normalization, explicit tags,
description-only and file-name-only matches, ordinary-title false positives,
blocked detail/artwork/download calls, and empty-page continuation. The native
check searches the mixed fixture and clicks Keep Looking on an entirely hidden
page. These checks are synthetic; they do not establish a comprehensive content
classification rate for the public catalog.
