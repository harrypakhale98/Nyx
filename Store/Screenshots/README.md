# App Store screenshots: Nyx 1.1 (raw)

Native-resolution captures, no alpha channel, captured 2026-10-06 (around 12:15 PM Pacific) for build 1.1 (6). Every iPhone frame uses the `live` scenario (real Open-Meteo forecasts and NPS alerts at capture time, scored by the shipping engine) except the journal, which is illustrative DEBUG seed data with no personal photos. Status bars are 9:41; `-nyx-reduce-motion` gives settled artwork. Every frame was looked at and critiqued (see `PHASE_STATUS.md`).

- `NN-name-6.9.png`: iPhone 18 Pro Max, iOS 27.0, 1320×2868. `6.5-inch/`: 1284×2778 (scaled to width 1284, 6 px trimmed top and bottom).
- `es/`: the same ten in Spanish (`-AppleLanguages "(es)" -AppleLocale es_MX`), with its own `6.5-inch/`.
- `iPad/`: six 13-inch landscape captures, 2752×2064 (iPad Pro 13-inch (M5), iOS 27.0), from 2026-10-06; raw is what App Store Connect takes.
- `Watch/`: six Apple Watch Ultra 3 captures, 422×514, watchOS 27 (Tonight, milestones, week, Parks, dark adaptation, Tonight in red). No paired iPhone in the simulator, so scores are moon and darkness only and say so.
- `Vision/`: four Apple Vision Pro captures, 3840×2160, visionOS 27 (window, immersive core, moonlit, name card).

Order and contents: `SUBMISSION.md` § Screenshots per device. Reproduce the iPhone set with `python3 Scripts/capture_store.py SIMULATOR_ID DERIVED_DATA en|es` after a Debug simulator build (frames 7 and 9 need one scroll each; the script pauses and says where), then caption with `swift Scripts/make_store_frames.swift [es]`. 1.0 captures: `Store/1.0/Screenshots`.
