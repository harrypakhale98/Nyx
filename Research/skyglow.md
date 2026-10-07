# Sky glow from NASA Black Marble (VNP46A4)

Offline dataset behind `Nyx/Resources/skyglow.json`. Built by `Scripts/build_skyglow.py`. It adds, for each of the 63 parks and 85 viewing spots, a relative artificial-glow index, an estimated Bortle class, a 36-bin "light dome" azimuth profile with named dominant sources, and a 2013 to 2025 trend.

## Sources and licence

- NASA Black Marble VNP46A4, VIIRS yearly nighttime lights, 15 arc-second, collection 5200 (version 2), HDF5 tiles. Product page: https://ladsweb.modaps.eosdis.nasa.gov/missions-and-measurements/products/VNP46A4/ ; DOI 10.5067/VIIRS/VNP46A4.002 ; user guide: Black-Marble_v2.0_UG_2024.pdf (LAADS document archive).
- Tile directory listings: `https://ladsweb.modaps.eosdis.nasa.gov/archive/allData/5200/VNP46A4/<year>/001.json`. Files were fetched from the Earthdata Cloud HTTPS endpoint (`data.laadsdaac.earthdatacloud.nasa.gov/prod-lads/VNP46A4/...`) with an Earthdata user token read at run time from `~/.earthdata_token`. The token is never stored in the repo or in any output.
- Method reference: Roman, M. O., et al. (2018). NASA's Black Marble nighttime lights product suite. Remote Sensing of Environment, 210, 113-143. https://doi.org/10.1016/j.rse.2018.03.017
- Licence: NASA Earth science data are in the public domain (NASA Earthdata data use policy: free and open, no restrictions on use or redistribution). The app ships only derived numbers. Nothing here is downloaded at run time; the app ships only the derived `skyglow.json` (48 KB).
- Walker's law: Walker, M. F. (1977), The effects of urban lighting on the brightness of the night sky, PASP 89, 405-409. The exponent 2.5 is the classic empirical value for sky glow versus distance.

Credit line for "About the data" (exact):

> Light-pollution estimates use NASA Black Marble nighttime lights (VNP46A4, Roman et al. 2018), public domain.

## Method

1. Years: 2013 (early) and 2025 (late). 2012 was skipped because VIIRS only began collecting in late January 2012, so its annual composite is partial. 2025 is the latest complete year (published March 2026).
2. Tiles: 40 tiles of 10 by 10 degrees per year (hXXvYY with h=(lon+180)/10, v=(90-lat)/10) cover every park and spot plus a 300 km window: contiguous US, Alaska, Hawaii (h02v06, h02v07), American Samoa (h00v10, h01v10) and the US Virgin Islands (h11v07). About 9.8 GB downloaded in total; each raw .h5 was reduced to ~2 km cells and deleted immediately.
3. Layer: `NearNadir_Composite_Snow_Free` (view zenith 0-20 degrees, so least angular bias; snow-free period so snow albedo does not inflate the signal). Fill (-999.9, quality 255) is masked. Quality flags (0 good, more than 3 observations; 1 poor, 3 or fewer; 2 gap-filled) are respected: where the near-nadir value is fill, or flagged poor while `AllAngle_Composite_Snow_Free` is good, the all-angle value is used. Remaining fill counts as zero light. High-latitude (Alaska) tiles show almost no fill pixels; that completeness relies on the product's gap-filling from historical data, so Alaskan values carry less certainty.
4. Aggregation: 4 by 4 pixel mean, giving cells of 1/60 degree (about 1.85 km).
5. Model (Walker's law): `G = sum_i L_i * A_i * d_i^-2.5` over cells with 1 km <= d <= 300 km (L in nW cm-2 sr-1, A in km2, d in km; d under 1 km is treated as 1 km). `glow = G / G_median_park`, so the median national-park centre is 1.0 and the value is unitless. The same contributions binned by bearing (36 bins of 10 degrees, bin 0 centred on north, clockwise, scaled to 0-255 relative to the site's brightest bin) are the profile.
6. Bortle: `bortle = 0.689 + 2.328 * log10(glow + 4.217)`, clipped to 1-9, least squares against the hand `bortleEstimate` of the 63 park centres. The additive constant (4.217) is a "natural floor" chosen by grid search over 10^-3 to 10^2; it is an interior optimum, not a grid edge.
7. Light domes: the profile is smoothed with a 3-bin (30 degree) window; up to three circular maxima are kept when their window holds at least 8% of the site's total (the maximum is suppressed within 30 degrees before the next). Bearing is the contribution-weighted circular mean; share is the window's fraction of total contribution. The strongest cell in the sector seeds a cluster (lit cells within 20 km); its radiance-weighted centroid is matched to the hand-written metro list in the script and named only if within 40 km, else `null`.
8. Trend: sum of L*A (nW cm-2 sr-1 km2) within 150 km of each park centre, 2013 versus 2025.

