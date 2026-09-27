# Liquid Voice

macOS dictation app, forked from FluidVoice (see `UPSTREAM.md`). The product is **straight voice to text**. Fluid Intelligence is removed, telemetry is hard-off (`AnalyticsConfig.isConfigured` is false), and the upstream updater is off (`AppDelegate.upstreamUpdatesDisabled`). Keep all three that way.

Atin dictates into Claude Code in c11 all day with the installed app. Text delivery into c11 and Ghostty (forced Reliable Paste) must never regress.

## Never touch the installed app

- Never touch `/Applications/Liquid Voice.app`, quit or relaunch the running Liquid Voice, write `defaults` for `com.FluidApp.app`, or touch `~/Library/Application Support/FluidVoice`. Never run `./build.sh install` without Atin.
- Debug builds are isolated: bundle ID `com.FluidApp.app.dev` (own UserDefaults) and data folder `FluidVoice-Dev`. Any code that picks an Application Support folder must use `AppStorageLocation.folderName`.
- Logs: the installed app writes `~/Library/Logs/Fluid/Fluid.log`; Debug builds and test runs write `~/Library/Logs/Fluid-Dev/Fluid.log` (`AppStorageLocation.logFolderName`). Read either freely.

## Build

```sh
xcodebuild -project Fluid.xcodeproj -scheme Fluid -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath DerivedData DEVELOPMENT_TEAM=UKQ4QALWD4 SDK_STAT_CACHE_ENABLE=NO build
```

- Always pass `SDK_STAT_CACHE_ENABLE=NO`. On this machine `clang-stat-cache` hangs at 0% CPU on its second run in a DerivedData folder, and the build sits at "ClangStatCache" with no error. If you see that, kill `clang-stat-cache` and re-run with the flag.
- Product: `DerivedData/Build/Products/Debug/Liquid Voice Debug.app`.
- The warning about `CTranscribe.framework/Versions/Current` symlinks is harmless for Debug builds.

## Test

- Same command with `test`. Iterate with `-only-testing:FluidDictationIntegrationTests/<Suite>`, then run the full suite before a PR.
- The test host is `Liquid Voice Debug.app`, which launches briefly. Never click through or dismiss a system permission prompt; report it.
- Known flaky: `DirectAudioReliabilityTests.testReadinessGateRearmingCancelsExistingWaiter`. Re-run it alone before calling it a regression.
- App sources are a synchronized folder; test files are listed in `project.pbxproj` by hand. A new test file needs a project entry, so prefer adding to an existing test file.
- swiftlint and swiftformat are not installed. Follow `.swiftlint.yml`, `.swiftformat` and the surrounding code.

## Validate

Green tests are not a working product. Mic capture, Accessibility and real paste into c11 need a check in the running app. When you cannot drive it yourself, hand Atin concrete steps.

## Git and PRs

- `gh repo set-default` is `BenevolentFutures/LiquidVoice`. The integration branch is `liquid-voice`.
- Always `gh pr create --repo BenevolentFutures/LiquidVoice --base liquid-voice`. Never open anything against `altic-dev/FluidVoice`.
- Upstream fixes are ported by hand, never merged. Policy, watermark and ledger: `UPSTREAM.md`.
