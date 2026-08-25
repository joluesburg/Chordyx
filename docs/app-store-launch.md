# Chordyx — App Store launch checklist

Use this as the single source of truth to ship **1.1** to the public App Store.

**Bundle ID:** `Espinosa.Chordyx`  
**Team:** `VR3672X7PZ`  
**Category:** Music  
**Devices:** iPhone + iPad  
**Privacy Policy (target):** https://joluesburg.github.io/Chordyx/privacy.html  
**Support email:** joluesburg@gmail.com

---

## Status snapshot (as of Aug 25, 2026)

| Item | Status |
|------|--------|
| App icon 1024 (opaque, light/dark/tinted) | Ready |
| Privacy Manifest `PrivacyInfo.xcprivacy` | Ready |
| Export compliance (`ITSAppUsesNonExemptEncryption = false`) | Ready |
| Local Network / Bluetooth / Camera / Photos / Mic usage strings | Ready |
| App Store copy EN/ES | Ready in `app-store-copy.md` |
| Privacy HTML in repo | Ready in `docs/privacy.html` |
| GitHub Pages live URL | **Blocked — 404** (enable Pages) |
| Screenshots 6.7" + 12.9" | **You must capture** |
| Paid Apps Agreement / banking | **You in App Store Connect** |
| Age rating / App Privacy answers | **You in App Store Connect** |
| Archive + Submit | **You in Xcode** |

---

## Phase 0 — Unblock App Store Connect (do first)

### 0.1 Enable GitHub Pages (required for Privacy Policy URL)

1. Open https://github.com/joluesburg/Chordyx/settings/pages  
2. **Source:** Deploy from a branch  
3. **Branch:** `joluesburg` (or `main` if you rename) → folder **`/docs`**  
4. Save → wait 1–2 minutes  
5. Confirm these load in Safari:
   - https://joluesburg.github.io/Chordyx/
   - https://joluesburg.github.io/Chordyx/privacy.html  

Without a live Privacy Policy URL, Apple rejects the submission.

### 0.2 App Store Connect account setup

1. https://appstoreconnect.apple.com → **Agreements, Tax, and Banking**  
2. Accept **Paid Applications** (even if the app is free for now)  
3. Complete tax + banking if you plan to charge later  
4. **My Apps → + → New App** (if Chordyx isn’t created yet):
   - Platforms: iOS  
   - Name: Chordyx  
   - Primary language: English (U.S.)  
   - Bundle ID: `Espinosa.Chordyx`  
   - SKU: `chordyx-ios` (any unique string)

---

## Phase 1 — Listing content (paste from docs)

Open the app → **App Information** / **1.1 Prepare for Submission**.

| Field | Source |
|-------|--------|
| Subtitle | `app-store-copy.md` → “Live band chord director” |
| Promotional text | Updated launch text below / in `app-store-copy.md` |
| Description | EN (+ optional ES localization) from `app-store-copy.md` |
| Keywords | from `app-store-copy.md` |
| Support URL | `https://joluesburg.github.io/Chordyx/` |
| Marketing URL | same (optional) |
| Privacy Policy URL | `https://joluesburg.github.io/Chordyx/privacy.html` |
| Category | Music (primary) |

### Promotional text (launch — not beta)

> Host a session on your iPad. Your band sees the chord ring update in real time — metronome, cues, and setlists included. Same Wi‑Fi, optional Internet join code.

### App Privacy questionnaire (Nutrition Labels)

Answer based on current product (no ads, no analytics SDKs):

| Data type | Collect? | Linked to identity? | Used for tracking? |
|-----------|----------|---------------------|--------------------|
| Contact info (name you type as display name) | Optional — stays on device / peers | No Chordyx account | No |
| User content (progressions, lyrics you save) | On device; optional iCloud if user enables | Via Apple ID only if iCloud on | No |
| Identifiers | No Chordyx analytics ID | — | No |
| Usage / diagnostics | Only if user shares with Apple | Apple | No |
| Audio / photos / camera | Only when user grants for features | On device | No |

