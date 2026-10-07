# Nyx — award entries (one set, for the first public release)

Rewritten 2026-10-07. Version 1.1 is Nyx's first public release, so the old "1.0-safe" variants are gone: there is one text per length, and it describes build 8. Every sentence below is something a juror can check in the app, on the website or in the repository. Nothing invents users, downloads, press or reviews.

**Before filing any entry:** (1) confirm each named feature is in the live build (same table as `metadata.md` § Confirm before pasting); (2) keep the accessibility wording at "designed for" / "carries" until the physical-device pass in `accessibility-nutrition-labels.md` is signed, then the stronger "works with" wording may be used; (3) re-read each form's field limits, which were not opened for this draft.

## Programs, deadlines and fees

| Program | Category | Deadline | Fee | Decision |
|---|---|---|---|---|
| **Webby Awards, 31st** | Apps, Software & Immersive → App Excellence → **Accessibility & Inclusion** | Early entry Fri Oct 30, 2026; final entry mid-December (an earlier edition's pattern; confirm) | $645 early, $715 final, per entry | **Enter**, once the app is live (Webby requires the work to be live and accessible at entry and through mid-2027). If the release is not live by Oct 30, enter at the final deadline; do not rush for the $70. Verified on webbyawards.com 2026-10-06. |
| **UX Design Awards, Spring 2027** | **Product** | Call for entries Sep 1 – **Nov 15, 2026** | **EUR 320** (excl. VAT); optional nomination package EUR 2,250 is not needed | **Enter by Nov 15.** Eligible products are "currently on the market or launching within one year of entry", so a pre-launch entry is allowed. Verified on ux-design-awards.com 2026-10-07; the entry materials and limits are in their "Participant Information" document, not read. |
| Red Dot: Brands & Communication Design 2027 | Digital → Interface & User Experience Design | 2026 pattern: early bird late Jan – mid Feb (EUR 250), regular to late Apr (EUR 330) | see left | **Later** (January 2027), and only if reviews and press exist to cite. 2027 dates unpublished. |
| iF Design Award 2027 | UI or UX | Last chance Nov 4, 2026 | EUR 500, about EUR 3,700 in total if it wins | **Skip this cycle** (AM-02 timeline): the cost is high before there is any evidence from real use. |
| Anthem, Core77 | Sustainability / Social Impact; Apps & Platforms | 2027 windows unpublished | — | **Later, only with measured impact.** Do not enter without it. |

Recommended spend this cycle: Webby Accessibility & Inclusion ($645 or $715) and UX Design Awards Product (EUR 320).

## Shared framing (the spine of every entry)

**Problem.** People drive hours into national parks to see the Milky Way, then arrive under a bright Moon, a cloud deck or a city's glow, or find the road closed. The question that decides the trip, which park and which night, has no single answer: weather apps show clouds, almanacs show the Moon, and nobody joins them for a park.

**Solution.** Nyx gives each of the 63 US national parks a nightly Darkness Score from 0 to 100. The Moon (40), clouds (25), sky glow (20) and the hours of true darkness (15) add up, and the weakest can cap the total, so a cloudy night never looks good. It says what it does not know: nights beyond a reliable forecast are drawn hollow or half-filled and use each park's usual clouds; three weather models are compared; estimates are named as estimates. It runs its astronomy on the device, works offline, collects no data, and is built for night-adapted eyes.

**Evidence that exists today (and may be stated):**
- App Privacy label: Data Not Collected. Three public data services, each switchable; no analytics or third-party code (`PRIVACY.md`, `Scripts/verify_release.py`).
- Apple's automated accessibility audit passes on every screen in both palettes in the simulator; contrast ratios are published (`Research/contrast.json`: red text on black 6.2:1). The physical-device pass is open and is said to be open (`AUDIT.md`).
- Astronomy checked against the U.S. Naval Observatory: Moon rise and set within 3.7 minutes at mid-latitude parks and within a minute at the Alaska, Hawaiʻi, American Samoa and Virgin Islands checks; Sun within a minute (`Research/accuracy.md`, `NyxTests/usno-polar-tropical.json`).
- A unit suite of 232 tests on iOS 26 and iOS 27 (count on 2026-10-07; update at filing).
- Free, with no purchase or subscription.

**After launch,** add only measured facts: App Store ratings, accessibility testers' feedback, parks or dark-sky groups that link to Nyx.

**Supporting links:** landing page `https://harrypakhale98.github.io/Nyx/`, case study `https://harrypakhale98.github.io/Nyx/case-study.html`, press kit `https://harrypakhale98.github.io/Nyx/press/`, App Store page (when live), the App Preview (`app-preview-script.md`).

---

## 50 words

```
Nyx is a free app for iPhone, iPad, Apple Watch and Apple Vision Pro that shows where and when the sky is darkest across the 63 US national parks. It turns Moon, clouds, sky glow and true darkness into one score, works offline, collects no data, and suits night-adapted eyes.
```

[50 words, 275 characters]

## 200 words (Webby, UX Design Awards, Red Dot project description)

```
People drive for hours into national parks to see the Milky Way, then arrive under a bright Moon or a cloud deck. Nyx answers the question that decides the trip: which park, and which night?

Each park and night gets a Darkness Score from 0 to 100, built from the Moon, cloud cover, estimated sky glow and the hours of true darkness. The parts add up, and the weakest can cap the total, so an overcast night never looks good. A line says which limit applies.

Nyx is honest about uncertainty. Nights beyond a reliable forecast are drawn hollow or half-filled and use each park's usual clouds. Three weather models are compared, and the range is drawn when they disagree. Closures sit beside the score.

The interface is built for the dark. A red mode with measured contrast, a field mode that dims the screen and counts down to true darkness, and a Moon drawn by a shader from NASA's map carry the identity; native navigation carries the rest. Custom charts carry VoiceOver summaries and audio graphs.

Nyx has no account, advertising or tracking. Its App Privacy label reads Data Not Collected. One developer built it, and it is free.
```

[200 words, 1,135 characters]

## Accessibility & Inclusion statement (Webby; about 120 words)

```
Nyx is designed for people who look at the sky with eyes adapted to the dark, and for people who use VoiceOver, larger text, sound and touch. Every custom control, from the score dial to the calendar nights, speaks a summary of its data, and the charts carry audio graphs. "Listen to tonight" plays the night as tones with a transcript, and haptics can follow the Moon's phase. Layouts reflow at the largest text sizes. A red mode keeps the whole app readable at night, with contrast measured rather than guessed. Viewing spots carry step-free notes quoted from each park's own accessibility pages. Apple's accessibility audit passes on every screen; testing with assistive-technology users on real devices is under way.
```

[120 words, 720 characters]

Last sentence: change "is under way" to what is true on the filing date (for example "was completed in November with three VoiceOver users"), never more.

## Red Dot form notes (for January)

- Six images, JPG or TIFF in CMYK, 1920×1641 px recommended, one full-screen screenshot per image on a void-black canvas, no hands or devices; convert to CMYK last and check the red palette.
- Project description 500 to 1,200 characters: use the 200-word text (check its character count above).
- Criteria: Idea, Form, Impact.

## Owner decisions

1. Webby Accessibility & Inclusion at $645 (only if live by Oct 30) or $715 (final deadline).
2. UX Design Awards, Product, EUR 320, by Nov 15.
3. Red Dot in January 2027 only with reviews or press to cite; Anthem and Core77 only with measured impact.
4. Whether a public GitHub repository is acceptable as supporting evidence (`AUDIT.md`, `DECISIONS.md`); if not, link the case study and export the rest as PDFs.

## Sources

- Webby: [eligibility and fees](https://webbyawards.com/eligibility-and-guidelines), [categories](https://www.webbyawards.com/about/categories/) (read 2026-10-06)
- UX Design Awards: [enter](https://ux-design-awards.com/enter) (read 2026-10-07)
- Red Dot: [dates and costs, 2026 edition](https://www.red-dot.org/bcd/termine-kosten), [Guide to Success (PDF)](https://www.red-dot.org/fileadmin/downloads/Downloadmaterial_BCD/Guide_to_Success_EN.pdf) (read 2026-10-06)
- iF: [iF Design Award 2027 listing](https://graphiccompetitions.com/multiple-disciplines/if-design-award-2027/) (secondary)