## Calibration (park centres)

Fit quality, honestly stated:

- R2 = 0.78, RMSE = 0.54 Bortle classes, bias about 0, maximum residual 1.23 (Kobuk Valley). Pearson r = 0.88, but Spearman rank correlation = 0.47.
- The weak rank correlation is expected: 30 of 63 hand estimates are all "2" (a conservative integer bucket), so the ordering among dark parks is decided by noise in the hand labels. The fit is driven by the roughly 12 brighter parks, where it is good.
- No park differs from its hand estimate by 2 or more classes. Five differ by 1 or more: Biscayne (5 hand, 4.0 computed), Cuyahoga Valley (6, 5.0), Kobuk Valley (2, 3.2), Mammoth Cave (4, 2.9), Saguaro (4, 5.1).
- Dark end: the floor term means everything with glow below about 1 maps to 2.1-2.4. VIIRS cannot tell Bortle 1 from 2 and the hand labels do not either. Treat `glow` as the ranking quantity and `bortle` as a Bortle-2-or-brighter estimate; do not display Bortle 1.
- Cross-check: all 17 Dark-Sky-designated parks in `parks.json` compute to Bortle 2.9 or lower (Arches 2.2, Big Bend 2.1, Black Canyon 2.3, Bryce 2.2, Canyonlands 2.1, Capitol Reef 2.1, Death Valley 2.3, Glacier 2.2, Grand Canyon 2.6, Great Basin 2.1, Great Sand Dunes 2.2, Joshua Tree 2.6, Mammoth Cave 2.9, Mesa Verde 2.3, Petrified Forest 2.5, Voyageurs 2.1, Zion 2.3), matching the expectation of Bortle 1-3. NPS Night Skies Program per-park measurements could not be retrieved for this report, so the cross-check against measured data is limited to the designation list.

