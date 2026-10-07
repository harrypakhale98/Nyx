# Nyx — App Store In-App Events (paste-ready)

Eleven events from November 2026 to August 2027. Copy follows the Nyx voice: calm, precise, honest about uncertainty, no exclamation marks, no marketing adjectives.

## Apple's limits (verified 2026-10-05)

Sources: App Store Connect Help, [Offer in-app events](https://developer.apple.com/help/app-store-connect/offer-in-app-events/offer-in-app-events), [In-app event badges](https://developer.apple.com/help/app-store-connect/reference/in-app-events/in-app-event-badges), [In-app event media and audio specifications](https://developer.apple.com/help/app-store-connect/reference/in-app-event-media-and-audio-specifications). The media numbers come from a search summary of that last page, so confirm them in the upload form.

| Field | Limit |
|---|---|
| Reference name (internal) | 64 characters |
| Event name | 30 characters |
| Short description (event card) | 50 characters |
| Long description (details page) | 120 characters |
| Event length | 15 minutes to 31 days |
| Publish date | at most 14 days before the start date |
| Regional start dates, if customized | within 48 hours of each other |
| Live at once / approved queue | 10 published, 15 approved per app |
| Badges | Live Event, Premiere, Challenge, Competition, New Season, Major Update, Special Event |
| Event card media | 16:9, at least 1920×1080; JPG/JPEG/PNG, or video (.mov/.m4v/.mp4, 30 or 60 fps) |
| Event details media | 9:16, at least 1080×1920; same formats |
| Video length / size | up to 30 s, loops; 500 MB maximum |
| Also asked | deep link (universal or custom URL), event purpose, priority (High or Normal), requires purchase (answer No), primary language, countries and regions |

Every event must be approved by App Review before it shows. Only the name and short description feed App Store search; the long description is for people on the details page.

Event purpose options as I remember them (confirm the wording in the form): Appropriate for all users, Attract new users, Keep active users informed, Bring back lapsed users.

**Badge choice.** Only "Special Event" fits: a limited-time event that no other badge captures. "Live Event" is for real-time shared activities, "Challenge" and "Competition" imply a goal or ranking, which Nyx does not have. Use **Special Event** throughout.

**Timing rule of thumb.** Submit each event for review at least 7 days before its publish date (Apple does not publish a review time for events; this margin is mine, unverified). Publish as early as Apple allows (14 days before start) so the card shows in search and on the product page for two weeks.

**Times.** All start and end times below are UTC. If the form asks in your local time zone, convert. Events run from late morning in the US East to the pre-dawn hours of the last night in the US West, so the last night is covered everywhere in the lower 48.

**What the events can claim.** Moon illumination and set times are computed by Nyx's engine and are within about 15 minutes for set times. Meteor rates are the International Meteor Organization's nominal ZHR for a perfect sky; the copy never promises a count. "Darkest" always means the Darkness Score on the night, not a guarantee of clear sky.

---

## Deep links

The app's URL scheme is `nyx` (`CFBundleURLSchemes`). Routes handled today (`RootView.onOpenURL`): `nyx://tonight`, `nyx://park/<id>`, `nyx://field/<id>`. Park ids are NPS-style four-letter codes in `parks.json` (`jotr`, `deva`, `bibe`, `grba`, `arch`).

Routes suggested for 1.1 (not built; the integrator can add them with a few lines in `onOpenURL`, and each degrades to opening Tonight if the route is unknown):

| Route | Opens | Used by |
|---|---|---|
| `nyx://whatsup?date=2026-12-14` | Tonight, scrolled to the shower line, "now" set to that date's evening (like `-nyx-date`) for the starting park | Geminids, Quadrantids, Eta Aquariids, Perseids |
| `nyx://calendar/<id>?month=2026-12` | The Calendar tab on that park and month, new moon window visible | New moon weekends |
| `nyx://planner?from=2026-11-06&to=2026-11-09` | The trip planner with those dates filled | New moon weekends (optional) |
| `nyx://park/<id>` (exists) | Park detail for tonight | Park-specific variants |

Where a route is missing in build 8, use `nyx://tonight`, which every build supports. Test a custom-scheme link from the event page on a device with Nyx installed and with it removed (the event should send people to the App Store page); Apple's guidance prefers a universal link, which would need a hosted `apple-app-site-association` file on a domain you control (GitHub Pages cannot serve one at the root of a project site). **Owner decision:** custom scheme now, universal link later.

---

## Event 1 — Geminids under a thin Moon

- Reference name: `Geminids 2026 (thin Moon)`
- Event name: `Geminids under a thin Moon` [26/30]
- Short description: `Find the darkest park skies for the peak nights` [47/50]
- Long description: `A crescent Moon sets by about 10 PM on Dec 13 to 14. See each park's moonset, cloud forecast and score for the Geminids.` [120/120]
- Badge: Special Event
- Purpose: Attract new users. Priority: High. Requires purchase: No
- Start (UTC): `2026-12-12 12:00` (7 AM EST, Sat Dec 12)
- End (UTC): `2026-12-15 18:00` (1 PM EST, Tue Dec 15)
- Publish (earliest allowed): `2026-11-28 12:00` UTC. Submit for review by Nov 20.
- Deep link: `nyx://whatsup?date=2026-12-14` (to build) or `nyx://tonight`
- Territories: United States. Language: English (add Spanish when the localization ships).

**Facts behind the copy.** IMO 2026: Geminids, ZHR about 150, a broad maximum around 14h UT on Dec 14, which is 9 AM EST and daylight in the Americas. The best US hours are therefore the nights of Dec 13 to 14 and Dec 14 to 15. Moon by a low-precision model: about 20% lit on the evening of Dec 13 and 28% on Dec 14, waxing crescent, setting in the evening (verify each park with `-nyx-screen whatsup -nyx-date 2026-12-13`). The radiant is high by midnight. Roadmap figure: about 23% at the peak.

**Event card (16:9).** A real Nyx render of the Geminid peak: park detail with the "What's up tonight" card (`-nyx-screen whatsup -nyx-date 2026-12-13`), set beside the real sky with the radiant rays. Overlay text, serif, at most six words: "Geminids. Thin Moon. Dec 13 to 14." No stock photos and no NPS logos.
**Details page (9:16).** The Tonight screen under `-nyx-date 2026-12-13`, framed like `Store/Framed`. Optional 20 s loop (see `app-preview-script.md`, shots 3 and 4).

---

## Event 2 — Quadrantids at an 11% Moon

- Reference name: `Quadrantids 2027 (11% Moon)`
- Event name: `Quadrantids at an 11% Moon` [26/30]
- Short description: `Thin Moon, modest US rates: plan the hours` [42/50]
- Long description: `Peak is 10:25 PM Eastern on Jan 3, with the radiant still low. Europe sees more. See each park's dark hours and clouds.` [119/120]
- Badge: Special Event
- Purpose: Keep active users informed. Priority: Normal. Requires purchase: No
- Start (UTC): `2027-01-02 12:00` (7 AM EST, Sat Jan 2)
- End (UTC): `2027-01-05 12:00` (7 AM EST, Tue Jan 5)
- Publish (earliest allowed): `2026-12-19 12:00` UTC. Submit by Dec 11.
- Deep link: `nyx://whatsup?date=2027-01-04` (to build) or `nyx://tonight`

**Honest framing.** Peak 2027-01-04 03:25 UT (IMO 2027, read only from search excerpts; `Research/sky-events.md` marks it unverified, so check the IMO 2027 calendar before publishing). That is 10:25 PM EST and 7:25 PM PST on Jan 3. The peak is narrow, about four hours, and the radiant is low in the north-northeast in the evening, so US rates at the peak are modest and fall off before the radiant climbs after midnight. Europe and western Asia see the peak in their pre-dawn hours. The Moon is 10 to 12% lit, waning, and rises near 4 AM, so every US evening is moon-free. The copy says this directly and does not promise a rate.

**Owner decision.** The event is an honest "this is a poor night for the US, with a thin Moon" card. Running it fits the brand and gives January a card; skipping it avoids promoting an event that favors another continent. Recommended: run at Normal priority, with the copy above.

**Event card (16:9).** The Tonight screen with the shower line under `-nyx-date 2027-01-03`; caption "Quadrantids. Radiant low early."
**Details page (9:16).** Park detail What's up card.

---

## Events 3 to 9 — New moon weekend

Eight new moons from the brief. Seven are standalone weekend events. **May is folded into Event 10 (Eta Aquariids)** because the new moon on May 6 and the shower coincide; if you want a separate May card, use Fri May 7 to Sun May 9.

Each weekend is the Friday to Sunday with the thinnest Moon in the evening hours (about 8 PM US Central), computed with a low-precision lunar model that reproduces the new-moon instants you supplied. Illumination is approximate (about ±1 point); read the final numbers from Nyx before publishing.

| Month | New moon (UTC, as supplied) | Weekend (Fri to Sun) | Moon lit, Fri / Sat / Sun evening | Start (UTC) | End (UTC) | Earliest publish (UTC) |
|---|---|---|---|---|---|---|
| Nov 2026 | Mon Nov 9 07:02 | Nov 6 to 8 | 5% / 2% / 0% | 2026-11-06 12:00 | 2026-11-09 15:00 | 2026-10-23 12:00 |
| Dec 2026 | Wed Dec 9 00:52 | Dec 4 to 6 | 14% / 8% / 4% | 2026-12-04 12:00 | 2026-12-07 15:00 | 2026-11-20 12:00 |
| Jan 2027 | Thu Jan 7 20:24 | Jan 8 to 10 | 1% / 4% / 9% | 2027-01-08 12:00 | 2027-01-11 15:00 | 2026-12-25 12:00 |
| Feb 2027 | Sat Feb 6 15:56 | Feb 5 to 7 | 0% / 0% / 2% | 2027-02-05 12:00 | 2027-02-08 15:00 | 2027-01-22 12:00 |
| Mar 2027 | Mon Mar 8 09:29 | Mar 5 to 7 | 5% / 2% / 0% | 2027-03-05 12:00 | 2027-03-08 15:00 | 2027-02-19 12:00 |
| Apr 2027 | Tue Apr 6 23:51 | Apr 2 to 4 | 15% / 9% / 4% | 2027-04-02 12:00 | 2027-04-05 15:00 | 2027-03-19 12:00 |
| May 2027 | Thu May 6 10:58 | Folded into Event 10 | | | | |
| Jun 2027 | Fri Jun 4 19:40 | Jun 4 to 6 | 0% / 2% / 7% | 2027-06-04 12:00 | 2027-06-07 15:00 | 2027-05-21 12:00 |

December and April use the weekend before the new moon because the one after has a thicker Moon (Dec 11 to 13 runs 8 / 14 / 21%, and overlaps the Geminids). Waning crescents rise late, so evenings are moon-free; waxing crescents set early.

**Template (replace the month and the seasonal hook).**

- Reference name: `New moon weekend, <Month Year>`
- Event name: `New moon weekend: November` [26/30] (every month fits; the longest used, `New moon weekend: November` and `... February`, is 26)
- Short description: `Thin Moon. See which park skies are darkest.` [44/50]
- Long description: see the table below
- Badge: Special Event. Purpose: Attract new users (Nov, Jan, Mar, Jun), Keep active users informed (the rest). Priority: Normal. Requires purchase: No
- Deep link: `nyx://calendar/<id>?month=<yyyy-mm>` (to build; start with `jotr` for the lower 48) or `nyx://tonight`

**Long descriptions, one per month** (each fits 120 characters and is true for the lower 48 on those dates; Alaska is noted where it differs):

| Month | Long description | Count |
|---|---|---|
| Nov | `The Moon is 5% lit or less all weekend. Compare the 63 parks by score, clouds and moonset for the darkest nights.` | [113/120] |
| Dec | `A thin waning Moon rises near dawn. Compare the 63 parks by score, clouds and moonset for the darkest nights.` | [109/120] |
| Jan | `Long winter nights, a thin Moon that sets early. Compare 63 parks for the darkest nights.` | [89/120] |
| Feb | `The Moon is 2% lit or less all weekend. Compare the 63 parks by score, clouds and moonset for the darkest nights.` | [113/120] |
| Mar | `The Milky Way core returns before dawn. Compare the 63 parks by score, clouds and moonset for the darkest nights.` | [113/120] |
| Apr | `The core rises after midnight; the Moon is thin. Compare 63 parks for the darkest nights.` | [89/120] |
| Jun | `Short nights, little Moon. Alaska has no true dark. Compare 63 parks for the darkest nights.` | [92/120] |

The "core returns before dawn" (March) and "core rises after midnight" (April) lines are seasonal guidance at mid-northern latitudes; confirm with Nyx's timed core for a park such as Joshua Tree on those dates before publishing. Mar 5 to 7 falls under `-nyx-date 2027-03-06`.

**Event card (16:9).** The calendar month with the new-moon window ringed (the calendar night cells are the signature picture). Caption: "New moon weekend. <Month>."
**Details page (9:16).** Park detail with the gauge, or the time river with the Moon morphing.

---

## Event 10 — Eta Aquariids at new moon

- Reference name: `Eta Aquariids 2027 (new moon)`
- Event name: `Eta Aquariids at new moon` [25/30]
- Short description: `No Moon at the peak. Southern parks see more.` [45/50]
- Long description: `New Moon is May 6. The radiant rises close to dawn, so rates are higher in the south. Check each park's window.` [111/120]
- Badge: Special Event
- Purpose: Attract new users. Priority: High. Requires purchase: No
- Start (UTC): `2027-05-04 12:00` (8 AM EDT, Tue May 4)
- End (UTC): `2027-05-08 12:00` (8 AM EDT, Sat May 8)
- Publish (earliest allowed): `2027-04-20 12:00` UTC. Submit by Apr 12.
- Deep link: `nyx://whatsup?date=2027-05-06` (to build) or `nyx://tonight`

**Facts behind the copy.** New moon 2027-05-06 10:58 UTC, as supplied; the shower peaks about May 6 (IMO gives a date, not a time; ZHR 50 in the IMO working list, variable 40 to 85). The radiant (Aquarius) rises only a short while before dawn from the northern US, so rates there are well below the ZHR; Big Bend, Hawaii, the Florida and Caribbean parks and American Samoa see it higher and longer. A new moon means no Moon at all, which is the point. The copy promises no rate.

**Event card (16:9).** What's up card at Big Bend on `-nyx-date 2027-05-06 -nyx-park bibe`; caption "Eta Aquariids. No Moon."
**Details page (9:16).** The Tonight screen for the same date.

---

## Event 11 — Perseids, a late-setting Moon (August 2027)

- Reference name: `Perseids 2027 (bright Moon)`
- Event name: `Perseids and a bright Moon` [26/30]
- Short description: `A bright Moon sets late. Find the last dark hour.` [49/50]
- Long description: `The Moon is about 86% lit and sets in the small hours. Nyx shows each park's dark window before dawn.` [101/120]
- Badge: Special Event
- Purpose: Keep active users informed. Priority: Normal. Requires purchase: No
- Start (UTC): `2027-08-11 12:00` (8 AM EDT, Wed Aug 11)
- End (UTC): `2027-08-14 12:00` (8 AM EDT, Sat Aug 14)
- Publish (earliest allowed): `2027-07-28 12:00` UTC. Submit by Jul 20.
- Deep link: `nyx://whatsup?date=2027-08-13` (to build) or `nyx://tonight`

**Facts behind the copy.** Peak 2027-08-13 about 08 to 10h UT (IMO 2027 excerpt, unverified), which is 1 to 3 AM PDT on Aug 13. The Moon is about 85 to 87% lit and waxing gibbous. My estimate, from the Moon's position at that date, is that it sets around 2 to 3 AM local daylight time at mid-northern latitudes, so the western US has a moon-free window from then until astronomical twilight begins, roughly 1 to 2 hours, with the radiant high. The east has a similar window an hour earlier or later by longitude. **This is an estimate: the brief says the Moon sets before the best hours in the western US. Open Nyx at a western park with `-nyx-screen whatsup -nyx-date 2027-08-13 -nyx-park jotr` and read the actual moonset and dark window before publishing, and edit "small hours" to the actual time if you want to name one.** The roadmap's honest line stands: this is a washed-out year, and Nyx says so.

**Event card (16:9).** What's up card on the Perseid night, with the Moon's setting time and the dark window; caption "Perseids. Moon sets late."
**Details page (9:16).** The sky arc showing the Moon's path ending before dawn.

---

## Media production notes (all events)

- Use real renders from the DEBUG scenarios in `README.md` ("Screenshot scenarios"), as the store screenshots do. The scenarios inject a date only; scores stay computed, never mocked.
- Event card is landscape and the details page is portrait. The app is portrait-only, so compose the card as a wide canvas: the real screen at the left or right, a short serif headline, a starfield, no marketing adjectives. Use `Scripts/make_store_frames.swift` as the starting point.
- No NPS, NASA or DarkSky logos, no photographs the owner does not hold, no personal journal content, no fabricated scores.
- Video is optional. Reuse the 6 to 10 s segments from `app-preview-script.md`; the event video loops and is capped at 30 s.
- Alt text and captions: App Store Connect has no alt-text field for event media, so keep the text in the long description complete without the picture.

## Checklist

1. 1.1 (8) approved. It is Nyx's first public release, so every event, November's included, rides on it; an event can be submitted only once a build with the app is approved.
2. Add the `whatsup`, `calendar` and `planner` routes, or use `nyx://tonight`.
3. Check each event's numbers in Nyx with the `-nyx-date` flag for the starting park and one western and one eastern park.
4. Create the event, upload media, submit for review at least 7 days before publish.
5. Attach the Geminids and Eta Aquariids events to a New Content featuring nomination (see `featuring-nominations.md`), at least 3 weeks before the event start.
6. Never leave more than 10 events published. The schedule above has at most two at once.
