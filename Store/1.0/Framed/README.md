> **Historical:** the Nyx 1.0 set, kept for reference (moved here 2026-10-06). The current 1.1 sets are in `Store/Screenshots` and `Store/Framed`.

# Captioned App Store screenshots

Six frames built from the raw captures in `Store/Screenshots` by `swift Scripts/make_store_frames.swift` (run from the repo root). Each puts a short serif headline over the full, uncropped screen on a starfield. Flattened, no alpha.

- `6.9-inch/` 1320×2868 — App Store Connect's required iPhone 6.9" slot
- `6.5-inch/` 1284×2778 — the 6.5" slot

Order: 01 Tonight, 02 Darkness Score, 03 Calendar, 04 Parks, 05 Night vision (Learn tab), 06 Journal.

Scores are real (live forecasts captured Oct 3, 2026, scored by the shipping engine). Journal entries are illustrative DEBUG seed data with no personal photos. To change captions, edit the `frames` list in the script and rerun. Recapture the raw frames with `Scripts/capture_store.py` first if the UI changes.

iPad (2026-10-06): no captioned iPad frames yet. The six raw 13-inch iPad captures in `Store/Screenshots/iPad/` (2752×2064 landscape, no alpha, real `live` data) can be uploaded as they are to App Store Connect's iPad 13-inch slot, which is required now that Nyx runs on iPad. To caption them, add an iPad size to `Scripts/make_store_frames.swift` (landscape canvas 2752×2064) rather than scaling the iPhone frames.
