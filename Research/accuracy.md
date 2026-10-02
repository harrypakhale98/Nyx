# Measured astronomy accuracy

2026-10-02. Independent USNO fixtures, representative NPS coordinates. Absolute error in minutes. NOAA solar equations; truncated Meeus lunar position. Actual terrain and atmosphere can cause larger deviations.

| Algorithm | Samples | Maximum error | Gate |
|---|---:|---:|---:|
| Solar rise/set/civil dusk | 27 | 0.47 min | 2 min |
| Lunar rise/set | 18 | 3.72 min | 15 min |

| Park | Date | Event | Error, min |
|---|---|---|---:|
| grca | 2026-01-15 | Sun Rise | 0.30 |
| grca | 2026-01-15 | Sun Set | 0.01 |
| grca | 2026-01-15 | Sun End Civil Twilight | 0.11 |
| grca | 2026-01-15 | Moon Rise | 3.27 |
| grca | 2026-01-15 | Moon Set | 3.67 |
| grca | 2026-03-20 | Sun Rise | 0.14 |
| grca | 2026-03-20 | Sun Set | 0.43 |
| grca | 2026-03-20 | Sun End Civil Twilight | 0.02 |
| grca | 2026-03-20 | Moon Rise | 3.02 |
| grca | 2026-03-20 | Moon Set | 2.38 |
| grca | 2026-07-15 | Sun Rise | 0.47 |
| grca | 2026-07-15 | Sun Set | 0.28 |
| grca | 2026-07-15 | Sun End Civil Twilight | 0.32 |
| grca | 2026-07-15 | Moon Rise | 2.34 |
| grca | 2026-07-15 | Moon Set | 3.41 |
| grba | 2026-01-15 | Sun Rise | 0.15 |
| grba | 2026-01-15 | Sun Set | 0.26 |
| grba | 2026-01-15 | Sun End Civil Twilight | 0.47 |
| grba | 2026-01-15 | Moon Rise | 3.72 |
| grba | 2026-01-15 | Moon Set | 3.50 |
| grba | 2026-03-20 | Sun Rise | 0.24 |
| grba | 2026-03-20 | Sun Set | 0.21 |
| grba | 2026-03-20 | Sun End Civil Twilight | 0.16 |
| grba | 2026-03-20 | Moon Rise | 3.08 |
| grba | 2026-03-20 | Moon Set | 3.31 |
| grba | 2026-07-15 | Sun Rise | 0.05 |
| grba | 2026-07-15 | Sun Set | 0.26 |
| grba | 2026-07-15 | Sun End Civil Twilight | 0.19 |
| grba | 2026-07-15 | Moon Rise | 3.18 |
| grba | 2026-07-15 | Moon Set | 3.02 |
| jotr | 2026-01-15 | Sun Rise | 0.35 |
| jotr | 2026-01-15 | Sun Set | 0.32 |
| jotr | 2026-01-15 | Sun End Civil Twilight | 0.22 |
| jotr | 2026-01-15 | Moon Rise | 3.19 |
| jotr | 2026-01-15 | Moon Set | 2.68 |
| jotr | 2026-03-20 | Sun Rise | 0.18 |
| jotr | 2026-03-20 | Sun Set | 0.17 |
| jotr | 2026-03-20 | Sun End Civil Twilight | 0.11 |
| jotr | 2026-03-20 | Moon Rise | 2.65 |
| jotr | 2026-03-20 | Moon Set | 3.14 |
| jotr | 2026-07-15 | Sun Rise | 0.42 |
| jotr | 2026-07-15 | Sun Set | 0.05 |
| jotr | 2026-07-15 | Sun End Civil Twilight | 0.34 |
| jotr | 2026-07-15 | Moon Rise | 2.70 |
| jotr | 2026-07-15 | Moon Set | 2.91 |

Sources: [USNO API](https://aa.usno.navy.mil/data/api.html), [NOAA equations](https://gml.noaa.gov/grad/solcalc/calcdetails.html). Raw fixtures are in usno-reference.json. These fixtures independently validate sunrise, sunset, and civil dusk. Astronomical twilight uses the same coordinates at −18° but has no independent published fixture here; do not claim it is measured to two minutes.

