# Releasing Flashback 1.11.0

The distributable is `Flashback-Mac.zip`. It contains `Flashback.app`, the
matching `Flashback-Source-1.11.0.tar.gz`, and the license/source instructions.
Share the ZIP as a whole. Do not use the separate TextTwist 2 app or the
development workspace as a release artifact; they contain game fixtures.

The license inventory and source work are recorded in `DISTRIBUTION-AUDIT.md`.
Source verification and packaging are performed by `package-release.py`.
After obtaining the dependency source cache with `fetch-sources.py`,
`fetch-js-sources.py`, `fetch-native-sources.py`, and
`fetch-archive-dependencies.py`, regenerate notices with `collect-notices.py`
before building. These source-management scripts require Python 3.12 or later.

## Signing

`build.sh` creates an ad-hoc signed local build. To sign a release, use an
available **Developer ID Application** identity from:

```sh
security find-identity -v -p codesigning
sh Flashback/sign-release.sh 'YOUR DEVELOPER ID APPLICATION IDENTITY'
```

The script signs Flashback's helper and the modified DOSBox bundle from the
inside out before signing the outer app. DOSBox retains its required JIT
entitlement. The unmodified ScummVM and BellSoft Java executables retain their
upstream Developer ID signatures. Flashback uses system frameworks and needs
no extra app entitlements for its WebKit processes or separately signed Java
processes.

## Apple notarization

The prepared app is Developer ID signed. **It is not notarized unless
`xcrun stapler validate Flashback.app` succeeds.** A Developer ID certificate
alone is insufficient; Apple also requires account authentication for the
notarization service. This workspace has no saved notarytool profile.

If you already have a profile in another keychain, use its name and keychain
with `notarytool`. Otherwise, run `xcrun notarytool store-credentials PROFILE`
interactively and follow Apple's prompts. Enter credentials directly in that
tool, not in source files, scripts, or chat. Use your own developer team.

Submit only the app, then staple and create the source-inclusive release:

```sh
ditto -c -k --keepParent Flashback.app Flashback/build/Flashback-notarization.zip
xcrun notarytool submit Flashback/build/Flashback-notarization.zip --keychain-profile PROFILE --wait
xcrun stapler staple Flashback.app
xcrun stapler validate Flashback.app
python3 Flashback/package-release.py
```

If Apple rejects the submission, inspect its report and correct the actual
issue before packaging. Do not describe a signed-but-unnotarized app as
notarized. Notarization is a Mac delivery check, separate from software
licensing and game redistribution rights.
