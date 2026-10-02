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
- Install with Atin only: `./build.sh install` checks for data already under a new identity (first install only), quits the app (and stops if it will not quit), backs it up to `~/Backups/liquid-voice-<timestamp>/` and verifies the copy (an older `/Applications/Liquid Voice.app` is backed up the same way and taken out in the same swap, since two copies of one bundle ID confuse LaunchServices), prints the rollback command (`bash ~/Backups/liquid-voice-<timestamp>/rollback.sh`), then copies the new app alongside and swaps it in. Then run `docs/INSTALL-CHECKLIST.md`.
- Never launch a Release product (`./build.sh release`, `DerivedData/.../Release/MouthKeys.app`): it is `com.stage11.liquidvoice`, the installed app's identity, and would write into the installed app's defaults and folder. The migration only runs for the app in `/Applications`.

## Never touch the installed app

- Never touch `/Applications/MouthKeys.app` or `/Applications/Liquid Voice.app` (its name before the rename, still installed until the next `./build.sh install`), quit or relaunch the running app, write `defaults` for `com.stage11.liquidvoice` or `com.FluidApp.app`, or touch `~/Library/Application Support/LiquidVoice` or `.../FluidVoice`. Never run `./build.sh install` without Atin.
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

- `gh repo set-default` is `BenevolentFutures/MouthKeys` (renamed from `BenevolentFutures/LiquidVoice`; GitHub redirects the old URL). The integration branch is `liquid-voice`.
- Always `gh pr create --repo BenevolentFutures/MouthKeys --base liquid-voice`. Never open anything against `altic-dev/FluidVoice`.
- Upstream fixes are ported by hand, never merged. Policy, watermark and ledger: `UPSTREAM.md`.
