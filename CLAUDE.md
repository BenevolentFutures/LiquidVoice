# MouthKeys

macOS dictation app, forked from FluidVoice (see `UPSTREAM.md`). The product is **straight voice to text**. Fluid Intelligence is removed, telemetry is hard-off (`AnalyticsConfig.isConfigured` is false), and the upstream updater is off (`AppDelegate.upstreamUpdatesDisabled`). Keep all three that way.

Atin dictates into Claude Code in c11 all day with the installed app. Text delivery into c11 and Ghostty (forced Reliable Paste) must never regress.

## Identity

| | Installed (Release) | Debug build and test host |
|---|---|---|
| Bundle ID | `com.stage11.liquidvoice` | `com.stage11.liquidvoice.dev` |
| Application Support | `~/Library/Application Support/LiquidVoice` | `.../LiquidVoice-Dev` |
| Log | `~/Library/Logs/LiquidVoice/Fluid.log` | `~/Library/Logs/LiquidVoice-Dev/Fluid.log` |

- The product was renamed from Liquid Voice to MouthKeys on 2026-10-02. Only what users see or type changed (app name `MouthKeys.app`, Debug `MouthKeys Debug.app`, UI strings, repo URL). The internal identifiers keep the old name on purpose, so no data, permission or login item moves: bundle IDs, Application Support and log folders, UserDefaults keys and markers, `com.stage11.liquidvoice.debug.*` notifications, queue labels, `LIQUIDVOICE_*` environment variables, type names such as `LiquidVoiceLinks`/`LiquidVoiceMain`, `~/Backups/liquid-voice-*`, and the `liquid-voice` branch.

- Until the identity change the app ran as FluidVoice: `com.FluidApp.app`, `Application Support/FluidVoice`, `~/Library/Logs/Fluid/`. On its first launch the installed app copies that data once (`AppIdentityMigration`, run from `LiquidVoiceMain` before anything reads a default): every UserDefaults key, then the folder, then the login item. It never writes to the old domain or folder, so the old app still runs from a backup. Check it with `grep IDENTITY_MIGRATION ~/Library/Logs/LiquidVoice/Fluid.log`; the markers are `LiquidVoiceIdentityMigrationDefaults` and `LiquidVoiceIdentityMigrationFolder` in the new domain. The old data wins on conflict; what it replaces is saved to `~/Backups/liquid-voice-displaced-*` first. A retry that had to set data aside and still failed stops retrying (`LiquidVoiceIdentityMigrationDefaultsHalted`) and shows an alert before the app opens. Debug builds never migrate.
- Identifiers live in `AppStorageLocation` (and `LegacyAppIdentity` for the old ones). Never hardcode one. The keychain service `com.fluidvoice.provider-api-keys` kept its name on purpose (`KeychainService.serviceName`).
- Model caches in `~/Library/Application Support/FluidAudio` belong to the FluidAudio library, not to a bundle ID, and are shared by every build.
- Install with Atin only, and pick the path by the installed app's signer (`codesign -dvv /Applications/MouthKeys.app 2>&1 | grep -m1 Authority=`). **Developer ID** (Atin's Mac since the 0.1.0 DMG): never `./build.sh install`; follow "Install over a Developer ID app" in `docs/INSTALL-CHECKLIST.md` (pitfall below). **Apple Development**: `./build.sh install` checks for data already under a new identity (first install only), quits the app (and stops if it will not quit), backs it up to `~/Backups/liquid-voice-<timestamp>/` and verifies the copy (an older `/Applications/Liquid Voice.app` is backed up the same way and taken out in the same swap, since two copies of one bundle ID confuse LaunchServices), prints the rollback command (`bash ~/Backups/liquid-voice-<timestamp>/rollback.sh`), then copies the new app alongside and swaps it in. Then run `docs/INSTALL-CHECKLIST.md`.
- Never launch a Release product (`./build.sh release`, `DerivedData/.../Release/MouthKeys.app`): it is `com.stage11.liquidvoice`, the installed app's identity, and would write into the installed app's defaults and folder. The migration only runs for the app in `/Applications`.

