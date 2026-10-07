# Nyx promo video

Social video (37.5 s): real app footage from the iOS 27 simulator, an original synthesized score, captions in the app's type.

1. Record clips (DEBUG build installed, status bar overridden), from `/tmp/nyx-promo` (clips land in `clips/` there; set `NYX_CLIPS` to change it): `rec.sh tonight 12 0 -nyx-screen tonight -nyx-state live`, likewise `river` (`-nyx-screen detail -nyx-state live -nyx-demo-river`), `field` (`-nyx-field-minutes 60`), `compass` (`-nyx-date 2027-07-03 -nyx-field-minutes 225`), `journal` (`-nyx-state populated`); `open` (tap Death Valley on Tonight) and `calendar` (tap next month) are recorded by hand with a tap during `simctl io recordVideo`.
2. `swift music.swift nyx-score.m4a` — the score, synthesized (no samples, no licensed audio).
3. Export `icon.png` with `ictool` (see "App icon" in the top-level `README.md`), then `swift promo.swift 9x16` and `swift promo.swift 4x5`.

Outputs in `Store/Social/` (videos are git-ignored; covers are committed).
