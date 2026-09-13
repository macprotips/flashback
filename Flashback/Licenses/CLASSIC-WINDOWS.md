# Experimental Classic Windows component

Classic Windows is excluded from ordinary builds and every distributable
archive. A developer can opt in with `FLASHBACK_EXPERIMENTAL_CLASSIC_WINDOWS=1`.
That opt-in copies the separately fetched DOSBox-X runtime into the development
app; it does not fetch, include, or configure Microsoft Windows, a product key,
or any game media.

`fetch-classic-windows.py` pins the two DOSBox-X 2026.08.31 upstream macOS
archives by URL and SHA-256, checks their architecture layout, and records the
same information in `vendor/classic-windows/provenance.json`. It preserves the
upstream `COPYING.txt`, `README.txt`, and `CHANGELOG.txt` in that local runtime.
DOSBox-X is GPL-2.0-or-later; the source tag is
`dosbox-x-v2026.08.31` at https://github.com/joncampbell123/dosbox-x .

This repository currently does not claim a release-ready corresponding-source
closure for DOSBox-X and all bundled dependencies, guest shutdown completion,
or two-architecture guest validation. `package-release.py` rejects an app that
contains `Resources/ClassicWindows`.
