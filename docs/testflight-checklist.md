# TestFlight checklist — Chordyx

Prioritized list before inviting external testers.

---

## P0 — Must work or beta fails

Manual validation on church/home Wi‑Fi (two physical devices). Code polish in this pass does **not** replace checking these boxes.

- [ ] **Two-device flow** — iPhone + iPad (or two iPhones) on same Wi‑Fi: host → join → chord changes sync
- [ ] **Local Network permission** — prompt appears; denying blocks join with clear message
- [ ] **Host approval** — guest join request → host accepts → guest sees chords
- [ ] **Reconnect** — guest locks phone, returns to app; still synced or clear “reconnect” path
- [ ] **Leave session** — both sides clean up without crash
- [ ] **Live view readable** — chord ring legible at arm’s length on iPad in dark room
- [ ] **Metronome audible** — host and guest hear click (or intentional host-only documented)
- [ ] **Privacy URL live** — GitHub Pages `privacy.html` reachable for App Store Connect (now documents optional iCloud join backup)

**Spanish spot-check (P1, but do with P0):** device language ES → Home, Join (Nearby / Code / QR), Live Leave/LIVE, Onboarding Get Started.

---

## P1 — Differentiators worth validating

- [ ] **Band cues** — Hold pauses auto-advance; Vamp repeats; visible on guest
- [ ] **Live piano mode** — host plays; guest sees current chord only
- [ ] **Setlist** — advance to next song; band follows
- [ ] **Count-in** — overlay visible on all devices before first chord
- [ ] **Transpose / capo (guest)** — guest changes view; host chart unchanged
- [ ] **Nashville superscript** — `57` displays as 5⁷ in live view
- [ ] **Pre-service checklist** — host can complete and go live
- [ ] **Spanish UI** — device language ES; spot-check live session strings

---

## P2 — Polish before public App Store

- [ ] **Screenshots** — 6.7" iPhone + 12.9" iPad, dark mode (see `app-store-copy.md`)
- [ ] **App icon** — final 1024×1024, no transparency
- [ ] **Onboarding** — first launch explains host vs join vs practice *(paths page added)*
- [ ] **Error states** — “Connection lost” banner → Reconnect works
- [ ] **Import song** — one happy path (La Cuerda or paste text) documented for testers
- [ ] **Mac build** — smoke test host on Mac + guest on iPad
- [ ] **Remove duplicate UI** — Back + Cancel on same sheet *(CreateProgression Cancel gated behind home shell)*
- [ ] **TestFlight notes** — paste App Review notes from `app-store-copy.md`

---

## Tester script (send to beta users)

```
1. Both devices: same Wi‑Fi, Local Network allowed for Chordyx.
2. Device A → Host a Session → pick a saved progression or practice.
3. Device B → Join a Session → select Device A → accept on A if asked.
4. On A: change chords manually or advance setlist.
5. On B: confirm ring updates within 1 second.
6. On A: tap Hold cue → B should show “Auto-advance paused” / ESPERA.
7. Optional: A opens piano sheet; play a chord → B updates.

Report: device models, iOS version, Wi‑Fi type (church/home), what broke.
```

---

## Known limitations (disclose honestly)

| Limitation | Message for testers |
|------------|---------------------|
| Same local network required | “Nearby join needs same Wi‑Fi/Bluetooth. Internet join code is the cellular backup (iCloud).” |
| Library not auto-synced across devices | “Save progressions on each device unless you enable optional iCloud backup; no automatic library sync by default.” |
| Web import quality varies | “Imported charts may need editing in Lyrics & Sections.” |
| Guest count | “Tested with 2–4 devices; large bands may need stress test.” |
| Incomplete Band Tools | “Audio chord detection is Coming soon; Planning Center import is paste-only beta.” |

---

## Metrics to track (first 10 teams)

1. Did they complete host + join without your help? (Y/N)
2. Did they use it in a **real rehearsal**? (Y/N)
3. Would they use it again next Sunday? (1–5)
4. What did they use before? (Charts / Music Stand / paper / other)
5. One thing that almost made them quit: ___

If #1 < 70% or #3 average < 3, fix connectivity/onboarding before App Store — not marketing.
