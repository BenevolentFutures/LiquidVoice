# Liquid Voice

<p align="center"><b><i>Straight voice to text for macOS, built to land every word</i></b></p>

<!-- hero: the overlay mid-dictation, image in docs/ -->

---

listen.

you talk to your computer all day now. prompts for agents, replies, notes. dictation should be the fastest way in, but it fails quietly. the text lands in the wrong window. a terminal swallows it. the clipboard you were holding is gone. you find out when you look up.

the problem is not hearing you. the problem is. delivery.

**Liquid Voice is on-device dictation for macOS.** hold or tap a hotkey, speak, and the text lands where you were typing when you stopped. the speech model runs on your Mac: Parakeet, Nemotron, Cohere Transcribe, Whisper or Apple Speech. when it sees a paste fail, it tells you and puts the words on your clipboard. AI cleanup through a provider you choose is there too, off until you turn it on.

## how it differs from FluidVoice.

Liquid Voice is a fork of [FluidVoice](https://github.com/altic-dev/FluidVoice) by altic-dev, taken on 2026-08-15 at upstream [`d62adc9`][base]. it is a separate product now. what changed since the fork follows. some of it is upstream's later work, ported by hand; [UPSTREAM.md](UPSTREAM.md) credits each commit.

- **no Fluid Intelligence.** the private AI layer is gone, with its settings and prompt routes. [#3]
- **no telemetry.** analytics are hard-wired off and the keys are blank. [`0e2948a`][0e2948a], [#3]
- **no upstream updater.** it would install stock FluidVoice over this build. you update by rebuilding. [`19202c1`][19202c1], [#3]
- **no silent drops it can see.** when a paste fails in a way it can detect, a card shows, and the text goes on your clipboard unless you copied something since. your own clipboard comes back, images and files included. [#4]
- **Reliable Paste for c11.** upstream forces Ghostty onto Reliable Paste; we added [c11](https://github.com/Stage-11-Agentics/c11), Stage 11's terminal multiplexer. back-to-back dictations queue instead of dropping. [`8ed75b9`][8ed75b9], [`8ab26a8`][8ab26a8]
- **Spoken Send, allowed in c11.** end with "send it" and Return follows the text. upstream blocks terminals; we allow c11, only in the pane you stopped in. off by default. [#7], [#8]
- **a faster stop.** in a headless benchmark with a 13,600-entry history, stop-path work outside the model fell from a 145 ms median to 4 ms; model time is unchanged. a stalled model no longer loses the recording: it is kept for Reprocess, even across a restart. [#9], [#10]
- **hotkey, mic and media fixes.** holds that always end, removed mics that stay removed, media resumed only if we paused it, a hung mic routed around, and a hotkey to reprocess the last dictation. [#2], [`8295536`][8295536], [`68afebc`][68afebc], [`0e2948a`][0e2948a]
- **a redesigned overlay.** a vertical action rail, a scrolling voice trace, a history browser, drag anywhere, and copy, reprocess and cancel one click away. [overlay history][overlay]

## install.

no binaries yet. you build it. building needs Xcode 26, which needs macOS 15.6 or later; the app itself runs on macOS 15 or later. by engine: Parakeet, Nemotron and Cohere need Apple Silicon. Apple Speech needs macOS 26. Whisper up to Medium and Apple ASR Legacy also run on Intel, which this fork has not tested.

```bash
git clone -b liquid-voice https://github.com/BenevolentFutures/LiquidVoice.git
cd LiquidVoice
./build.sh install
```

`./build.sh install` builds a signed Release, backs up the installed app to `~/Backups/`, quits it, and replaces `/Applications/Liquid Voice.app`. to update, pull and run it again.

**signing.** the install needs an Apple Development identity, so macOS keeps your permissions across rebuilds. a free Personal Team is enough: add an Apple Account in Xcode › Settings › Accounts, then create an Apple Development certificate. with several teams, set `FLUIDVOICE_DEVELOPMENT_TEAM` to the Team ID you want. without one, `./build.sh unsigned` makes an unsigned Debug build, `DerivedData/Build/Products/Debug/Liquid Voice Debug.app`. it is a separate app with its own settings and data, and macOS may ask for Accessibility again after each rebuild.

**permissions.** Microphone, to hear you. Accessibility, to type into other apps. Apple ASR Legacy also asks for Speech Recognition. then pick a speech model; the default on Apple Silicon, Parakeet TDT v3, is about a 460 MiB download.

## privacy.

no telemetry, no account. your audio and your text stay on your Mac unless you choose otherwise. the app goes online for three things, each your choice:

- downloading the speech model you pick.
- AI cleanup, if you set up a provider: OpenAI, Anthropic, Google, xAI, Groq, Cerebras, OpenRouter or a custom endpoint. Ollama and LM Studio stay on your Mac.
- **Apple ASR Legacy**, which lets macOS choose where speech is recognized, and that may be Apple's servers. every other engine runs on the Mac.

Feedback opens a draft GitHub issue in your browser. the app posts nothing; you read it and submit it yourself.

## upstream.

we don't merge FluidVoice. we read its fixes and port the ones that belong here by hand, crediting each in the commit. what we took, what we skipped, and why: [UPSTREAM.md](UPSTREAM.md).

## contributing.

bugs and ideas go in [issues](https://github.com/BenevolentFutures/LiquidVoice/issues). pull requests target `liquid-voice`; start with [CONTRIBUTING.md](CONTRIBUTING.md).

---

*your voice is the fastest way you have to get a thought out of your head. it should land where you meant it.*

---

## license.

GPL-3.0, unchanged from FluidVoice. See [LICENSE](LICENSE). FluidVoice versions published before 2026-02-23 were licensed under Apache License 2.0 ([upstream's note][relicense]); Liquid Voice was forked after that date.

**Modification notice.** Liquid Voice is a modified version of [FluidVoice](https://github.com/altic-dev/FluidVoice) by altic-dev. Atin Woodard has modified it since 2026-08-15. The changes are summarized under *how it differs from FluidVoice* above; [UPSTREAM.md](UPSTREAM.md) and the git history record each one.

FluidVoice by altic-dev and its contributors built nearly all of this: the speech pipeline, hotkeys, typing, settings and model downloads. The models themselves come from NVIDIA, Cohere, OpenAI and Apple. If Liquid Voice is useful to you, please [sponsor altic-dev](https://github.com/sponsors/altic-dev).

Liquid Voice is not affiliated with or endorsed by altic-dev.

[base]: https://github.com/altic-dev/FluidVoice/commit/d62adc9ac35467f9933fda689111514545466a2d
[relicense]: https://github.com/altic-dev/FluidVoice/commit/76bc885e875e368fe5938fa44bd7246669c6b84f
[0e2948a]: https://github.com/BenevolentFutures/LiquidVoice/commit/0e2948ac
[19202c1]: https://github.com/BenevolentFutures/LiquidVoice/commit/19202c1a
[8ed75b9]: https://github.com/BenevolentFutures/LiquidVoice/commit/8ed75b9a
[8ab26a8]: https://github.com/BenevolentFutures/LiquidVoice/commit/8ab26a8f
[8295536]: https://github.com/BenevolentFutures/LiquidVoice/commit/82955361
[68afebc]: https://github.com/BenevolentFutures/LiquidVoice/commit/68afebce
[overlay]: https://github.com/BenevolentFutures/LiquidVoice/commits/liquid-voice/Sources/Fluid/Views/BottomOverlayView.swift
[#2]: https://github.com/BenevolentFutures/LiquidVoice/pull/2
[#3]: https://github.com/BenevolentFutures/LiquidVoice/pull/3
[#4]: https://github.com/BenevolentFutures/LiquidVoice/pull/4
[#7]: https://github.com/BenevolentFutures/LiquidVoice/pull/7
[#8]: https://github.com/BenevolentFutures/LiquidVoice/pull/8
[#9]: https://github.com/BenevolentFutures/LiquidVoice/pull/9
[#10]: https://github.com/BenevolentFutures/LiquidVoice/pull/10
