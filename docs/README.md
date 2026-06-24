# Chordyx GitHub Pages

These files power a simple site for TestFlight and App Store links.

**Setup guide (connect remote + Pages):** see [GITHUB_SETUP.md](./GITHUB_SETUP.md)

## Enable GitHub Pages

1. Push this repo to GitHub (for example `your-username/Chordyx`) — follow [GITHUB_SETUP.md](./GITHUB_SETUP.md).
2. Open **Settings → Pages** in the repository.
3. Under **Build and deployment**, set **Source** to **Deploy from a branch**.
4. Choose branch **`main`** (or `joluesburg`) and folder **`/docs`**.
5. Save. After a minute or two, the site will be live at:

   `https://your-username.github.io/Chordyx/`

## URLs for App Store Connect

| Field | URL |
|-------|-----|
| Privacy Policy | `https://your-username.github.io/Chordyx/privacy.html` |
| Marketing (optional) | `https://your-username.github.io/Chordyx/` |

Replace `your-username` and repo name with your actual GitHub details.

## Other docs

| File | Purpose |
|------|---------|
| [app-store-copy.md](./app-store-copy.md) | Subtitle, description EN/ES, keywords, review notes |
| [testflight-checklist.md](./testflight-checklist.md) | Pre-beta checklist and tester script |

## Customize

- Update the contact email in `index.html` and `privacy.html` if needed.
- Update the effective date in `privacy.html` when you change the policy.