**Tracking:** No  
**Third-party advertising:** No  
**Data used to track you:** None  

For CloudKit / Multipeer, describe as: session data processed on device / Apple iCloud when Internet join is enabled — not sold.

### Age rating

Typically **4+** if no unrestricted web, no gambling, no mature content. Answer the questionnaire honestly (user import loads public web pages the user chooses — still usually 4+).

---

## Phase 2 — Screenshots & preview

Capture in **dark mode** on:

1. **iPhone 6.7"** (e.g. iPhone 16 Pro Max simulator or device)  
2. **iPad 12.9"** / 13" (required if you support iPad)

Suggested 6 frames (captions in `app-store-copy.md`):

1. Home — Host / Join  
2. Live chord ring (host)  
3. Guest view + NEXT  
4. Band cues pad  
5. Setlist + metronome  
6. Notation / transpose  

Optional: 15–30s App Preview video of host → join → chord change.

---

## Phase 3 — Build & archive

In Xcode (physical signing with your Apple Development / Distribution team):

1. Select scheme **Chordyx**, destination **Any iOS Device (arm64)**  
2. Version **1.1**, Build **≥ 1** (increment each upload)  
3. **Product → Archive**  
4. Organizer → **Distribute App → App Store Connect → Upload**  
5. Wait for processing in App Store Connect → select the build on the version page  

### Review Notes (paste)

```
Chordyx uses Multipeer Connectivity for peer-to-peer sessions between nearby devices on the same local network.

To test:
1. Install on two devices (iPhone/iPad) on the same Wi‑Fi.
2. Device A: Home → Host a Session → start session.
3. Device B: Home → Join a Session → accept join if prompted on host.
4. Host changes chords; guest sees chord ring update in real time.

Local Network permission is required for Bonjour discovery (_chordyx._tcp).

No Chordyx login. Sessions are primarily peer-to-peer on the local network. Optional Internet join codes use the user’s Apple iCloud (CloudKit). Optional song import fetches public web pages the user provides.

Contact: joluesburg@gmail.com
```

---

## Phase 4 — Pre-submit smoke test (do not skip)

From `testflight-checklist.md` **P0** on two real devices:

- [ ] Host → Join → chords sync  
- [ ] Local Network permission path  
- [ ] Leave session cleanly  
- [ ] Live ring readable on stage distance  
- [ ] Metronome  
- [ ] Privacy URL opens in Safari  

---

## Phase 5 — Submit for Review

1. Complete all yellow/red missing items in App Store Connect  
2. **Add for Review** → **Submit to App Review**  
3. Typical first review: 24–48 hours (can be longer)  

### Common rejection risks for Chordyx

| Risk | Mitigation |
|------|------------|
| Privacy URL 404 | Enable GitHub Pages before submit |
| Reviewer can’t test Multipeer | Clear Review Notes + offer second device / demo video |
| Mic string mentions removed Solo Drums | Updated — optional on-device analysis only |
| Icon transparency | Icons flattened to opaque RGB |
| Incomplete App Privacy answers | Use table above |
| Crash on launch | Archive smoke-test on a device before upload |

---

## Pricing for v1.1 (recommendation)

Ship **Free** first (max adoption + reviews), then add StoreKit Pro unlock in 1.2.

If you want paid from day one: **$6.99–$9.99** one-time (Paid Apps Agreement must be active).

---

## After approval

1. **Release** manually or automatic after approval  
2. Share TestFlight → App Store link with 3–5 worship bands  
3. Ask for a review after a successful Sunday use  
4. Then implement monetization (StoreKit) when you choose the model  

---

## Related docs

| File | Purpose |
|------|---------|
| [app-store-copy.md](./app-store-copy.md) | Subtitle, description, keywords, screenshots |
| [testflight-checklist.md](./testflight-checklist.md) | Device QA |
| [privacy.html](./privacy.html) | Privacy Policy page |
| [GITHUB_SETUP.md](./GITHUB_SETUP.md) | Pages setup |
| [README.md](./README.md) | Pages overview |
