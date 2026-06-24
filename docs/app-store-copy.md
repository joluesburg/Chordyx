# Chordyx — App Store copy & positioning

Use this document when filling App Store Connect and TestFlight notes.

---

## One-line positioning

| Language | Line |
|----------|------|
| **ES** | El director lleva la progresión; la banda la sigue en vivo — sin PDFs ni cuenta en la nube. |
| **EN** | You lead the chord progression; your band follows live — no PDFs, no cloud account. |

---

## Subtitle (30 characters max)

**EN (recommended):** `Live band chord director`  
*(28 chars)*

**ES (if localized listing):** `Acordes en vivo para banda`  
*(26 chars)*

Alternatives:
- EN: `Lead chords. Band follows.` (27)
- ES: `Dirige acordes en escenario` (27)

---

## Promotional text (170 chars, editable anytime)

**EN:**
> Host a session on your iPad. Your band sees the chord ring update in real time — metronome, cues, and setlists included. Same Wi‑Fi. No subscription required for beta.

**ES:**
> Haz de host en tu iPad. Tu banda ve el anillo de acordes al instante — metrónomo, señales y setlists incluidos. Misma Wi‑Fi. Sin suscripción en la beta.

---

## Description — English (App Store)

**Paragraph 1 (hook):**
Chordyx is built for the moment on stage — when you lead and the band needs to follow you, not a static PDF.

**What you get:**
• **Host or join** a live session with nearby musicians over local Wi‑Fi  
• **Chord ring** — large, readable progression view with next-chord preview  
• **Live piano / MIDI mode** — play chords; guests see only what you play  
• **Band cues** — Hold, Vamp, Break, and section jumps synced to every device  
• **Metronome & count-in** — tempo and beats per bar shared with the band  
• **Setlists** — multiple songs in one session  
• **Per-musician view** — transpose and capo on guest devices without changing the chart  
• **Notation** — chord symbols, Solfège, or Nashville numbers  
• **Import songs** — pull chords and lyrics from supported web sources  
• **Practice solo** — rehearse with the ring and metronome  

**Built for:**
Worship leaders, small bands, and keyboardists who want direct control during rehearsal or service — without setting up Planning Center or a cloud library.

**Requirements:**
Two or more Apple devices on the same local network for host/guest sessions. Local Network permission is required for discovery.

**Privacy:**
Sessions are peer-to-peer on your local network. We do not run a cloud service or sell your data. See our privacy policy on the support URL.

---

## Description — Español (localized listing)

**Párrafo 1:**
Chordyx está hecho para el momento en escenario — cuando tú diriges y la banda necesita seguirte, no un PDF estático.

**Incluye:**
• **Host o invitado** — sesión en vivo con músicos cercanos por Wi‑Fi local  
• **Anillo de acordes** — progresión grande y legible con vista del siguiente acorde  
• **Modo piano / MIDI** — tú tocas; los invitados ven el acorde actual  
• **Señales de banda** — Hold, Vamp, Break y saltos de sección sincronizados  
• **Metrónomo y count-in** — tempo compartido con la banda  
• **Setlists** — varias canciones en una sesión  
• **Vista por músico** — transpose y cejilla en cada dispositivo  
• **Notación** — símbolos, solfeo o números Nashville  
• **Importar canciones** — acordes y letra desde fuentes web compatibles  
• **Práctica solo** — ensaya con anillo y metrónomo  

**Para quién:**
Líderes de alabanza, bandas pequeñas y tecladistas que quieren control directo en ensayo o servicio — sin montar Planning Center ni biblioteca en la nube.

**Requisitos:**
Dos o más dispositivos Apple en la misma red local. Se necesita permiso de Red local para descubrir sesiones.

---

## Keywords (100 chars, EN — comma separated, no spaces after commas)

**Recommended:**
`chord,band,worship,live,sync,metronome,setlist,nashville,stage,music`

**Avoid:** planning center, multitrack, moises, pdf reader (wrong intent, bad ASO)

---

## Category

**Primary:** Music  
**Secondary:** Utilities (or Lifestyle if Music is crowded)

---

## App Review notes (paste in Review Notes)

```
Chordyx uses Multipeer Connectivity for peer-to-peer sessions between nearby devices on the same local network.

To test:
1. Install on two devices (iPhone/iPad) on the same Wi‑Fi.
2. Device A: Home → Host a Session → start session.
3. Device B: Home → Join a Session → accept join if prompted on host.
4. Host changes chords; guest sees chord ring update in real time.

Local Network permission is required for Bonjour discovery (_chordyx._tcp).

No login, no server backend. Optional song import fetches public web pages user provides.

Contact: joluesburg@gmail.com
```

---

## Screenshot storyboard (6 frames)

| # | Screen | Caption EN | Caption ES |
|---|--------|------------|------------|
| 1 | Home menu | Host or join in seconds | Host o invitado al instante |
| 2 | Live chord ring (host) | Lead the progression | Tú llevas la progresión |
| 3 | Guest view + next chord | Band follows in real time | La banda sigue en vivo |
| 4 | Band cues pad | Hold, Vamp, Break — synced | Señales sincronizadas |
| 5 | Setlist + metronome | Full set, shared tempo | Setlist y tempo compartido |
| 6 | Nashville / transpose | Every musician, their view | Cada músico, su vista |

Use dark mode screenshots — matches the app and stage context.

---

## What NOT to claim

- “Replace Planning Center” — you will get comparison shoppers who churn  
- “AI stems / isolate instruments” — different product, legal risk  
- “Works anywhere without Wi‑Fi” — Multipeer needs local network  
- “30,000 song library” — you don’t have it  

---

## Pricing suggestion (post-beta)

| Model | Rationale |
|-------|-----------|
| **Free + tip jar** | Max adoption for niche; hard to monetize |
| **One-time purchase ($4.99–$9.99)** | Matches “tool for my band” not “church SaaS” |
| **Free host / paid guest** | Awkward for worship context |
| **Subscription** | Only if you add cloud setlists + backup later |

For v1 beta: **free TestFlight**, gather 10 bands who complete a full rehearsal flow.
