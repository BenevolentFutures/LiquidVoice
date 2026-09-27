# Upstream

Liquid Voice is a GPL-3 fork of [FluidVoice](https://github.com/altic-dev/FluidVoice) by altic-dev (git remote `upstream`). It is a separate product focused on straight voice to text: no Fluid Intelligence, no telemetry, no upstream updater.

## Policy

- **We port by hand. We never merge upstream.** Our typing, audio and overlay code has diverged where upstream's fixes land, so a merge conflicts and would drag in features we cut.
- `git cherry-pick -x <sha>` only when it applies cleanly. Otherwise read `git show <sha>` and re-implement the fix on our code.
- Credit every port in the commit message: `Ported from altic-dev/FluidVoice@<sha> (<original subject>) by <original author>.` Say what you left out and why.
- A commit that mixes a dictation fix with something on the never-port list: take only the dictation part.

## Never port

- Fluid Intelligence, private AI, the Edit Mode private model, "Smart" styles, the prompt picker on the pill.
- Meetings: FluidMeet, Fluid Notes, AEC, captions, speakers.
- Dashboard, onboarding redesign, stats card, What's New.
- Analytics of any kind (DAU, latency events, weekly batches, FI TPS).
- Zeppelin search.
- The updater. It would replace this build with stock FluidVoice.
- Upstream's overlay redesign. Adapt the behavior into our overlay in `BottomOverlayView.swift` instead.

## Where we stand

| | SHA | Note |
|---|---|---|
| Fork base | `d62adc9` | `d62adc9ac35467f9933fda689111514545466a2d` |
| Watermark | `3b509ea1` | `upstream/main`, reviewed through 2026-09-24 |

Move the watermark forward after each review, in the same PR as the ports.

## Next review

```sh
git fetch upstream
git log --no-merges 3b509ea1..upstream/main
```

Skip anything on the never-port list. For each remaining commit, port it or record why not, in the ledger below.

## Port ledger

| Upstream SHA | Subject | Status | Our PR |
|---|---|---|---|
