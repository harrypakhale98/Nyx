# Step-free access for viewing spots

Retrieved 2026-10-05. Data: `Nyx/Resources/accessible-spots.json` (one record per spot in `parks.json`; bundled in the app since 2026-10-06).

## Method

- Covered all 85 viewing spots in 50 parks. The 13 parks with no viewing spots were skipped.
- Read each park's nps.gov Accessibility page (and its Physical / Mobility subpage where there is one), plus nps.gov "place" pages and park night-sky pages where they name the spot.
- A claim is recorded only when an official nps.gov page says it. Every non-unknown record carries a `sourceURL` and a verbatim `evidence` quote of 25 words or fewer. Quotes were checked against the live page text by script.
- `note` holds context that cuts against, or limits, the claim (steep slopes, uneven surfaces, what the evidence does not cover). Unknown records carry `checked`, the page that was read.
- Nothing was inferred from photos or from general "most overlooks are accessible" statements.

## Meaning of `stepFree`

- `yes`: an official source says the spot, its viewing area, or the facility it is named for (visitor center, amphitheater, overlook) is wheelchair accessible.
- `partial`: some accessible facility or route is documented at the spot (accessible parking, restroom, a paved section, a platform), but the whole viewing area is not confirmed step-free. Read the `note`.
- `no`: official source says the spot needs steps or a hike.
- `unknown`: no spot-specific official statement found.

## Counts (85 spots)

| stepFree | spots |
| --- | --- |
| yes | 35 |
| partial | 25 |
| no | 1 (Moro Rock, 350+ steps) |
| unknown | 24 |

## Caveats

- Conditions change. Check with the park before a trip, especially after storms, snow, or construction. Present this as official-source guidance, not a guarantee.
- Several source pages are old: Haleakalā (2020), Diablo Lake Overlook (2017), Grand Teton (mentions 2017 works), Cinnamon Bay Beach place page (2021). Dates are on the live pages.
- Night use differs from daytime access: gates, lighting, shuttles, and seasonal closures are not captured here.
- Some evidence covers a nearby facility rather than the exact named spot (for example, a visitor center for a parking lot). These are `partial` with a `note`.
- Chinde Point Picnic Area is matched to the NPS "Hózhó Point" listing (same site, renamed). The match is from the site description, not an explicit rename statement on nps.gov.
- NPS place pages list "Wheelchair Accessible" as an amenity tag with no detail. Those records (`yes`) rest on that tag alone and say so in the `note` or evidence.
