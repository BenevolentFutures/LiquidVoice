// Liquid Voice — shared mock data for the visual-language prototypes.
// Realistic dictations: prompts to coding agents in c11, emails, notes.
// Durations in seconds, word counts real, mics and target apps as they appear on a Mac.
// Not wired to real data.

window.LV_MOCK = {
  mics: [
    { name: "MacBook Pro Microphone", kind: "builtin" },
    { name: "AirPods Pro", kind: "bluetooth" },
    { name: "Hollyland Lapel Mic", kind: "usb" },
    { name: "Studio Display Microphone", kind: "builtin" },
  ],
  targets: [
    { app: "c11", icon: "c11", title: "Style Studio — c11" },
    { app: "Mail", icon: "mail", title: "Re: Q4 rollout — Mail" },
    { app: "Notes", icon: "notes", title: "Launch checklist — Notes" },
    { app: "Slack", icon: "slack", title: "#eng-platform — Slack" },
    { app: "Safari", icon: "safari", title: "Pull request 412 — Safari" },
  ],
  // Live listening snippets: what the streaming preview shows while speaking.
  livePreview: [
    "okay so the retry path is still admitting duplicates when the queue",
    "make the overlay follow the system appearance but keep the trace",
    "can you look at why the second display gets the wrong",
  ],
  // History: newest first. seconds = recording duration.
  history: [
    {
      id: "h1", when: "2026-09-27T15:04:12", target: "c11", mic: "MacBook Pro Microphone", seconds: 41, words: 118, delivered: true,
      text: "Okay, take a look at the retry admission path in the queue worker. When the same job ID lands twice inside the lease window we are admitting both, and the second one clobbers the first one's checkpoint. I think the fix is to key the admission set on job ID plus lease epoch instead of just job ID. Write a failing test first that reproduces the double admission, then fix it, then run the whole queue suite. Don't touch the scheduler. When you're done give me a one-line summary and the diff stat.",
    },
    {
      id: "h2", when: "2026-09-27T14:51:40", target: "c11", mic: "MacBook Pro Microphone", seconds: 12, words: 34, delivered: true,
      text: "Rename the tab to Review, set the description, and then read the three open PRs on the retry-admission branch and tell me which one you'd merge first and why.",
    },
    {
      id: "h3", when: "2026-09-27T14:38:05", target: "c11", mic: "MacBook Pro Microphone", seconds: 66, words: 189, delivered: false,
      text: "So the thing I want to change about the overlay is that the chips should never move. Right now when the failure row appears the whole pill grows upward and the rails re-center, and that means my cursor is no longer over the cancel chip. Reserve the height for the failure row from the start, or anchor the rails to the bottom of the pill so that they stay put when the pill grows. Also I want the trace to keep scrolling during silence, the bars should just be tiny, not stopped, because a stopped trace reads as a hang. And one more thing: the copy chip needs feedback, a checkmark for a second or a little pulse, anything, right now I click it and I have no idea if it worked. Do the reserve-height change first since it's the one that bites me most, ship it as its own commit, then the silence scrolling, then the copy feedback. Screenshot each state and put them in the PR description.",
    },
    {
      id: "h4", when: "2026-09-27T13:20:33", target: "Mail", mic: "AirPods Pro", seconds: 38, words: 96, delivered: true,
      text: "Hi Priya, thanks for the walkthrough yesterday. Two things from our side. First, we can commit to the October 14 date for the pilot as long as the SSO piece lands by the 7th. Second, on pricing, let's keep the per-seat number where it is and revisit after the first ninety days with real usage. I'll send the revised order form tomorrow morning. If anything in there is off, just call me. Best, Sam",
    },
    {
      id: "h5", when: "2026-09-27T12:02:19", target: "Notes", mic: "AirPods Pro", seconds: 24, words: 61, delivered: true,
      text: "Launch checklist note. The desktop build is the fixed point. The mobile build follows a week later. Anything that touches billing waits for the whole team to sign off, which means the pricing page only changes on release day. Write this down properly in the release doc and stop re-deriving it every sprint.",
    },
    {
      id: "h6", when: "2026-09-27T11:47:58", target: "c11", mic: "Hollyland Lapel Mic", seconds: 9, words: 22, delivered: true,
      text: "Status check. What's merged, what's in flight, what's blocked, and what do you need from me. Numbered.",
    },
    {
      id: "h7", when: "2026-09-27T11:31:02", target: "Slack", mic: "Hollyland Lapel Mic", seconds: 19, words: 47, delivered: true,
      text: "Heads up, the nightly sync job paused itself overnight after three failed pushes. I've restarted it and it's caught up, but if anybody pushed to the staging mirror between two and six this morning double check it landed.",
    },
    {
      id: "h8", when: "2026-09-27T10:58:44", target: "c11", mic: "MacBook Pro Microphone", seconds: 53, words: 142, delivered: true,
      text: "Let's do the paste safety work. The bug is that when the transcription finishes fast, under about three hundred milliseconds, the modifier flags from the hotkey are still held when we synthesize command V, so the paste turns into a command shift V or nothing. Wait for the flags to clear, poll the current flags with a short timeout, and only then post the paste event. If they never clear within half a second, fall back to typing the text character by character. Add a log line for each path so I can see which one fired. Test it in c11 and in TextEdit.",
    },
    {
      id: "h9", when: "2026-09-26T18:12:27", target: "Mail", mic: "MacBook Pro Microphone", seconds: 71, words: 203, delivered: true,
      text: "Hi Marcus, following up on the design review. I agree the settings window is doing too much. My proposal is that we cut it to four panes: general, microphone, hotkeys, and dictionary. Everything about AI providers goes away in this fork because we're not shipping the intelligence layer. The stats page also goes. History stays but becomes a plain list you can search, with the transcript as the main thing you see, not a card with five badges. On the overlay, I'm keeping the vertical rail and the wide trace. I've spent six weeks on those and they're right. What I want from a new visual language is that everything else falls in line behind them. Let me know if you want to pair on it Thursday, I'll have prototypes by then. Thanks, Atin",
    },
    {
      id: "h10", when: "2026-09-26T16:40:09", target: "c11", mic: "AirPods Pro", seconds: 5, words: 11, delivered: true,
      text: "Yes, go ahead and merge it. Then close the worktree.",
    },
    {
      id: "h11", when: "2026-09-26T16:02:51", target: "c11", mic: "AirPods Pro", seconds: 88, words: 251, delivered: true,
      text: "New task. I want a small command line tool called sensorq that reads the room sensor over Bluetooth and prints CO2, temperature, humidity and pressure as one line, with a JSON flag for scripts. It should cache the last reading for sixty seconds so that ten scripts asking at once don't hammer the sensor. If the sensor is out of range print a clear error with the last known reading and its age, don't just hang. Use the existing Bluetooth helper in the shared utilities package rather than writing a new one. Ship it with a short readme that explains how to call it and how to tell if the reading is stale. Tests should run without the sensor present, so mock the Bluetooth layer. Keep the whole thing under five hundred lines if you can. When it's done, run it for real once, paste the real output into the PR, and tell me how long the cold read took.",
    },
    {
      id: "h12", when: "2026-09-26T15:21:36", target: "Safari", mic: "MacBook Pro Microphone", seconds: 15, words: 39, delivered: true,
      text: "Looks good to me. One nit: the error message on line 42 says microphone unavailable but the actual cause is the permission being denied, so say that instead. Approving now, fix the message before merge.",
    },
  ],
};

// Helpers shared by prototypes.
window.LV = {
  fmtDuration(s) {
    const m = Math.floor(s / 60), r = s % 60;
    return m ? `${m}:${String(r).padStart(2, "0")}` : `0:${String(r).padStart(2, "0")}`;
  },
  fmtTime(iso) {
    const d = new Date(iso);
    let h = d.getHours(), ap = h >= 12 ? "PM" : "AM"; h = h % 12 || 12;
    return `${h}:${String(d.getMinutes()).padStart(2, "0")} ${ap}`;
  },
  fmtDay(iso) {
    const d = new Date(iso), now = new Date("2026-09-27T16:00:00");
    const sameDay = d.toDateString() === now.toDateString();
    if (sameDay) return "Today";
    const y = new Date(now); y.setDate(now.getDate() - 1);
    if (d.toDateString() === y.toDateString()) return "Yesterday";
    return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  },
  // Deterministic pseudo-random for repeatable traces.
  seeded(seed) {
    let s = seed >>> 0;
    return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
  },
};
