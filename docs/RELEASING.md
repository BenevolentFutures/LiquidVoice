# releasing.

a release is a Developer ID signed, notarized and stapled `MouthKeys.app` inside a signed, notarized and stapled DMG, attached to a GitHub release. `scripts/release.sh` does all of it; `./build.sh dist` is the same thing.

there is no auto-update. the upstream updater stays off, and people download each release by hand.

## once.

1. **a Developer ID Application certificate** for the team, in the login keychain of the Mac that signs. check with `security find-identity -v -p codesigning`. it needs the paid Apple Developer Program; a Personal Team cannot make one.
2. **a notarytool profile**, stored in the same keychain. with an app-specific password from account.apple.com › Sign-In and Security:

   ```bash
   xcrun notarytool store-credentials liquidvoice-notary --apple-id <apple-id> --team-id <team-id>
   ```

   or with an App Store Connect API key: `--key AuthKey_XXXX.p8 --key-id <key-id> --issuer <issuer-uuid>` in place of the Apple ID and team. the script uses `liquidvoice-notary` unless `LIQUIDVOICE_NOTARY_PROFILE` names another.

the script checks both before it does anything and says what is missing. any working profile for the same team will do: notary credentials belong to the team, not the app.

notarytool reads the profile from the login keychain, which locks with the screen. notarize with the Mac unlocked, or the profile reads as missing even though it worked a minute ago.

## each release.

1. **version.** set `CFBundleShortVersionString` in `Info.plist` to the new version, and raise `CFBundleVersion` by one (it only ever goes up). merge to `liquid-voice`. MouthKeys versions started at 0.1.0; the `v1.6.x` tags in this repo are FluidVoice's.
2. **build.** `scripts/release.sh build` makes a Release build signed to run locally. it needs Xcode 26 and no certificate, so it can run on a separate build Mac. the product is `DerivedData/Build/Products/Release/MouthKeys.app`. never launch it: it is `com.stage11.liquidvoice`, and would write into the installed app's settings and data.
3. **package.** on the Mac with the certificate, `scripts/release.sh package [path/to/MouthKeys.app]`. it copies the app to `dist/`, normalizes the CTranscribe framework layout, re-signs every nested framework and binary and then the app with Developer ID, the hardened runtime, a secure timestamp and the entitlements Xcode built it with, notarizes and staples the app, builds the DMG (the app beside an Applications link), signs, notarizes and staples the DMG, then verifies. the result is `dist/MouthKeys-<version>.dmg`.
4. **check.** the last step runs `codesign --verify --deep --strict`, `spctl -a -vvv` on the app, `spctl -a -vvv -t install` on the DMG and `xcrun stapler validate` on both, and confirms the microphone entitlement. `scripts/release.sh verify dist/MouthKeys.app dist/MouthKeys-<version>.dmg` runs it again.
5. **draft.** `gh release create v<version> --draft --repo BenevolentFutures/MouthKeys --target liquid-voice dist/MouthKeys-<version>.dmg --notes-file <notes>`.
6. **smoke test.** install from the DMG on a real Mac, launch it, and run [INSTALL-CHECKLIST.md](INSTALL-CHECKLIST.md): microphone, Accessibility, and a real paste. green checks are not a working app. before the first launch of a build with a new signature, delete every other copy of `com.stage11.liquidvoice` signed by someone else (`mdfind "kMDItemCFBundleIdentifier == 'com.stage11.liquidvoice'"`, then the Trash, `~/Library/Caches/com.apple.SwiftUI.Drag-*` and DerivedData Release builds) and empty the Trash. System Settings can record such a copy's code requirement when Accessibility is switched on, and the switch then shows on but never matches the running app.
7. **publish** the draft. the README's download link points at the latest release.

`LIQUIDVOICE_SKIP_NOTARIZE=1 scripts/release.sh package` signs and packages without notarizing, to check signing alone. that DMG will not open on another Mac without a Gatekeeper override, so never upload it.
