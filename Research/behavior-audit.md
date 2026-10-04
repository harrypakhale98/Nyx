# Behaviour audit: does Nyx do what a person expects?

*Nyx build 3 · October 3, 2026 · four independent code reviews (defaults and memory, end-to-end journeys, consistency across surfaces, real-world edge cases), each finding re-checked in the code*

Triggered by one question: when someone chooses "Near me", why does Nyx forget it? It turned out to be one of a family. Below, every confirmed issue, deduplicated and ranked. **Bold file references** were re-verified by hand.

## Summary

- **8 issues to fix before release.** They touch safety (closures), honesty (scores that rise when data is lost), or launch survival (a shared API key that 20 people can exhaust in an hour).
- **12 issues where Nyx behaves in a way a person wouldn't expect.** None is dangerous; together they make the app feel forgetful and inconsistent.
- **4 missing capabilities.** The largest: Nyx can't answer "which park is darkest on *that* weekend?", which is half of its own core question.

## A. Fix before release

### A1. Every copy of the app shares one NPS key with a 1,000 requests/hour limit
**Where:** `Config/Secrets.xcconfig` → Info.plist; `Nyx/Services/DataServices.swift` (`ParkStore.enrichment`: alerts + events pages + parks per park); `Nyx/App/PlanModel.swift` (`refresh` fetches park updates for every park in the radius).
**What happens:** NPS documents a default of 1,000 requests per hour per key. Each park costs at least 3 requests; Tonight at 1,000 mi refreshes 15–20 parks, plus saved parks on every launch. Roughly 20 active users in an hour exhaust the key. After that every request fails (HTTP 429), and Nyx shows old closures or "Access not checked" for everyone.
**Fix:** The NPS API accepts many park codes in one request (verified: one call returned alerts for Acadia, Joshua Tree, Yellowstone and Death Valley together). Fetch **alerts for all 63 parks in one call** every six hours and share them across screens; fetch events only when a park's detail opens; drop the `parks` call (descriptions are already bundled); back off for an hour after a 429. *Owner step:* ask NPS for a higher limit before launch.

### A2. Tonight shows old closures, forecasts and location as if current
**Where:** **`TonightView.swift:56`** (refresh keyed only on park, radius and location, so it never re-runs when the app returns); `RootView.swift` (returning refreshes saved parks only); `PlanModel.alertSummary` (no date); location requested once.
**What happens:** Open Tonight on Tuesday, background the app, travel, reopen Friday: Tuesday's position, "No alerts in the last park update" from Tuesday (a closure may have been posted Wednesday), and "forecast included" with no age. This is the outcome the spec calls the worst the app can cause.
**Fix:** Refresh Tonight whenever the app becomes active; re-fetch location if it's in use; say "as of {time}" once data is over six hours old and "not checked recently" after a day.

### A3. Closures show in the app but not in the widget, reminders or Siri
**Where:** **`SharedSettings.swift` (`SavedSkySnapshot` has parks and forecasts only)**; `NyxWidgetsBundle.swift` (widget picks the best saved park, closed or not); `NotificationScheduler.plans` (no closure check); `NyxIntents.swift` (Siri never reads cached alerts). The calendar peek, score breakdown and share card also omit closures.
**What happens:** The Parks row for a park shows a road-closed warning while the widget says "91 Pristine" and a "promising night" reminder fires.
**Fix:** One shared closure helper over cached alerts; add closure titles to the widget snapshot and show them; skip or flag reminders for closed parks; Siri mentions a cached closure.

### A4. Losing signal in the park makes the score go up
**Where:** **`DataServices.swift:50`** (`Forecast.mean` returns nil after 36 hours) with the no-forecast renormalisation in `ScoreEngine.swift`.
**What happens:** Fetch Friday morning, arrive offline Saturday night: the cached 90% cloud is discarded, the cloud term is dropped and the rest rescaled, so a night that scored ~55 now shows an amber ~92 "Estimate".
**Fix:** Keep the last forecast past 36 hours, labelled with its age ("clouds as of Fri 8 AM"), rather than dropping it. A score must never rise because data aged out.

### A5. Tapping a reminder opens the wrong night, and pending reminders keep old numbers
**Where:** **`NotificationScheduler.swift:28` (only `parkID` in `userInfo`)**; `RootView` opens the park with no date; pending reminders are deliberately left untouched.
**What happens:** Thursday 18:00 "Fri: 94/100, Pristine" → tap → Thursday's night, perhaps 61 Fair. A reminder scheduled at 94 still says 94 after the forecast moves to 91.
**Fix:** Carry the night in the notification and open that night. Re-add a pending reminder under the same ID and fire time when its text changes (fire time unchanged, so nothing is pushed back).

