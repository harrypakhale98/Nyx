# Captioned App Store screenshots

Six frames built from the raw captures in `Store/Screenshots` by `swift Scripts/make_store_frames.swift` (run from the repo root). Each puts a short serif headline over the full, uncropped screen on a starfield. Flattened, no alpha.

- `6.9-inch/` 1320×2868 — App Store Connect's required iPhone 6.9" slot
- `6.5-inch/` 1284×2778 — the 6.5" slot

Order: 01 Tonight, 02 Darkness Score, 03 Calendar, 04 Parks, 05 Night vision (Learn tab), 06 Journal.

Scores are real (live forecasts captured Oct 3, 2026, scored by the shipping engine). Journal entries are illustrative DEBUG seed data with no personal photos. To change captions, edit the `frames` list in the script and rerun. Recapture the raw frames with `Scripts/capture_store.py` first if the UI changes.
