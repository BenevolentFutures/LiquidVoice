# Liquid Voice

<p align="center"><b><i>Straight voice to text for macOS, built to land every word</i></b></p>

<p align="center"><img src="docs/images/overlay.png" width="560" alt="The Liquid Voice overlay mid-dictation: the live transcript above a voice trace, a 13-second timer, 43 words and 203 words per minute in the foot row, and the active mic. History and copy sit on the left rail, cancel and reprocess on the right."></p>

<p align="center"><sub>mid-dictation: the live transcript, your voice as a trace, and the word count and words per minute as you speak.</sub></p>

---

listen.

you talk to your computer all day now. prompts for agents, replies, notes. dictation should be the fastest way in, but it fails quietly. the text lands in the wrong window. a terminal swallows it. the clipboard you were holding is gone. you find out when you look up.

the problem is not hearing you. the problem is. delivery.

**Liquid Voice is on-device dictation for macOS.** hold or tap a hotkey, speak, and the text lands where you were typing when you stopped. the speech model runs on your Mac: Parakeet, Nemotron, Cohere Transcribe, Whisper or Apple Speech. when it sees a paste fail, it tells you and puts the words on your clipboard. AI cleanup through a provider you choose is there too, off until you turn it on.

## built on FluidVoice.

Liquid Voice is a fork of [FluidVoice](https://github.com/altic-dev/FluidVoice) by altic-dev, taken on 2026-08-15 at upstream [`d62adc9`][base]. FluidVoice did the hard part: the speech pipeline, the model integrations, hotkeys, typing into other apps, settings and model downloads.

**why we forked.** we dictate into coding agents all day, and we needed one thing done perfectly: every word lands where we were typing. FluidVoice was growing in many directions at once: an AI assistant of its own, analytics, its own updater, connections back to its servers. we wanted the engine without the rest. so we cut Liquid Voice down to the job and spent the time on what matters to us: delivery that never drops a word, a faster stop, and an interface that stays quiet until you reach for it. if you want FluidVoice's AI features, FluidVoice is the app for that.

some of what follows is upstream's later work, ported by hand; [UPSTREAM.md](UPSTREAM.md) credits each commit.

### what's new.

- **a new interface.** the overlay, history, cards, menu bar and icon share one visual language, Signal: square, flat, monochrome, with orange marking only what is live. the controls are cleaner. copy, reprocess, cancel and history sit one click away on a slim rail beside the pill, and nothing on screen moves unless it means something. [#17], [design notes](design/visual-language/DESIGN.md)
- **a live voice trace.** a scrolling trace of your voice, calibrated to the recording, so you can see it hearing you. [#22], [#24]
- **live counters.** a timer, a word count and words per minute while you speak. [#27]
- **your mic at a glance.** the active mic shows in the overlay, with the battery level of a Hollyland lapel mic. [#29], [#30]
- **a history browser.** recent dictations, each one click from copy or reprocess. drag the overlay anywhere. [#25]
- **paste you can trust.** when a paste fails in a way the app can detect, a card shows, and the text goes on your clipboard unless you copied something since. your own clipboard comes back, images and files included. back-to-back dictations queue instead of dropping. [#4], [`8ab26a8`][8ab26a8]
- **Reliable Paste for c11.** upstream forces Ghostty onto Reliable Paste; we added [c11](https://github.com/Stage-11-Agentics/c11), Stage 11's terminal multiplexer. [`8ed75b9`][8ed75b9]
- **Spoken Send, allowed in c11.** end with "send it" and Return follows the text. upstream blocks terminals; we allow c11, only in the pane you stopped in. off by default. [#7], [#8]
- **a faster stop.** in a headless benchmark with a 13,600-entry history, stop-path work outside the model fell from a 145 ms median to 4 ms; model time is unchanged. a stalled model no longer loses the recording: it is kept for Reprocess, even across a restart. [#9], [#10]
- **hotkey, mic and media fixes.** holds that always end, removed mics that stay removed, media resumed only if we paused it, a hung mic routed around, and a hotkey to reprocess the last dictation. [#2], [`8295536`][8295536], [`68afebc`][68afebc], [`0e2948a`][0e2948a]

<p align="center"><img src="docs/images/history.png" width="520" alt="The Liquid Voice history browser open directly above the recording overlay: recent dictations newest first, each with its time, word count and destination app. Below it, the overlay is mid-dictation with its live transcript, voice trace, timer and counters."></p>

<p align="center"><sub>the history browser opens right where you are, above the overlay. click a dictation to insert it again.</sub></p>

### what's left out.

Liquid Voice is narrower on purpose.

- **Fluid Intelligence.** FluidVoice's AI layer and its settings are not included. AI cleanup through a provider you choose is still here. [#3]
- **telemetry.** analytics are hard-wired off and the keys are blank. [`0e2948a`][0e2948a], [#3]
- **the built-in updater.** it updates to FluidVoice, which would replace this build, so it is off. you update by rebuilding. [`19202c1`][19202c1], [#3]

## install.

no binaries yet. you build it. building needs Xcode 26, which needs macOS 15.6 or later; the app itself runs on macOS 15 or later. by engine: Parakeet, Nemotron and Cohere need Apple Silicon. Apple Speech needs macOS 26. Whisper up to Medium and Apple ASR Legacy, the older Apple engine, also run on Intel, which this fork has not tested.

```bash
git clone --depth 1 -b liquid-voice https://github.com/BenevolentFutures/LiquidVoice.git
cd LiquidVoice
./build.sh install
```

`./build.sh install` builds a signed Release, quits a running Liquid Voice, backs up the installed app to `~/Backups/`, and replaces `/Applications/Liquid Voice.app`. it prints the command to roll back. to update, pull and run it again.

**coming from FluidVoice.** stock FluidVoice and older Liquid Voice builds share the bundle ID `com.FluidApp.app`. if you have used either on this Mac, Liquid Voice copies its settings, dictionary and history once, on first launch, and never changes the original. after that the two apps keep separate data and can run side by side. macOS does not carry permissions over, so you grant them again.

**signing.** the install needs an Apple Development identity, so macOS keeps your permissions across rebuilds. a free Personal Team is enough: add an Apple Account in Xcode › Settings › Accounts, then create an Apple Development certificate. with several teams, set `LIQUIDVOICE_DEVELOPMENT_TEAM` to the Team ID you want. without one, `./build.sh unsigned` makes an unsigned Debug build, `DerivedData/Build/Products/Debug/Liquid Voice Debug.app`. it is a separate app with its own settings and data, and macOS may ask for Accessibility again after each rebuild.

**permissions.** Microphone, to hear you. Accessibility, to type into other apps. Apple ASR Legacy also asks for Speech Recognition. then pick a speech model; the default on Apple Silicon, Parakeet TDT v3, is about a 460 MiB download.

## privacy.

no telemetry, no account. your audio and your text stay on your Mac unless you choose otherwise. the app goes online for three things, each your choice:

- downloading the speech model you pick.
- AI cleanup, if you set up a provider: OpenAI, Anthropic, Google, xAI, Groq, Cerebras, OpenRouter or a custom endpoint. Ollama and LM Studio stay on your Mac.
- **Apple ASR Legacy**, which lets macOS choose where speech is recognized, and that may be Apple's servers. every other engine runs on the Mac.

Feedback opens a draft GitHub issue in your browser. the app posts nothing; you read it and submit it yourself.

## upstream.

we follow FluidVoice's work and port the fixes that fit here by hand, crediting each in the commit. what we took, what we skipped, and why: [UPSTREAM.md](UPSTREAM.md).

## contributing.

bugs and ideas go in [issues](https://github.com/BenevolentFutures/LiquidVoice/issues). pull requests target `liquid-voice`; start with [CONTRIBUTING.md](CONTRIBUTING.md).

---

*your voice is the fastest way you have to get a thought out of your head. it should land where you meant it.*

---

## license.

GPL-3.0, unchanged from FluidVoice. See [LICENSE](LICENSE). FluidVoice versions published before 2026-02-23 were licensed under Apache License 2.0 ([upstream's note][relicense]); Liquid Voice was forked after that date.

**Modification notice.** Liquid Voice is a modified version of [FluidVoice](https://github.com/altic-dev/FluidVoice) by altic-dev. Atin Woodard has modified it since 2026-08-15. The changes are summarized under *built on FluidVoice* above; [UPSTREAM.md](UPSTREAM.md) and the git history record each one.

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
[#2]: https://github.com/BenevolentFutures/LiquidVoice/pull/2
[#3]: https://github.com/BenevolentFutures/LiquidVoice/pull/3
[#4]: https://github.com/BenevolentFutures/LiquidVoice/pull/4
[#7]: https://github.com/BenevolentFutures/LiquidVoice/pull/7
[#8]: https://github.com/BenevolentFutures/LiquidVoice/pull/8
[#9]: https://github.com/BenevolentFutures/LiquidVoice/pull/9
[#10]: https://github.com/BenevolentFutures/LiquidVoice/pull/10
[#17]: https://github.com/BenevolentFutures/LiquidVoice/pull/17
[#22]: https://github.com/BenevolentFutures/LiquidVoice/pull/22
[#24]: https://github.com/BenevolentFutures/LiquidVoice/pull/24
[#25]: https://github.com/BenevolentFutures/LiquidVoice/pull/25
[#27]: https://github.com/BenevolentFutures/LiquidVoice/pull/27
[#29]: https://github.com/BenevolentFutures/LiquidVoice/pull/29
[#30]: https://github.com/BenevolentFutures/LiquidVoice/pull/30
