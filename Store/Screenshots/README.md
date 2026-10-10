# App Store screenshots: Nyx 1.1 (raw)

**Superseded for English iPhone:** `Scripts/capture_store.py` now writes raw iPhone captures to `Store/1.2 v10/raw/` (build 10, 1206×2622, `NN-name.png`). The Spanish captures here (`es/`) stay until the native review.

Native-resolution captures, no alpha channel, captured 2026-10-06; the iPhone (English) and Vision Pro sets were retaken in full that evening (about 8:50 PM Pacific) for build 1.1 (7), Spanish frames 01, 04, 06, 08, 09, 10 earlier that evening. Every iPhone frame uses the `live` scenario (real Open-Meteo forecasts and NPS alerts at capture time, scored by the shipping engine) except the journal, which is illustrative DEBUG seed data with no personal photos. Status bars are 9:41; `-nyx-reduce-motion` gives settled artwork. Every frame was looked at and critiqued (see `PHASE_STATUS.md`).

- `NN-name-6.9.png`: iPhone 18 Pro Max, iOS 27.0, 1320×2868. `6.5-inch/`: 1284×2778 (scaled to width 1284, 6 px trimmed top and bottom).
- `es/`: the same ten in Spanish (`-AppleLanguages "(es)" -AppleLocale es_MX`), with its own `6.5-inch/`.
- `iPad/`: six 13-inch portrait captures, 2064×2752 (iPad Pro 13-inch (M5), iOS 27.0), retaken 2026-10-06 evening from build 7 with live data. Captioned in `Store/Framed/iPad-13-inch/`.
- `Watch/`: six Apple Watch Ultra 3 captures, 422×514, watchOS 27 (Tonight, milestones, week, Parks, dark adaptation, Tonight in red). No paired iPhone in the simulator, so scores are moon and darkness only and say so.
- `Vision/`: four Apple Vision Pro captures, 3840×2160, visionOS 27 (window, immersive core, moonlit, Jupiter's name card).

Order and contents: `SUBMISSION.md` § Screenshots per device. Reproduce the iPhone set with `python3 Scripts/capture_store.py SIMULATOR_ID DERIVED_DATA en|es` after a Debug simulator build (trip and listen are scrolled by DEBUG flags, so the whole set runs unattended), then caption with `swift Scripts/make_store_frames.swift [es]`.
