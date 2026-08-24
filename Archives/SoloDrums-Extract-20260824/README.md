# Solo Drums — snapshot for a future app

Frozen copy of Chordyx Mac Solo / Auto Band / Service Learning sources so they can become a separate product later without hunting through the main app.

**Source:** Chordyx (`SOURCE_COMMIT.txt`)  
**Scope:** drums + bass accompaniment engines, Mac solo panel, Auto Band, Service Learning

## What’s in this folder (self-contained-ish)

| Area | Files |
|------|--------|
| Engines | `DrumAccompanimentEngine`, `DrumSoundSource`, `DrumPhraseArrangement`, `DrumMIDILoopPacks`, `DrumAudioUnitCatalog`, `BassAccompanimentEngine` |
| Mac VM slices | `SessionViewModel+MacSoloAccompaniment`, `+MacAutoBand`, `+MacServiceLearning` |
| UI | `SoloAccompanimentMacPanel`, `ServiceLearningMacSection` |
| Models | `SoloDrum*`, `SoloServicePreset`, `ServiceLearning*`, `BandLearningModels` |
| Polish | `SoloDrumPolish` |

## Still wired into Chordyx (not copied — peel carefully)

These stay in the main app and **call into** Solo Drums. When you extract to a new target/app, either keep thin stubs or re-home the prefs/UI hooks:

- `SessionViewModel.swift` — owns engines, start/stop, sync fields
- `ChordyxPreferences.swift` — Solo Drums toggles / defaults
- `PreferencesHubView.swift`, `LiveHostControlRail.swift`, `SessionView.swift` (Mac)
- `RingCueStrip.swift`, `SessionEnhancementViews.swift`, `WorshipViews.swift`
- `MetronomeEngine.swift` — shared tempo clock with accompaniment
- `PlatformDevice.swift` — Mac-only gates
- Possibly audio input / learning engines if Auto Band depends on them

## Suggested next steps (when you want “otra app”)

1. New Xcode project (or target) **Mac-first**.
2. Drop in this `Services/` + `Models/` + `Utilities/` set first; get audio playing with a minimal host VM.
3. Port `SessionViewModel+MacSoloAccompaniment` into a dedicated `SoloDrumsController` (don’t keep the Chordyx session name).
4. Bring UI panel last; strip Multipeer / guest sync.
5. In Chordyx later: hide Solo from Live path or `#if` / feature-flag Mac Advanced.

## What this is *not*

- Not a runnable app by itself.
- Not removed from Chordyx — main app still has the live code.
- Not a git commit (unless you ask to commit `Archives/`).

When you’re ready: “extrae Solo Drums a proyecto nuevo” or “quítarlo del camino Live en Chordyx”.
