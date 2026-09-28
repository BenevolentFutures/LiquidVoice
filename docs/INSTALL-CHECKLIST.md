# Liquid Voice install checklist

Run once after installing a new build. It takes about ten minutes, fifteen the first time after the identity change.

Install with `./build.sh install` (with Atin, never unattended). It quits the app, backs up the installed one to `~/Backups/liquid-voice-<timestamp>/Liquid Voice.app`, installs the new build, and prints the exact rollback command. Keep that output.

Tail the log in a c11 pane first:

```sh
tail -F ~/Library/Logs/LiquidVoice/Fluid.log | grep -E 'IDENTITY_MIGRATION|STOP_SUMMARY|frontmost_check|send_key|SPOKEN_SEND|stop_target_capture|DELIVERY'
```

Rollback: run the command `./build.sh install` printed. By hand: quit Liquid Voice, then

```sh
rm -rf "/Applications/Liquid Voice.app" && ditto "$HOME/Backups/liquid-voice-<timestamp>/Liquid Voice.app" "/Applications/Liquid Voice.app" && open "/Applications/Liquid Voice.app"
```

The previous app still finds all of its own data, because the identity migration copies and never moves. Dictations made with the new app are not in the old one.

## 0. First launch after the identity change (once)

The app is now `com.stage11.liquidvoice`, no longer FluidVoice's `com.FluidApp.app`. macOS treats it as a new app: your data comes over on the first launch, but Microphone and Accessibility must be granted again.

1. Open `/Applications/Liquid Voice.app`. The window opens on **Getting Started**. Under Quick Setup, **Grant Microphone Permission** and **Enable Accessibility Access** are pending. The voice model shows ready after a second or two (the model cache is shared, nothing downloads).
2. The log (new folder: `~/Library/Logs/LiquidVoice/`) shows, within a second of launch, with your own counts:
   ```
   IDENTITY_MIGRATION start from=com.FluidApp.app folder=FluidVoice to=com.stage11.liquidvoice folder=LiquidVoice
   IDENTITY_MIGRATION step=defaults outcome=copied keys=119 replaced=0 from=com.FluidApp.app
   IDENTITY_MIGRATION step=folder outcome=copied files=2 bytes=<n> from=FluidVoice to=LiquidVoice (FluidVoice left in place)
   IDENTITY_MIGRATION step=login_item outcome=not_needed (launch at startup was off)
   IDENTITY_MIGRATION finished result=ok defaults=copied(119) folder=copied(2) loginItem=not_needed elapsedMs=<n>
   ```
   Any `outcome=failed` or `result=incomplete`: stop and tell Cairn before dictating. A failed step is not marked done and runs again on the next launch; the old data is untouched. (If a retry replaces values the app wrote in between, it first saves them to `~/Backups/liquid-voice-displaced-defaults-*.plist` and logs `displaced=`. If the folder step finds a `LiquidVoice` folder already there, it adds only the missing files and logs `outcome=merged`.)
   A line `IDENTITY_MIGRATION skipped reason=not_installed` means the app was not started from `/Applications`.
3. Accessibility: click **Open Settings** on that step. System Settings opens at Privacy & Security > Accessibility, with a floating guide. Drag Liquid Voice into the list (or click +, pick `/Applications/Liquid Voice.app`) and switch it on. Within two seconds the app restarts itself once. You may see two "Liquid Voice" rows; the one that was already on belongs to the old identifier. Leave it until you no longer need rollback (section 7).
4. Microphone: after the restart, press the dictation hotkey (or click **Grant Access** under Getting Started, or in Settings > Microphone Permission). macOS asks; choose **Allow**. That press does not record; the next one does. If you choose Don't Allow, the hotkey shows a "Microphone access is off" card whose gear opens Privacy & Security > Microphone.
   If macOS asks whether Liquid Voice may use the keychain item `com.fluidvoice.provider-api-keys`, choose Always Allow (only happens when an AI provider key was saved; there is none today).
5. Your data carried over:
   - History lists your past dictations.
   - Custom Dictionary lists your entries and replacements.
   - Settings: the same dictation, Paste Last and Reprocess Last hotkeys; the same microphone, overlay position and size, sounds and text insertion mode.
   - `defaults read com.stage11.liquidvoice LiquidVoiceIdentityMigrationDefaults` prints the date and the key count.
