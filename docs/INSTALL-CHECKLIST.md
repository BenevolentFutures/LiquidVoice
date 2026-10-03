# MouthKeys install checklist

This is the maintainer's own post-install checklist; contributors do not need it.

Run once after installing a new build. It takes about ten minutes, fifteen the first time after the identity change.

Install with Atin, never unattended, by the path that matches the installed app's signer: `codesign -dvv /Applications/MouthKeys.app 2>&1 | grep -m1 Authority=`.

### Install over a Developer ID app

The installed app came from a DMG (`Authority=Developer ID Application: …`). Never `./build.sh install` here: it signs with Apple Development, a different designated requirement, and Accessibility silently stops matching (hotkeys dead, `Attempt 1 failed` in the log). Instead:

1. **Build** Release from a clean checkout of `origin/main` (a fresh clone or worktree, never a checkout with local changes): `scripts/release.sh build`. It needs no certificate, so a separate build Mac can run it; copy the product back with `ditto -c -k --keepParent MouthKeys.app - | ditto -x -k - <dir>` (ditto keeps the framework symlinks).
2. **Sign** with Developer ID into a scratch folder, without notarizing (a locally built app carries no quarantine, so Gatekeeper does not check it):
   ```sh
   MOUTHKEYS_SKIP_NOTARIZE=1 MOUTHKEYS_DIST_DIR=<scratch> scripts/release.sh package <dir>/MouthKeys.app
   ```
3. **Match** the signature: the `designated =>` lines of `codesign -d -r- /Applications/MouthKeys.app` and `codesign -d -r- <scratch>/MouthKeys.app` must be identical. If they differ, stop. **Exception, the install that changes the bundle ID** (the installed app is not `com.stage11.mouthkeys`, i.e. 0.1.0 to 0.1.1): the `identifier` clause differs by design, so compare the signer instead: `codesign -dvv <app> 2>&1 | grep -E '^(Authority|TeamIdentifier)='` must print the same lines for both. Then follow section 0, not step 6.
4. **Back up** and verify:
   ```sh
   B=~/Backups/mouthkeys-$(date +%Y%m%d-%H%M%S); mkdir -p "$B"
   ditto /Applications/MouthKeys.app "$B/MouthKeys.app" && codesign --verify --deep --strict "$B/MouthKeys.app"
   ```
5. **Swap:** `osascript -e 'quit app "MouthKeys"'`, wait until `pgrep -x MouthKeys` prints nothing, then `ditto <scratch>/MouthKeys.app /Applications/MouthKeys.app.new`, move the old app aside, move `.new` into place, remove the old one, `open /Applications/MouthKeys.app`.
6. **Check** (same bundle ID only): `grep HOTKEY_TAP ~/Library/Logs/MouthKeys/Fluid.log | tail -1` says `state=installed`. `state=waiting_for_accessibility` means the signature did not match: roll back by quitting the app and putting `$B/MouthKeys.app` back the same way.

### Install over an Apple Development app

`./build.sh install`. It quits the app and waits for it to go, backs up the installed one to `~/Backups/mouthkeys-<timestamp>/MouthKeys.app` (and a second copy named by `MOUTHKEYS_LEGACY_INSTALL_PATH`, if given, beside it) and verifies each copy (bundle ID and `codesign --verify --deep --strict`), prints the rollback command, and only then copies the new build next to the old one and swaps it in. Keep that output.

Tail the log in a c11 pane first:

```sh
tail -F ~/Library/Logs/MouthKeys/Fluid.log | grep -E 'IDENTITY_MIGRATION|STOP_SUMMARY|frontmost_check|send_key|SPOKEN_SEND|stop_target_capture|DELIVERY|OVERLAY_OUTCOME'
```

Rollback after `./build.sh install`: run the command it printed:

```sh
bash ~/Backups/mouthkeys-<timestamp>/rollback.sh
```

It quits the app, waits for it to go, puts every backed-up app back where it was (a second copy under its own name), takes out a `MouthKeys.app` that was not there before, and opens what it restored. The previous app still finds all of its own data, because the identity migration copies and never moves. Dictations made with the new app are not in the old one.

## 0. First launch after the identity change (once)

