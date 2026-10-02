# security.

## reporting a vulnerability.

please report it privately, not in a public issue. use GitHub's private vulnerability reporting: open the repository's Security tab, choose "Report a vulnerability", and describe what you found, the macOS version, and how to reproduce it. that opens a private security advisory only the maintainers can see.

you will get a reply, and a fix or an explanation, as soon as the maintainers can manage. this is a small project, so there is no formal timeline.

## what the app does and does not do.

- no telemetry. the app sends no analytics and no crash reports, and has no account.
- no server. there is no Liquid Voice backend; nothing is uploaded to one.
- the upstream updater is off, so the app never checks for versions.
- the only network use is what you choose: model downloads, an AI provider you set up, and Apple's own recognition if you pick Apple ASR Legacy. the README's privacy section lists each.
- dictations and history stay in `~/Library/Application Support/LiquidVoice`.

## scope.

in scope: anything in this repository that could expose your audio, your transcripts, your clipboard, or your keychain items, or that lets another process abuse the Microphone or Accessibility permissions you granted.

out of scope: vulnerabilities in macOS itself, or in third-party libraries (report those upstream; tell us if a pinned version here needs bumping).