| Park | id | Hand Bortle | Computed | Residual | Glow (median park = 1) | Dark-Sky designated |
|---|---|---|---|---|---|---|
| National Park of American Samoa | npsa | 3 | 2.1 | -0.9 | 0.00476 |  |
| Yellowstone | yell | 2 | 2.2 | +0.2 | 0.071 |  |
| Canyonlands | cany | 2 | 2.2 | +0.2 | 0.083 | yes |
| Great Basin | grba | 2 | 2.2 | +0.2 | 0.0883 | yes |
| Big Bend | bibe | 2 | 2.2 | +0.2 | 0.0905 | yes |
| Voyageurs | voya | 2 | 2.2 | +0.2 | 0.107 | yes |
| Capitol Reef | care | 2 | 2.2 | +0.2 | 0.121 | yes |
| Redwood National and State Parks | redw | 3 | 2.2 | -0.8 | 0.129 |  |
| Isle Royale | isro | 2 | 2.2 | +0.2 | 0.131 |  |
| Grand Teton | grte | 2 | 2.2 | +0.2 | 0.137 |  |
| Dry Tortugas | drto | 2 | 2.2 | +0.2 | 0.14 |  |
| Crater Lake | crla | 2 | 2.2 | +0.2 | 0.177 |  |
| Badlands | badl | 2 | 2.2 | +0.2 | 0.192 | yes (July 2026) |
| Glacier | glac | 2 | 2.2 | +0.2 | 0.2 | yes |
| Bryce Canyon | brca | 2 | 2.2 | +0.2 | 0.206 | yes |
| Haleakalā | hale | 2 | 2.2 | +0.2 | 0.277 |  |
| Lassen Volcanic | lavo | 2 | 2.2 | +0.2 | 0.311 |  |
| Great Sand Dunes | grsa | 2 | 2.2 | +0.2 | 0.338 | yes |
| Arches | arch | 3 | 2.2 | -0.8 | 0.343 | yes |
| Katmai | katm | 2 | 2.2 | +0.2 | 0.354 |  |
| Wind Cave | wica | 2 | 2.2 | +0.2 | 0.481 |  |
| Death Valley | deva | 2 | 2.3 | +0.3 | 0.553 | yes |
| Kings Canyon | kica | 3 | 2.3 | -0.7 | 0.564 |  |
| Mesa Verde | meve | 3 | 2.3 | -0.7 | 0.642 | yes |
| Zion | zion | 3 | 2.3 | -0.7 | 0.715 | yes |
| Yosemite | yose | 3 | 2.3 | -0.7 | 0.723 |  |
| North Cascades | noca | 2 | 2.3 | +0.3 | 0.759 |  |
| Guadalupe Mountains | gumo | 2 | 2.3 | +0.3 | 0.781 |  |
| Black Canyon of the Gunnison | blca | 2 | 2.3 | +0.3 | 0.82 | yes |
| Sequoia | sequ | 3 | 2.4 | -0.6 | 0.941 |  |
| Theodore Roosevelt | thro | 2 | 2.4 | +0.4 | 0.985 |  |
| White Sands | whsa | 3 | 2.4 | -0.6 | 1 |  |
| Olympic | olym | 3 | 2.4 | -0.6 | 1.03 |  |
| Channel Islands | chis | 2 | 2.4 | +0.4 | 1.28 |  |
| Carlsbad Caverns | cave | 2 | 2.5 | +0.5 | 1.52 |  |
| Mount Rainier | mora | 3 | 2.5 | -0.5 | 1.6 |  |
| Gates of the Arctic | gaar | 2 | 2.5 | +0.5 | 1.77 |  |
| Rocky Mountain | romo | 2 | 2.5 | +0.5 | 1.78 |  |
| Petrified Forest | pefo | 2 | 2.5 | +0.5 | 1.89 | yes |
| Pinnacles | pinn | 3 | 2.5 | -0.5 | 2.09 |  |
| Grand Canyon | grca | 2 | 2.6 | +0.6 | 2.31 | yes |
| Denali | dena | 2 | 2.6 | +0.6 | 2.36 |  |
| Joshua Tree | jotr | 3 | 2.6 | -0.4 | 2.41 | yes |
| Hawaiʻi Volcanoes | havo | 3 | 2.7 | -0.3 | 2.87 |  |
| Glacier Bay | glba | 2 | 2.7 | +0.7 | 2.93 |  |
| Everglades | ever | 3 | 2.7 | -0.3 | 2.97 |  |
| Kenai Fjords | kefj | 2 | 2.7 | +0.7 | 3.1 |  |
| Shenandoah | shen | 3 | 2.8 | -0.2 | 3.45 |  |
| Lake Clark | lacl | 2 | 2.8 | +0.8 | 3.63 |  |
| New River Gorge | neri | 3 | 2.8 | -0.2 | 3.72 |  |
| Wrangell–St. Elias | wrst | 2 | 2.8 | +0.8 | 3.86 |  |
| Mammoth Cave | maca | 4 | 2.9 | -1.1 | 4.69 | yes |
| Great Smoky Mountains | grsm | 3 | 2.9 | -0.1 | 4.74 |  |
| Virgin Islands | viis | 3 | 2.9 | -0.1 | 4.81 |  |
| Acadia | acad | 3 | 2.9 | -0.1 | 5.09 |  |
| Congaree | cong | 4 | 3.2 | -0.8 | 7.54 |  |
| Kobuk Valley | kova | 2 | 3.2 | +1.2 | 8.18 |  |
| Biscayne | bisc | 5 | 4.0 | -1.0 | 21.3 |  |
| Cuyahoga Valley | cuva | 6 | 5.0 | -1.0 | 67 |  |
| Saguaro | sagu | 4 | 5.0 | +1.0 | 70.7 |  |
| Indiana Dunes | indu | 6 | 5.5 | -0.5 | 109 |  |
| Hot Springs | hosp | 5 | 5.6 | +0.6 | 123 |  |
| Gateway Arch | jeff | 8 | 8.1 | +0.1 | 1.5e+03 |  |

## Sanity checks

- Darkest in the lower 48 by glow: Yellowstone, Canyonlands, Great Basin, Big Bend, Voyageurs, Capitol Reef, Redwood, Isle Royale, Grand Teton, Dry Tortugas. Great Basin ranks 3rd and Big Bend 4th of 51 lower-48 parks. Death Valley ranks 19th (glow 0.55, computed Bortle 2.3): about 6 times Great Basin, almost entirely from the Las Vegas, Pahrump and Los Angeles-basin dome at 100-300 km. It is still in the darkest tier by Bortle (2.3), but the "among the darkest" expectation holds only at that tier level, not by strict rank.
- Brightest: Gateway Arch (glow 1500, Bortle 7.9), Hot Springs (123), Indiana Dunes (109), Saguaro (71, Tucson), Cuyahoga Valley (67), Biscayne (21). All four named expected-bright parks are in the top five.
- Death Valley domes: 102 degrees (east), 45% of total, Las Vegas; then 199 degrees Ridgecrest, 271 degrees Visalia. At the Harmony Borax Works spot the Las Vegas dome is at 104 degrees and Furnace Creek takes the south. The east bearing is slightly north of "east-southeast"; Las Vegas is geometrically almost due east of the park centre.
- Joshua Tree domes: 249 degrees (west-southwest), 42%, Indio / Coachella Valley, then 282 degrees (Yucca Valley area). At the west-side spots (Cap Rock, Hidden Valley) the Coachella Valley and Palm Springs are at 200-275 degrees. The Los Angeles basin is not named separately: within the 20 km clustering radius the near-field towns win, so LA shows as part of the 250-290 degree spread rather than as its own named dome. Treat the 282 degree dome as "Yucca Valley and the Los Angeles side".
- Great Smoky: 355 degrees (north), 33%, named Pigeon Forge (the Gatlinburg and Pigeon Forge corridor); 311 degrees (northwest), 15%, Knoxville. Cades Cove adds Maryville (319 degrees).