From 0.1.1 the app is `com.stage11.mouthkeys`. 0.1.0 ran under the app's earlier identifiers (listed in `PreviousAppIdentity`, `Sources/Fluid/Persistence/AppStorageLocation.swift`), and FluidVoice before it as `com.FluidApp.app`. macOS treats the new identity as a new app: your data comes over on the first launch from the newest earlier identity that has any, but Microphone and Accessibility must be granted again.

0. Before installing: nothing may exist yet under the new identity, or the one-time copy is skipped or merged into it. `defaults read com.stage11.mouthkeys` should say the domain does not exist, and `~/Library/Application Support/MouthKeys` should not exist. `./build.sh install` checks both on a first install of the new identity; if either exists it explains, prints the commands to move them aside, and installs only after you type `install`. Move them aside unless Cairn says otherwise.
1. Open `/Applications/MouthKeys.app`. The window opens on **Getting Started**. Under Quick Setup, **Grant Microphone Permission** and **Enable Accessibility Access** are pending. The voice model shows ready after a second or two (the model cache is shared, nothing downloads). Quick Setup has four steps and none of them is AI Enhancement; AI Enhancement sits alone under **Advanced** in the sidebar.
2. The log (new folder: `~/Library/Logs/MouthKeys/`) shows, within a second of launch, with your own counts:
   ```
   IDENTITY_MIGRATION start from=<0.1.0 domain> folder=<0.1.0 folder> to=com.stage11.mouthkeys folder=MouthKeys
   IDENTITY_MIGRATION step=defaults left_behind=<n> (the old identity's own keys)
   IDENTITY_MIGRATION step=defaults outcome=copied keys=119 replaced=0 attempt=1 from=<0.1.0 domain>
   IDENTITY_MIGRATION step=folder outcome=copied files=2 bytes=<n> skipped=0 from=<0.1.0 folder> to=MouthKeys (<0.1.0 folder> left in place)
   IDENTITY_MIGRATION step=login_item outcome=not_needed (launch at startup was off)
   IDENTITY_MIGRATION finished result=ok defaults=copied(119) folder=copied(2) loginItem=not_needed elapsedMs=<n>
   ```
   Any `outcome=failed` or `result=incomplete`: stop and tell Cairn before dictating. The old data is untouched either way. A failed step is not marked done and runs once more on the next launch. Your old data always wins: a value or file the new app already had and the copy changes is saved first, to `~/Backups/mouthkeys-displaced-defaults-*.plist` or `~/Backups/mouthkeys-displaced-folder-*/`, and logged as `displaced=`. If a retry had to set data aside and still failed, the migration stops retrying: an alert before the app opens names the log and the backup (`outcome=halted`). To try again after a fix: `defaults delete com.stage11.mouthkeys MouthKeysIdentityMigrationDefaultsHalted`.
   Other lines: `outcome=merged` means a `MouthKeys` folder already existed and the old files were merged into it; `skipped_symlink=` or `skipped_unreadable=` name old files left behind, on purpose; `skipped reason=not_installed` means the app was not started from `/Applications`.
3. Accessibility: click **Open Settings** on that step. System Settings opens at Privacy & Security > Accessibility, with a floating guide. Drag MouthKeys into the list (or click +, pick `/Applications/MouthKeys.app`) and switch it on. Within a second the step turns green and the hotkeys arm, with no restart (`HOTKEY_TAP state=installed` in the log). You may see an older row next to MouthKeys (named "MouthKeys" or "FluidVoice", from an earlier identity); the one that was already on belongs to the old identifier. Leave it until you no longer need rollback (section 7).
4. Microphone: after the restart, press the dictation hotkey (or click **Grant Access** under Getting Started, or in Settings > Microphone Permission). macOS asks; choose **Allow**. That press does not record; the next one does. If you choose Don't Allow, the hotkey shows a "Microphone access is off" card whose gear opens Privacy & Security > Microphone.
   If no dialog appears and MouthKeys is missing from Privacy & Security > Microphone, the app was signed without the microphone entitlement: `codesign -d --entitlements - --xml "/Applications/MouthKeys.app" | grep -c device.audio-input` must print 1. `build.sh` now refuses to install a build without it (2026-09-28).
   If macOS asks whether MouthKeys may use the keychain item `com.fluidvoice.provider-api-keys`, choose Always Allow (only happens when an AI provider key was saved; there is none today).
