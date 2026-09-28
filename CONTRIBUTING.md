# contributing.

thanks for helping. Liquid Voice is for straight voice to text on macOS. the most welcome changes make that more reliable: recognition, delivery, hotkeys, audio and the overlay.

## issues.

- **bugs:** say what you did, what you expected, and what happened. include your macOS version, your Mac, the speech model, and the app you were dictating into. the app log helps; Settings shows where it is. the app's Feedback page drafts an issue for you.
- **ideas:** say what problem it solves before how.

## pull requests.

- target `liquid-voice`.
- one fix or feature per PR. say how you tested it, and on which Mac.
- build and test commands, and the rules the tests follow, are in [CLAUDE.md](CLAUDE.md). it is written for people and agents alike.
- for anything you can see (the overlay, settings, the menu bar), attach a screenshot or a short video.
- keep telemetry off, the upstream updater off, and Fluid Intelligence out.
- never commit a Team ID or an API key. `scripts/check-team-id.sh` works as a pre-commit hook.

## upstream.

Liquid Voice ports fixes from [FluidVoice](https://github.com/altic-dev/FluidVoice) by hand; see [UPSTREAM.md](UPSTREAM.md). if your fix also applies to FluidVoice, please send it to them too. they built nearly all of this.

## license.

contributions are licensed under GPL-3.0, like the rest of the code.
