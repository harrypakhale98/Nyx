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

Revised 2026-10-07 (ST-4, DX-19). The order follows the product page's hero order: the real sky in colour, the river mid-scrub with the Moon changing shape, the Moon at size, field mode, the calendar, then what a city's light takes (added 2026-10-09: the park's sky against the same sky at a city's class, the Social Impact story in one gesture). The "models disagree" shot is dropped (hard to read with the sound off), field mode gets four full seconds, and the video ends on the night, not on privacy. Privacy belongs in the description and the label.

| # | Time | What happens | Caption (≤6 words) | Launch arguments |
|---|---|---|---|---|
| 1 | 0.0 to 4.0 s | Cold open on the real sky in colour over the park, then Tonight's first line: the darkest park and its score counting up. | `The darkest park. The darkest night.` (6) | `-nyx-screen sky -nyx-state live` cut to a plain Debug launch with no `-nyx-screen`, recorded after one warm launch (onboarding done, forecasts cached). The `tonight` route loads its forecasts after the first frame, so its dial starts on one park and jumps to another (34 to 97) mid-count; a warm launch reads the caches first and counts once from 0 to the hero score. |
| 2 | 4.0 to 9.0 s | The thirty-night time river, scrubbed mid-way: the Moon above the selected night changes shape night by night, the best nights glow, the half-filled and hollow nights show where the forecast thins out. Perform the drag during the recording; haptics do not appear in video. Poster frame here, at about 7 s, with the Moon half lit. | `Scrub the month. Watch the Moon.` (6) | `-nyx-screen detail -nyx-state live` (scroll until the river fills the lower half) |
| 3 | 9.0 to 13.0 s | The Moon at size: the shader Moon filling most of the width, lit at that night's phase, its terminator slowly crossing the craters as the night steps on. | `The Moon, as the park sees it.` (6) | `-nyx-screen detail -nyx-state live -nyx-chapter moon -nyx-date 2026-10-18` (the park page scrolled to the Moonlight panel in The sky chapter, the panel centred under the chapter index; the route keeps scrolling until the page above it has loaded, so start recording about 3 s after launch. The date is a first-quarter night, so the terminator crosses the craters whatever night it is recorded; any quarter-Moon night works) |
| 4 | 13.0 to 17.0 s | Field mode: the screen turns red, the countdown to true darkness runs, the eye clock fills. | `Red light for dark-adapted eyes.` (5) | `-nyx-screen field -nyx-state adapting -nyx-field-minutes 14` |
| 5 | 17.0 to 21.0 s | The calendar: a month of nights as tiny skies, the best stretch ringed, the month sliding to the next. | `Choose the night worth the drive.` (6) | `-nyx-screen calendar -nyx-state live` (route name may change with the Plan tab; check `RootView`) |
| 6 | 21.0 to 25.0 s | What a city's light takes: Death Valley's The place chapter opens on the park's own drawn sky; about 1 s in, tap "City · Class 8" and the class animates on the shared spring as the stars thin to a city's handful; hold on the city sky with "An illustration" in view. | `What a city's light takes.` (5) | `-nyx-screen detail -nyx-park deva -nyx-chapter place` (without `-nyx-reduce-motion`, so the switch animates) |
| 7 | 25.0 to 28.0 s | End card: the Moon on black, then the name. | `Where. When. Then look up.` (5), then "Nyx" | Edited in post: the Moon from shot 3 over void black, the serif name beneath. No app UI on the card. |

**Total 28.0 s** (4 + 5 + 4 + 4 + 4 + 4 + 3), inside Apple's 15 to 30 s. If a caption is rejected, the pictures still carry the story.

### Caption style

- Font: New York (serif) in starlight `#F5F1E6`, 28 to 34 pt at 6.9-inch, bottom third, over a soft black gradient. Contrast against the gradient at least 7:1.
- Start 0.3 s after each shot cuts; remove 0.3 s before the next cut; no animation other than a fade.
- Words are the app's own: "score", "Moon", "forecast". No adjectives from marketing.

### Audio

- **No music, no voiceover** in the main cut. A very quiet stereo bed of the Moon-and-star ambience (or silence on an AAC track) keeps the file spec-correct.
- Optional: lay the app's own "Listen to tonight" sonification under shot 2 if it sounds good at low level; it shows the accessibility work. Audio never carries information that the picture does not, since autoplay is muted.
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
3. Review: no hands, no frame, no prices, no dates, no "new"; the status bar reads 9:41 with full battery; no personal journal content; the score numbers are the engine's own, from build 10, never an earlier capture.
4. Upload in App Store Connect under the 6.9-inch iPhone slot; choose the poster frame near 7 s; allow up to 24 hours for processing.
5. Reuse segments of the preview as the In-App Event videos (`in-app-events.md`, 30 s cap) and as the Webby, iF and Core77 case-study clip (`award-entries.md`).