5. Your data carried over:
   - History lists your past dictations.
   - Custom Dictionary lists your entries and replacements.
   - Settings: the same dictation, Paste Last and Reprocess Last hotkeys; the same microphone, overlay position and size, sounds and text insertion mode.
   - `defaults read com.stage11.mouthkeys MouthKeysIdentityMigrationDefaults` prints the date and the key count.
6. Login items, every time: an earlier identity's login item can start the backup copy in `~/Backups` (still trusted for Accessibility, under the same process name), and then two apps capture the hotkey. Open System Settings > General > Login Items and remove any MouthKeys or FluidVoice entry that is not the new app. Launch at startup, only if you had it on: Settings shows it on, and System Settings > General > Login Items lists MouthKeys. If the log says `requires_approval`, approve it there; if it says `outcome=failed`, turn Launch at startup on again in Settings. The old app's login item cannot be removed by the new app. It is registered under the earlier identifier and could start the backup copy, or an old Release build in `~/Projects/MouthKeys/DerivedData/Build/Products/Release/`: remove the older entry there (it may still be named "MouthKeys" or "FluidVoice") with the minus button.
7. Dictate once into c11. The text lands. Then go on with section 1.

## 1. Delivery into c11 (must pass)
1. Dictate into a Claude Code prompt in c11: one short, one long, then two quick ones in a row. Every text lands, in order. Your clipboard is unchanged afterward.
   Log: `frontmost_check stage=before_paste waitedMs=0 result=in_front`, and one `STOP_SUMMARY` per dictation.
2. Stop in c11, then Cmd-Tab to Safari while it transcribes. Either c11 comes back and gets the text, or a card appears and the text is on the clipboard. It is never silent.
3. Copy an image (a screenshot to the clipboard), then dictate into c11. After about 1 s, Preview > File > New from Clipboard shows the image.
4. The pill now stays up after the paste for 0.6 s ("Pasted into c11"), then fades. During that hold, click the chips and the pill: nothing is typed again or copied. Click the transparent margin just outside the pill (between the chips, or a few points beyond the edge): the click reaches c11. After the fade, click where the pill was: the click reaches c11. Repeat after a long dictation.

## 2. Other apps
5. Dictate into TextEdit, then into a Chrome textarea. The text lands.
6. Click a toolbar button so focus is on it, then dictate. The "No text field focused" card appears, and ⌘V pastes the transcript.
7. If you use Word, Zed or Warp: dictate without moving focus. There is no false "Text wasn't inserted".

## 3. Hotkeys, mic and media
8. Hold mode: quick tap and release, including with a Bluetooth mic. Recording always stops.
9. Mouse-button hotkey held, then Cmd-Tab mid-hold and release. Recording stops, and there is no stray click.
10. Lock the screen, press the hotkeys, unlock. Nothing recorded.
11. Music playing with "pause media" on: it pauses, then resumes after the text lands.
12. Accessibility, live (any build with a new signature, and every first install): with MouthKeys off in Privacy & Security > Accessibility, the menu bar menu shows "Hotkeys Paused" and Settings > Global Hotkey says "Hotkeys paused: needs Accessibility" with your saved shortcuts listed. Switch MouthKeys on: within a second the step or card turns green and the dictation hotkey works, no relaunch. The log shows `HOTKEY_TAP state=waiting_for_accessibility` once, then `HOTKEY_TAP state=installed`, with no repeating retry lines. If the switch is on but the app stays untrusted, wait 3 s back in the app: the "Already switched on?" hint appears, and `grep PERMISSION_DIAG ~/Library/Logs/MouthKeys/Fluid.log` names any older copy of the app (Trash, a drag cache, a DerivedData Release build) that has to be deleted first.

## 4. Spoken Send (Settings: turn it on)
12. In a Claude Code prompt in c11, say "fix the typo in the README, send it". The text lands without the phrase and the prompt submits.
    Log: `stop_target_capture pid=<c11> element=true`, then `SPOKEN_SEND outcome=sent`. If you see `focus_unreadable` instead, tell Cairn: the feature is failing safe and needs a fix.