6. Launch at startup, only if you had it on: Settings shows it on, and System Settings > General > Login Items lists Liquid Voice. If the log says `requires_approval`, approve it there; if it says `outcome=failed`, turn Launch at startup on again in Settings. The old app's login item cannot be removed by the new app and would start the backup copy: remove the older "Liquid Voice" entry there with the minus button.
7. Dictate once into c11. The text lands. Then go on with section 1.

## 1. Delivery into c11 (must pass)
1. Dictate into a Claude Code prompt in c11: one short, one long, then two quick ones in a row. Every text lands, in order. Your clipboard is unchanged afterward.
   Log: `frontmost_check stage=before_paste waitedMs=0 result=in_front`, and one `STOP_SUMMARY` per dictation.
2. Stop in c11, then Cmd-Tab to Safari while it transcribes. Either c11 comes back and gets the text, or a card appears and the text is on the clipboard. It is never silent.
3. Copy an image (a screenshot to the clipboard), then dictate into c11. After about 1 s, Preview > File > New from Clipboard shows the image.
4. Stop, then immediately click where the pill was, over c11. The click reaches c11. Nothing is typed again or copied. Repeat after a long dictation.

## 2. Other apps
5. Dictate into TextEdit, then into a Chrome textarea. The text lands.
6. Click a toolbar button so focus is on it, then dictate. The "No text field focused" card appears, and ⌘V pastes the transcript.
7. If you use Word, Zed or Warp: dictate without moving focus. There is no false "Text wasn't inserted".

## 3. Hotkeys, mic and media
8. Hold mode: quick tap and release, including with a Bluetooth mic. Recording always stops.
9. Mouse-button hotkey held, then Cmd-Tab mid-hold and release. Recording stops, and there is no stray click.
10. Lock the screen, press the hotkeys, unlock. Nothing recorded.
11. Music playing with "pause media" on: it pauses, then resumes after the text lands.

## 4. Spoken Send (Settings: turn it on)
12. In a Claude Code prompt in c11, say "fix the typo in the README, send it". The text lands without the phrase and the prompt submits.
    Log: `stop_target_capture pid=<c11> element=true`, then `SPOKEN_SEND outcome=sent`. If you see `focus_unreadable` instead, tell Cairn: the feature is failing safe and needs a fix.
13. Say "Draft the reply but don't send it." No send, and no countdown.
14. Say "… send it", then Cmd+2 to another pane while it transcribes. The text may land in the new pane, but no Return is sent. The log gives the reason.
15. Answer a Claude question with "Yes, go ahead and send it". It types "Yes" and submits.
16. In Terminal.app, say "echo hello send it". `echo hello` lands with no Return.

## 5. The cut
17. Settings has no Fluid-1 or Fluid Intelligence anywhere. Updates is one line. Analytics says nothing is sent.
18. `defaults read com.stage11.liquidvoice | grep -iE 'fluid-1|FluidIntelligence'` prints nothing.

## 6. Speed
19. After about ten dictations: `python3 scripts/stop_path_latency.py --last 10`. The old build's median was 306 ms; the new one should be well under. The old build's log stays readable: `python3 scripts/stop_path_latency.py ~/Library/Logs/Fluid/Fluid.log`.

## 7. Cleanup, once rollback is no longer needed (optional)
- Remove the old identity's permission rows: `tccutil reset Accessibility com.FluidApp.app` and `tccutil reset Microphone com.FluidApp.app`.
- Archive, then remove, the old data: `defaults export com.FluidApp.app ~/Backups/com.FluidApp.app.plist && defaults delete com.FluidApp.app`, then `~/Library/Application Support/FluidVoice` and `~/Library/Logs/Fluid/`.
- Every install keeps a full app copy in `~/Backups/liquid-voice-*`. Delete all but the last one or two now and then.
- The migration runs once. To redo it (say, after a rollback during which you kept dictating in the old app): quit Liquid Voice, `defaults delete com.stage11.liquidvoice`, move `~/Library/Application Support/LiquidVoice` aside, and open the app. That replaces the new app's data with the old app's.