## Never touch the installed app

- Never touch `/Applications/MouthKeys.app` or `/Applications/Liquid Voice.app` (its name before the rename), quit or relaunch the running app, write `defaults` for `com.stage11.liquidvoice` or `com.FluidApp.app`, or touch `~/Library/Application Support/LiquidVoice` or `.../FluidVoice`. Never run `./build.sh install` without Atin.
- Debug builds are isolated by their own bundle ID (own UserDefaults) and folders (table above). Any code that picks an Application Support folder must use `AppStorageLocation.folderName`, and the log folder `AppStorageLocation.logFolderName`.
- Read either log freely.

## Build

```sh
xcodebuild -project Fluid.xcodeproj -scheme Fluid -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath DerivedData DEVELOPMENT_TEAM="$LIQUIDVOICE_DEVELOPMENT_TEAM" SDK_STAT_CACHE_ENABLE=NO build
```

- `LIQUIDVOICE_DEVELOPMENT_TEAM` is your own 10-character Apple team ID (the maintainer uses his own; contributors pass theirs). `./build.sh` reads the same variable.
- Always pass `SDK_STAT_CACHE_ENABLE=NO`. On this machine `clang-stat-cache` hangs at 0% CPU on its second run in a DerivedData folder, and the build sits at "ClangStatCache" with no error. If you see that, kill `clang-stat-cache` and re-run with the flag.
- Product: `DerivedData/Build/Products/Debug/MouthKeys Debug.app`. The test module is `MouthKeys_Debug` (`@testable import MouthKeys_Debug`).
- The warning about `CTranscribe.framework/Versions/Current` symlinks is harmless for Debug builds.

## Test

- Same command with `test`. Iterate with `-only-testing:FluidDictationIntegrationTests/<Suite>`, then run the full suite before a PR.
- The test host is `MouthKeys Debug.app`, which launches briefly. Never click through or dismiss a system permission prompt; report it.
- **App-hosted tests must stay invisible and silent on the operator's machine.** Atin works (and dictates with the installed app) while tests run. As the XCTest host the app runs in `TestHostQuietMode`: it never activates, puts no window on screen, has no menu bar item, installs no global monitor or event tap, posts no notification, asks for no permission, and creates no sound player. `TestHostQuietModeTests` guards this. Never add a test or benchmark that shows UI, plays audio, takes focus, types, or touches the clipboard, and batch repeated runs inside one test-host launch.
- Never wait on a real `NSAnimationContext` completion in a test. Window animations evidently tick on the display (a run ended the moment the displays woke), so while the displays sleep the completion never comes and the suite hangs (`SignalFloatShadowTests`, 2026-10-01). Step the animated value by hand, and in an async test spell out `completionHandler: nil`: the bare `runAnimationGroup { }` there is the async overload, which awaits completion. Every wait gets a timeout of a few seconds (`fulfillment(of:timeout:)`, or a polled deadline).
- `DirectAudioReliabilityTests.testReadinessGateRearmingCancelsExistingWaiter` was flaky (a test race) until `4474074e`. If it fails again, re-run it alone before calling it a regression.
- App sources are a synchronized folder; test files are listed in `project.pbxproj` by hand. A new test file needs a project entry, so prefer adding to an existing test file.
- swiftlint and swiftformat are not installed. Follow `.swiftlint.yml`, `.swiftformat` and the surrounding code.

## Validate

Green tests are not a working product. Mic capture, Accessibility and real paste into c11 need a check in the running app. When you cannot drive it yourself, hand Atin concrete steps. After every install, Atin runs `docs/INSTALL-CHECKLIST.md`; add a line there when a change needs a real-path check.