13. Say "Draft the reply but don't send it." No send, and no countdown.
14. Say "… send it", then Cmd+2 to another pane while it transcribes. The text may land in the new pane, but no Return is sent. The log gives the reason.
15. Answer a Claude question with "Yes, go ahead and send it". It types "Yes" and submits.
16. In Terminal.app, say "echo hello send it". `echo hello` lands with no Return.

## 5. The cut
17. Settings has no Fluid-1 or Fluid Intelligence anywhere. Updates is one line. Analytics says nothing is sent.
18. `defaults read com.stage11.mouthkeys | grep -iE 'fluid-1|FluidIntelligence'` prints nothing.

## 6. Speed
19. After about ten dictations: `python3 scripts/stop_path_latency.py --last 10`. The old build's median was 306 ms; the new one should be well under. The old build's log stays readable: `python3 scripts/stop_path_latency.py ~/Library/Logs/Fluid/Fluid.log`.

## 7. The Signal overlay and menu bar
20. Dictate into c11 with the pill in view. Listening: the preview (newest words, "…" in front once it fills three lines), the trace with its orange write head gliding left smoothly while you talk (12 bars a second of speech, heights easing, no stepping) and holding still in pauses longer than a quarter second, a solid orange square and a running mono timer flush right; the foot row has the target-app icon and the microphone name centred as a pair, the live word count at its left end; square chips spaced evenly down the rails. The pill is shorter than before (130 pt, round 6) and the trace runs nearly the full width.
20a. The trace follows your voice on your usual microphone at a normal speaking distance: syllables stand up tall, pauses drop to the 2 pt floor, and a steady background (a fan, music) settles flat within a few seconds. After the stop: `grep TRACE_SUMMARY ~/Library/Logs/MouthKeys/Fluid.log | tail -3`. A start logs `START_SUMMARY` (hotkey to capture, the pill's show). On speech, `raised` should be a good share of `pushed`, and `pushed` close to 12 a second of speech; a trace that stays flat shows `raised=0` and the `loudest` level that did not clear the `gate`.
20b. The pill, a recovery card and the history card float on a soft shadow (dark and light). Click just outside the pill's edge, on the shadow: the click reaches c11. After the fade no shadow is left where the pill was. Let a recovery card dismiss itself: its shadow fades with it, step by step, not after it. Leave it idle for more than 8 s (the pill parks offscreen), then dictate: the shadow sits under the pill, not off to one side. Start latency after that idle park: `grep START_SUMMARY ~/Library/Logs/MouthKeys/Fluid.log | tail -5` (`hotkeyToCaptureMs`, `overlayVisibleMs`, `overlayWasParked=true`, and `shadowAfterMs`, the shadow arriving after the pill).
20c. Start a dictation: 0 WORDS shows at once at the bottom left (right-aligned in a fixed 4-digit box) and steps up as words land; WPM at the bottom right climbs and drifts; neither label moves; SEND replaces WPM when you say the send phrase.
20d. With the Hollyland lapel mic selected, the foot row reads HOLLYLAND LAPEL nn% within a few seconds of the overlay showing; switch the mic off and within a minute the percent goes away. The icon and label do not shift when the percent appears. Turn both transmitters on: the label still reads HOLLYLAND LAPEL with one percent, the lower of the two, and does not shift. Another mic shows its own name. No Input Monitoring prompt appears. Log: `grep MIC_BATTERY ~/Library/Logs/MouthKeys/Fluid.log | tail -3` (one line per change, both mics recorded, e.g. `mic1=off mic2=33% result=ok`, or `mic1=80% mic2=33% result=ok` with both on).
21. Stop a short dictation: it goes straight from listening to "Pasted into c11 · N WORDS" (no Transcribing flash), held 0.6 s, then a 120 ms fade. Log: `OVERLAY_OUTCOME … shown=pasted`. A long dictation first shows the hollow square, the dimmed frozen preview and the orange sweep, then Pasted.
22. Move the pointer over the pill, then over each chip, then away: the pill takes no bracket (it is not clickable), each chip draws its bracket outside the box under the pointer only, one at a time, and fades; nothing moves. With SEND showing, the pill takes a bracket (a click cancels the Return). On a recovery card, Copy and Dismiss take a bracket on hover; the card itself does not. Check it over a black terminal in light appearance too (the brackets keep their white halo).
23. Press a chip quickly: it inverts for a visible moment. Copy turns orange with a check for about a second.
24. Open History from the chip: the ruled table opens centred over the overlay, 6 pt above it, the chip stays inverted, rows invert on hover, a click inserts, an outside click closes it. Hover the card: no bracket on it (only clickable things take one).
25. Drag the pill somewhere else, dictate again: it appears there. Double-click it: it returns to bottom-centre, 50 pt up.
25a. Click History: the card appears at once (`grep HISTORY_OPEN ~/Library/Logs/MouthKeys/Fluid.log | tail -3` shows click_to_action_ms under ~50), centred over the overlay; double-click on the pill still resets its position, and a double-click on a chip does not.
26. Switch System Settings > Appearance to Light: the pill, chips, cards and history card turn to print on paper. Back to Dark.
27. Spoken Send on: say "… send it" and stop talking. SEND (orange) shows at the foot row's right end, then the flat trace with an orange bar draining over 1.5 s and the timer counting 1.5 to 0.0; then "Sent to c11 · N WORDS · RETURN". Again, but press Esc while SEND shows (or click the pill, or the Cancel chip): NO SEND, the bar stops in ink, the dictation keeps recording, and Claude Code does not see the Esc (the turn is not interrupted). Stop: the text lands and the prompt is not submitted. Press Esc twice while SEND shows: the second press cancels the dictation. After a stop, Esc while SEND shows drops the Return; a second Esc only dismisses the pill (the text still lands). In Terminal.app the placard reads NO SEND, dimmed, as soon as the phrase is heard.
28. Recovery card: focus a button and dictate. The pill grows upward into "Couldn't paste into …" with the reason, the transcript, Copy and Dismiss; the trace row, mic row and chips stay exactly where they were.
28a. Speech recognition is back (hard to trigger on purpose; check when it happens, or with `grep "Recognition-back notice row" ~/Library/Logs/MouthKeys/Fluid.log`): the pill shows the headline, "A kept dictation is waiting" and Reprocess · Dismiss in its preview area, with no growth and no orange top rule. Hovering Reprocess draws its own bracket; Reprocess transcribes the kept recording; Dismiss and the Cancel chip close it; left alone it goes after 10 s.
29. Menu bar: the grin (four teeth a jaw) at rest; the grin plus a solid square while listening, the lower jaw opening and closing as you talk and shut in pauses; an outlined square only when a pass is slow; a bracket inside the mark on hover and while the menu is open. The menu has the mono MOUTHKEYS header with the state, Start Dictation with the hotkey (it starts one), the microphone, History… (opens History), Copy Last Transcript, Custom Dictionary, Open MouthKeys, Settings…, Quit.
30. The Dock and Finder show the new icon: an ink tile and a grin of white keycap teeth with one orange tooth right of centre in the lower jaw; in the Dock the teeth read as keys. List views show plain teeth, the orange tooth still there.

## 8. Cleanup, once rollback is no longer needed (optional)
- Remove the old identity's permission rows: `tccutil reset Accessibility com.FluidApp.app` and `tccutil reset Microphone com.FluidApp.app`.
- Archive, then remove, the old data: `defaults export com.FluidApp.app ~/Backups/com.FluidApp.app.plist && defaults delete com.FluidApp.app`, then `~/Library/Application Support/FluidVoice` and `~/Library/Logs/Fluid/`.
- Every install keeps a full app copy in `~/Backups/mouthkeys-<timestamp>/` (`ls -d ~/Backups/mouthkeys-20*`). Delete all but the last one or two now and then. Never delete `~/Backups/mouthkeys-displaced-*`: that is data the identity migration set aside, and the only copy of it.
- The migration runs once. To redo it (say, after a rollback during which you kept dictating in the old app): quit MouthKeys, `defaults delete com.stage11.mouthkeys`, move `~/Library/Application Support/MouthKeys` aside, and open the app. That replaces the new app's data with the old app's.
