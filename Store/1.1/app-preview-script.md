# Nyx — App Preview video: storyboard and specs

One 28-second preview for the iPhone 6.9-inch slot, staged from the DEBUG launch arguments in `README.md` ("Screenshot scenarios"). Autoplay is muted on the App Store, so the story is carried by the pictures and six-word captions.

## Apple's rules (verified 2026-10-06)

Sources: App Store Connect Help, [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications); [Apple's App Previews guidance](https://developer.apple.com/app-store/app-previews/). Both were read through a page fetch; two items are flagged below.

**Technical**

| Item | Requirement |
|---|---|
| Length | 15 to 30 seconds |
| Frame rate | 30 fps maximum |
| Resolution, iPhone 6.9-inch | 886 × 1920 px portrait (1920 × 886 landscape). The 6.5-inch and 6.1-inch slots take the same size. **Flag:** I read this value from a page summary. Also confirm in the upload form whether it accepts the device's native 1320 × 2868 recording; scaling 1320 × 2868 to 886 × 1920 changes the aspect ratio by under 0.3%, so a scale and tiny crop is invisible. |
| Video codec | H.264, progressive, High Profile Level 4.0 maximum; target 10 to 12 Mbps VBR |
| Containers | .mov, .m4v, .mp4; up to 500 MB |
| Audio | Stereo, AAC 256 kbps, 44.1 or 48 kHz, tracks enabled. **Flag:** the specification lists audio as part of the format. Include a stereo AAC track even if it is silent or near silent; do not rely on a video-only file being accepted. |
| Quantity | Up to 3 previews per device size and language |
| Poster frame | Defaults to 5 seconds in; you can choose another frame |
| Processing | Up to 24 hours after upload; submitted with the app version for review |
| Orientation | Portrait or landscape; plays back in its original orientation |

**Content (Apple's guidance)**

- Allowed: footage captured from the device; touch indicators; text overlays; app UI sounds; voiceover; one music track.
- Not allowed: device frames or bezels; hands or fingers on the screen; people filmed using the device; seasonal or timely references (such as "new for spring" or specific dates); specific prices; unlicensed content.
- Best practice: native UI resolution (do not zoom), legible text held long enough to read, plain dissolves and fades, a first preview that gives the overview.

**What this means for Nyx.** No captions saying "free", "new in 1.1", "December" or "Geminids": the preview must stay true for years and may not carry dates or prices. A date that appears inside the app UI is part of the footage, but prefer a date that reads as ordinary (July, for the Milky Way core) over a headline event. No hands, no frame. Zero third-party logos; no NPS marks.

## The footage

**Where to record.** Prefer a physical iPhone 17 or 18 Pro Max: connect it, open QuickTime Player, File → New Movie Recording, choose the iPhone as the camera, record the screen. The launch arguments are DEBUG-only, so run a Debug build from Xcode on the device and set the arguments in the scheme (Run → Arguments Passed On Launch). For the simulator: `xcrun simctl io <UDID> recordVideo --codec=h264 --force shot.mov` while the app runs. Apple's guidance says "footage captured directly from the device"; a real device is the safer reading.

**Before recording.** On the simulator, set the status bar as in `Scripts/capture_store.py`: `xcrun simctl status_bar <UDID> override --time 9:41 --batteryState charged --batteryLevel 100 --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4`, and clear it afterwards. On a device, use Control Center: no Focus, brightness at the preview level, Do Not Disturb on, battery above 80%. Remove `-nyx-reduce-motion` (the store script uses it for stills; the preview needs the motion). Scores stay computed from live engines; do not edit any value. Recapture if the forecast fails to load (`-nyx-state live` shows a real forecast).

**Cadence.** Record each shot separately, 6 to 10 seconds, then cut. Hold each caption at least 2.5 seconds. Dissolves of 0.3 s between shots. No flashes. End the video on the Moon and the name.

## Storyboard (28 s, 7 shots)

| # | Time | What happens | Caption (≤6 words) | Launch arguments |
|---|---|---|---|---|
| 1 | 0.0 to 3.5 s | Cold open on Tonight: the real sky, the top park, the dial counts up. | `Where is the sky darkest?` (5) | `-nyx-screen tonight -nyx-state live` |
| 2 | 3.5 to 8.0 s | Park detail: the score reveal, the four meters glide into place, the band word appears. Poster frame here, at about 7 s once the numeral has settled. | `One score. Four reasons.` (4) | `-nyx-screen detail -nyx-state live` |
| 3 | 8.0 to 13.0 s | The thirty-night time river: a finger-less scrub left to right (the screen recording shows no hand), the Moon morphing above the selected night, amber glow on the best nights, a hollow mark past the forecast. Perform the drag during the recording; haptics do not appear in video. | `Scrub the month. Watch the Moon.` (6) | `-nyx-screen detail -nyx-state live` (scroll just enough that the river fills the lower half) |
| 4 | 13.0 to 17.0 s | What's up tonight: the Milky Way core timed ("rises", "highest", "Moon-free from"), planets, and the sky arc with the core's path. Use a plain summer date. | `The Milky Way, timed.` (4) | `-nyx-screen whatsup -nyx-date 2027-07-17` (then scroll to the arc: `-nyx-screen skyarc -nyx-date 2027-07-17`) |
| 5 | 17.0 to 21.0 s | The honest forecast: three models disagree, the pale range bar on the river and the words "Models differ". | `Honest when models disagree.` (4) | `-nyx-screen detail -nyx-state disagree` |
| 6 | 21.0 to 25.0 s | Night vision: the whole app turns red. Cut to field mode: the countdown to true darkness and the eye clock. | `Made for night-adapted eyes.` (4) | `-nyx-screen field -nyx-state adapting -nyx-field-minutes 14` (add `-nyx-night-vision` for the red cut on the previous screen: `-nyx-screen detail -nyx-state live -nyx-night-vision`) |
| 7 | 25.0 to 28.0 s | The compass sky turns with the phone ("Where to look"), then fades to the Moon and the app name, "Nyx", above "Dark Sky Planner". | `No account. No tracking.` (4) | `-nyx-screen field-compass` (fixed pose facing the core) |

**Total 28.0 s.** Safe under the 30 s limit with a 2-second margin for trimming. If the review team rejects any caption, the story still reads from the pictures.

### Caption style

- Font: New York (serif) in starlight `#F5F1E6`, 28 to 34 pt at 6.9-inch, bottom third, over a soft black gradient. Contrast against the gradient at least 7:1.
- Start 0.3 s after each shot cuts; remove 0.3 s before the next cut; no animation other than a fade.
- Words are the app's own: "score", "Moon", "forecast". No adjectives from marketing.

### Audio

- **No music, no voiceover** in the main cut. A very quiet stereo bed of the Moon-and-star ambience (or silence on an AAC track) keeps the file spec-correct.
- Optional: lay the app's own "Listen to tonight" sonification under shot 3 if it sounds good at low level; it shows the accessibility work. Audio never carries information that the picture does not, since autoplay is muted.
- If the sound is added, keep integrated loudness around -23 LUFS.

## Export

Export 886 × 1920, 30 fps, H.264 High Level 4.0, about 11 Mbps VBR, AAC 256 kbps stereo at 48 kHz, .mp4 or .mov. A tool-agnostic recipe, untested here, with ffmpeg if you have it:

```
ffmpeg -i shot.mov -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -vf "scale=886:1920:force_original_aspect_ratio=increase,crop=886:1920,fps=30" \
  -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p -b:v 11M -maxrate 12M -bufsize 24M \
  -c:a aac -b:a 256k -ar 48000 -ac 2 -shortest -movflags +faststart nyx-preview.mp4
```

Final Cut, iMovie or Compressor with the same settings work as well. Check the length (15 to 30 s), the frame size and the file under 500 MB before uploading.

## Second and third previews (optional, up to three per language)

1. **Field mode (20 to 25 s):** `-nyx-screen live-activity` (Lock Screen and Dynamic Island), `-nyx-screen field -nyx-state adapted`, `-nyx-screen field-compass`, `-nyx-screen alarm-explainer`. Caption ideas: `A countdown for the dark.`, `Eyes adapt in thirty minutes.`, `Point the phone. Find the core.`
2. **Accessibility (20 to 25 s):** VoiceOver reading the gauge and the calendar, the audio graph playing, Larger Text at AX5 reflowing the calendar into rows. VoiceOver's speech shows in the system recording of the device; add captions that spell what is spoken. Caption ideas: `Hear a month of darkness.`, `Text scales to the largest size.`
3. **Apple Watch and Apple Vision Pro** each need their own preview on their own device slot, recorded on the real device or its simulator, if shipped in 1.1. Apple's guidance lists previews for iOS, iPadOS, macOS, tvOS and visionOS; confirm the watchOS requirement in App Store Connect.

## Checklist

1. Capture in a Debug build on device or simulator with the arguments above; keep source files in a shared folder, not the repo.
2. Edit to 28 s with the captions and the end card; export to the spec above.
3. Review: no hands, no frame, no prices, no dates, no "new"; the status bar reads 9:41 with full battery; no personal journal content; the score numbers are the engine's own.
4. Upload in App Store Connect under the 6.9-inch iPhone slot; choose the poster frame near 7 s; allow up to 24 hours for processing.
5. Reuse segments of the preview as the In-App Event videos (`in-app-events.md`, 30 s cap) and as the Webby, iF and Core77 case-study clip (`award-entries.md`).