## Trend (2013 to 2025)

- Median change in the summed radiance within 150 km is +34%; only Theodore Roosevelt (-12%) and Virgin Islands (-3%) fall, Dry Tortugas is flat.
- Do not read these as real light growth. The increase appears in all radiance classes (including cells under 1 nW, and the count of lit cells rises), which points to product and sensitivity differences between early-mission 2013 data and the 2025 reprocessing (gap-filling, BRDF and lunar corrections, noise floor). Use the trend only to compare parks with each other.
- Largest values are on tiny bases and mostly not light pollution: Katmai +789% (212 to 1885), Hawaii Volcanoes +436% (the lava lake at Halemaumau and the 2018-2025 eruptions glow), Lake Clark +407%, Wrangell-St. Elias +275%, Carlsbad Caverns +306% and Guadalupe Mountains +145% (Permian Basin oil and gas flaring and well-pad lighting), Glacier Bay +241%, Denali +206%. Alaskan values are dominated by sub-1 nW diffuse cells (aurora, gap-fill, snow-free-window differences).
- The same flaring and lava sources inflate `glow` itself for Carlsbad Caverns and Hawaii Volcanoes.

## Limitations (show a short version in the app)

- VIIRS DNB is blind below about 500 nm. White and blue LEDs emit largely in that range, so the sensor under-detects LED street lighting. A city that converts from sodium to LED can look dimmer to VIIRS while its sky glow rises. Declines in the trend, and low glow near LED-heavy towns, may therefore be wrong.
- The index is a relative, calibrated proxy. It models no atmospheric propagation, aerosols, terrain shielding, light colour, or upward-emission angle. It is not a sky-brightness measurement and must not be presented as one.
- Cells under 2 km cannot resolve a lit visitor centre or lodge. Because the formula weights distance by d^-2.5 and treats d under 1 km as 1 km, a lit village next to a spot (Grand Canyon Village, Cuyahoga Valley suburbs, Volcano) can dominate the spot's glow. That is a real effect for visitors, but it is local light, not skyglow from a distant city.
- Calibration labels are conservative integer hand estimates, mostly 2, so the dark end is not resolved. Alaska relies on gap-filled values. Light dome names come from a hand-written metro list and are `null` for small settlements and park lodging not on the list.
- Half-pixel (about 230 m) tile registration offset is ignored.

## Reproduce

```
python3 -m pip install --target <scratch>/pylib h5py numpy
export PYTHONPATH=<scratch>/pylib
python3 Scripts/build_skyglow.py --cache <scratch>      # ~16 min for the 80 downloads, then ~1 min
python3 Scripts/build_skyglow.py --cache <scratch> --skip-download   # reprocess from aggregated cache
```

Outputs: `Nyx/Resources/skyglow.json`, `Research/skyglow-calibration.csv`.

## Review queue: hand estimate versus computed (2026-10-06)

The app keeps the hand `bortleEstimate` in the score (DECISIONS, "Every sky"). These parks differ from the computed class by a full class or more and should be checked against measured data (NPS Night Skies Program SQM/all-sky photometry, or DarkSky International reports) before either number is changed:

| Park | Hand | Computed | Likely reason to check |
|---|---|---|---|
| Biscayne (bisc) | 5 | 4.0 | Miami dome over water; the hand value may be conservative |
| Cuyahoga Valley (cuva) | 6 | 5.0 | Suburban park; the 2 km cells smooth Akron/Cleveland edges |
| Kobuk Valley (kova) | 2 | 3.2 | Alaskan gap-filled values; probably a computed overestimate |
| Mammoth Cave (maca) | 4 | 2.9 | Dark-Sky designated; the hand value may be too bright |
| Saguaro (sagu) | 4 | 5.0 | Tucson at the park boundary; the hand value may be too dark |

Also note Hawaiʻi Volcanoes and Carlsbad Caverns, whose computed glow includes lava and oil-field flaring rather than skyglow from towns.