Scripted delivery checks (Debug builds only): `defaults write com.stage11.liquidvoice.dev LiquidVoiceDebugDeliveryTriggers -bool YES`, then post a `com.stage11.liquidvoice.debug.*` distributed notification (see `DeliveryDebugTriggers.swift`).

## Git and PRs

- `gh repo set-default` is `BenevolentFutures/MouthKeys` (renamed from `BenevolentFutures/LiquidVoice`; GitHub redirects the old URL). The integration branch is `main` (renamed from `liquid-voice` on 2026-10-02).
- Always `gh pr create --repo BenevolentFutures/MouthKeys --base main`. Never open anything against `altic-dev/FluidVoice`.
- Upstream fixes are ported by hand, never merged. Policy, watermark and ledger: `UPSTREAM.md`.

## Agent pitfalls

### `./build.sh install` over the Developer ID app silently kills the hotkeys

**The incident (2026-10-02):** with the Developer ID 0.1.0 build installed, an agent ran `./build.sh install`. It signs with the Apple Development identity: same bundle ID, a different designated requirement. Accessibility still showed switched on, `AXIsProcessTrusted()` was false, and the hotkey retried `Attempt 1 failed` until the install was rolled back.

**The rule:** match the installed app's signer. Over a Developer ID app, sign the Release build with Developer ID (`scripts/release.sh package`, notarizing optional for a local install), confirm `codesign -d -r-` matches the installed app's line exactly, then swap it in by hand: "Install over a Developer ID app" in `docs/INSTALL-CHECKLIST.md`. After the swap, `grep HOTKEY_TAP ~/Library/Logs/LiquidVoice/Fluid.log | tail -1` must say `state=installed`; `waiting_for_accessibility` means the signature does not match, so roll back.

### A new signature leaves a stale Accessibility grant, and other copies of the bundle ID poison it

**The incident (2026-10-02):** Atin replaced an Apple Development-signed build with the Developer ID-signed 0.1.0 DMG (same bundle ID, new signature). MouthKeys showed as switched on in Privacy & Security > Accessibility, yet `AXIsProcessTrusted()` stayed false: onboarding kept saying Open Settings and the hotkeys were silently dead (the old retry logged `Attempt 1 failed` every 0.5 s, forever). Removing the row with − and switching it on again did not help. tccd logged `Failed to match existing code requirement for subject com.stage11.liquidvoice and service kTCCServiceAccessibility`: other copies with the same bundle ID and a different signer were registered with LaunchServices (`~/.Trash/Liquid Voice.app`, a `~/Library/Caches/com.apple.SwiftUI.Drag-*/` copy, an old DerivedData Release build), and System Settings recorded one of their code requirements when the switch was flipped.

**What the app does now:** `AccessibilityTrustMonitor` re-reads trust every 0.5 s while a permission surface is visible and on every activation; the hotkey tap arms itself the moment trust flips (`HOTKEY_TAP state=waiting_for_accessibility`, then `state=installed`, transitions logged once). Still untrusted 3 s after the user returns from System Settings, the step shows "Already switched on?", and `ConflictingAppCopyDetector` names any registered copy whose designated requirement the running app does not satisfy (`PERMISSION_DIAG conflicting_copies=N paths=...`) with Show in Finder. Trusted but the tap refused after five tries: `state=failed_trusted` and a Relaunch MouthKeys button. It never deletes anything.

**The rules:**
1. Before the first launch of a build with a new signature, delete other copies of `com.stage11.liquidvoice` signed by someone else and empty the Trash. `./build.sh install` lists them after installing (read-only).
2. Diagnose from the log first: `grep -E 'HOTKEY_TAP|ACCESSIBILITY|PERMISSION_DIAG|PERMISSION_HINT' ~/Library/Logs/LiquidVoice/Fluid.log`, and tccd's view with `log show --last 10m --predicate 'process == "tccd"' | grep liquidvoice`.
3. Agents never touch TCC (`tccutil`) or delete Atin's copies. Hand him the paths and the steps.
