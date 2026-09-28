# contributing.

thanks for helping. Liquid Voice is for straight voice to text on macOS. the most welcome changes make that more reliable: recognition, delivery, hotkeys, audio and the overlay.

## issues.

- **bugs:** say what you did, what you expected, and what happened. include your macOS version, your Mac, the speech model, and the app you were dictating into. the app log helps: Settings › Debug Settings › Reveal Log File. the app's Feedback page drafts an issue for you.
- **ideas:** say what problem it solves before how.

## build and test.

`./build.sh` makes a signed Debug build; the README covers signing. the test suite, unsigned:

```bash
xcodebuild test -project Fluid.xcodeproj -scheme Fluid -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

if a build sits at `ClangStatCache` and never moves, add `SDK_STAT_CACHE_ENABLE=NO`.

## pull requests.

- target `liquid-voice`.
- one fix or feature per PR. say how you tested it, and on which Mac.
- the house rules, including how tests must behave, are in [CLAUDE.md](CLAUDE.md).
- for anything you can see (the overlay, settings, the menu bar), attach a screenshot or a short video.
- keep telemetry off, the upstream updater off, and Fluid Intelligence out.
- don't change `DEVELOPMENT_TEAM` in the project; `build.sh` passes yours at build time. never commit an API key. `scripts/check-team-id.sh` works as a pre-commit hook that catches a team change.

## upstream.

Liquid Voice ports fixes from [FluidVoice](https://github.com/altic-dev/FluidVoice) by hand; see [UPSTREAM.md](UPSTREAM.md). if your fix also applies to FluidVoice, please send it to them too. they built nearly all of this.

## license.

contributions are licensed under GPL-3.0, like the rest of the code.