### A6. Reminders fire in the middle of the user's night when the park is in another time zone
**Where:** `NotificationScheduler.swift` (18:00 in the park's zone, trigger pinned to that zone).
**What happens:** A New Yorker saving Haleakalā gets a reminder at midnight; American Samoa at 1 AM.
**Fix:** Fire at 18:00 the day before in the phone's own zone, still before darkness begins at the park.

### A7. Location is forgotten, never refreshed, and everyone starts at Joshua Tree
**Where:** **`PlanModel.swift` (`homeID` defaults to `"jotr"`; `LocationService` keeps coordinates in memory and calls `requestLocation()` once)**; onboarding never asks where you are.
**What happens:** A Maine user's first answer is "Joshua Tree, Death Valley…" 2,500 miles away. "Near me" works once and is gone next launch. A New Yorker at the default 200 mi sees an empty "A little farther from here".
**Fix:** Remember "use my location" and get a fresh fix whenever the app opens (While Using; coordinates never stored). Ask "Near me or choose a park" at the end of onboarding. Until chosen, pick a starting park from the phone's time zone rather than Joshua Tree. When nothing is in range, show the nearest parks labelled "beyond 200 mi".

### A8. "Best nights" favour estimates over nights that have a forecast
**Where:** **`TimeRiver.swift:28-29`** (amber glow on the three highest scores) and calendar dot size, fed by the no-forecast ×1/0.75 rescale.
**What happens:** At new moon, a night beyond the forecast scores ~93 "Estimate" while a forecast night with 20% cloud scores ~89, so the glow lands on nights with *less* information.
**Fix:** Choose peaks among forecast nights first (or compare on moon and darkness only), and draw the two groups distinctly.

## B. Behaves unexpectedly

| # | Issue | Where | Fix |
|---|---|---|---|
| B1 | Tapping a calendar night opens only the score breakdown, with no way to open, save or remind; the park menu is an unsearchable list of 63 that ignores saved parks | **`CalendarView.swift:137`** | Tap opens the night's detail; keep long-press peek; searchable picker with saved parks first |
| B2 | Calendar's park and the Parks filters reset on every launch, while the Parks sort is remembered | **`CalendarView.swift:78`**, **`ParkViews.swift:38-39`** | Remember them |
| B3 | Calendar and Journal default to Joshua Tree even when Tonight is centred on your location | `CalendarView`, `JournalEditorModel` | One shared "focus park": last explicit pick → Tonight's top park → first saved park |
| B4 | Journal: an entry made at 1 AM is filed under the next day; switching the park can shift the date by a day; Bortle always starts at 3; no "Record this night" from a park; entries never show that night's score or moon | **`JournalViews.swift:75-77`**, `:124` | Default to the night in progress, keep the chosen day across zones, add "Record this night", show the night on the entry |
| B5 | The same no-forecast night reads "Estimate" in some places and "Good" in others; VoiceOver always speaks the band | Parks row, river, peek vs gauge, breakdown, Siri | One shared label for screen and VoiceOver |
| B6 | Siri always asks which park; it prefers the widget's (possibly older) forecast over the app's newer one | **`NyxIntents.swift:19,26`** | Optional park defaulting to the best saved park; use the newer forecast |
| B7 | Parks rows never fetched for alerts look clear; "No alerts" summaries carry no date | `ParkViews.swift`, `PlanModel.alertSummary` | "Access not checked" on unchecked rows; dates on summaries (A1 makes most rows checked) |
| B8 | A park detail left open past sunrise keeps showing the night that just ended; Tonight's header moon and stars belong to the starting park, not the park shown | `ParkDetailView`, `TonightView.swift:26,51` | Drop a passed selection; use the hero park |
| B9 | After restoring to a new iPhone, reminders silently stop and the next three nights count as already sent | `RootView`, `ReminderLedger` | Sync permission whenever the app opens; clear the ledger when permission is undetermined |
| B10 | Widget and reminders wait for the network; on one bar of signal that can be minutes, or never if the app is closed first | `RootView.updateSaved` | Write the widget and schedule from cache first, then again after refresh; fetch in parallel |
| B11 | Wording: nights 15–16 days out say "forecast unavailable" (sounds like an error); "No true darkness tonight" shows for any scrubbed night; the sky arc's "Now" marker freezes while open | `ParkViews.swift:115-116`, `SkyArc` | Compare with the forecast's last hour; say "on this night"; refresh the arc each minute |
| B12 | Small: metric users see 161 / 322 / 805 / 1,609 km; shared cards are image-only (no text, red in night vision); the moon's "% illuminated" and its VoiceOver figure can differ by a few percent | `TonightView`, `ShareCard`, moon panel | Round km options; add share text and always share the normal palette; one illumination source |

## C. Missing capabilities

1. **Plan a date, not just tonight.** "Which park within 500 miles is darkest on the weekend of the 24th?" needs opening each park's calendar in turn. Add Tonight / This weekend / Pick dates to Tonight and the Parks sort; rank by each park's best night in the range. This completes the app's own core question.
2. **Reminders people can trust and see.** A fixed ≥90 threshold means eight parks (Gateway Arch, Cuyahoga, Indiana Dunes, Biscayne, Hot Springs, Congaree, Mammoth Cave, Saguaro) can essentially never remind. Reminders are off by default, buried in Settings, and nothing lists what's scheduled. Offer reminders when a park is first saved, remind about each saved park's best Excellent-or-better night, list upcoming reminders, and refresh in the background (`BGAppRefreshTask`; Open-Meteo is an allowed host).
3. **On-site mode.** At 11 PM in the park, show what's left of tonight: true darkness ends in 3 h 10 min; the moon rises at 2:40.
4. **A real first run.** Onboarding ends by asking where you'll look from (see A7).

## What already works

Park-local "tonight" that turns over at sunrise; honest "Estimate" labelling; a failed NPS request never wipes known closures; partial forecasts never count as clear; DST-safe day arithmetic; 24-hour time follows the device; Low Power Mode pauses animation; Reduce Transparency and night vision get solid surfaces; reminder de-duplication and the 64-request limit; the journal migration (`thumbnail` is optional).

## Proposed order

| Build | Contents | Effort |
|---|---|---|
| **4** | A1–A8 (closures, staleness, honesty, reminders, location) · B1–B3, B5–B7, B9 | about a day, including both full test suites |
| **5** | C1 date planning · C2 reminders · B4 journal · B8, B10–B12 | about a day |
| later | C3 on-site mode, C4 is folded into A7 | — |

## Sources

- NPS, [API developer guides: rate limits](https://www.nps.gov/subjects/developer/guides.htm) (1,000 requests per hour per key by default)
