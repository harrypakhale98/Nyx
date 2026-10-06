# Spanish localization (es-MX / US Spanish): first draft

Prepared on 2026-10-05 as a translation memory. **Nothing here is wired into the app yet.** The String Catalogs were not edited, because other work was editing them at the same time.

## Files

| File | What it is |
|---|---|
| `es-strings.json` | `{ "<English source key>": "<Spanish>" }` for all 692 keys in `Nyx/Resources/Localizable.xcstrings` as of this date (690 when the draft started, plus *Field mode offered* and *Nothing changes yet*). It includes the five `essay.*` keys. No entry has plural or device variations, so every value is a plain string. Every format specifier (`%@`, `%lld`, `%%`) and `${park}` placeholder was checked by script against the English: same count, same type, same order. No positional reordering was needed. |
| `es-infoplist.json` | The two keys in `Nyx/Resources/InfoPlist.xcstrings`: `NSLocationWhenInUseUsageDescription` and `NSAlarmKitUsageDescription`. |
| `glossary-es.md` | Register (tú), term decisions, proper names, meteor shower and compass names. Read this first. |
| `learn-es/*.md` | The five Learn essays in Spanish. They match the `essay.*` values in `es-strings.json` (the first line is the title, then paragraphs separated by blank lines, the same structure `EssayView` expects). |
| `appstore-es.md` | Spanish (Mexico) App Store metadata: name, subtitle, promotional text, description, keywords, What's New and screenshot captions, with character counts. |

## Integration (for whoever wires it in)

1. Add `es-419` or `es-MX` to the project's known regions in `project.yml` (decide which. `es-419` covers all of Latin America and the US, while App Store Connect calls the metadata locale "Spanish (Mexico)"). Run `xcodegen generate`.
2. Merge `es-strings.json` into `Localizable.xcstrings` as `"es"`/`"es-419"` `stringUnit`s with `state: "needs_review"` until the native review below is done. Merge `es-infoplist.json` into `InfoPlist.xcstrings` the same way. A small script modeled on `Scripts/sync_catalog.py` is the safest way.
3. Keys added to the catalog after 2026-10-05 have no Spanish yet. Diff the catalog keys against `es-strings.json`.
4. Strings that do not come from the catalog stay English until they are localized at the source: park names (deliberately English), viewing-spot names, meteor shower names (see the glossary warning about *Máximo de las %@*), NPS alerts and programs (they come from the API in English).
5. Check on device in Spanish, at AX5 Dynamic Type: SkyArc canvas labels (*Salida de la Luna*, *Puesta del sol*), the Live Activity (*Sale el sol a las*), the Lock Screen widgets, the time-river badges, and the field-mode milestone list.

## Remaining step: native-speaker review (the owner will arrange it)

A native Mexican or US-Hispanic Spanish speaker, ideally someone who stargazes or works in parks, should review everything before release. Points to check:

- **Labels that may be too long.** Most short labels are within about 130% of the English, but some cannot be: *Puesta de la Luna* / *Salida de la Luna* (Moonset/Moonrise), *Núcleo de la Vía Láctea a la vista* (Milky Way core up), *Observación de estrellas* (Stargazing Focus), and VoiceOver-only words such as *la izquierda* / *Desactivada*, where length does not matter. Confirm none of them truncate.
- **Uncertain choices:**
  - *Sin cruce* ("No crossing": the Moon or a target never crosses the horizon that night).
  - *Queda oscuridad total por* (lead-in for a countdown timer).
  - *Sale después de la oscuridad* / *Se pone antes de la oscuridad*.
  - *Mala* for the lowest band.
  - *Prístina* for the top band.
  - The iOS names *Concentración* and *modo Silencio*.
  - Closed compass compounds (*estenoreste*).
  - *a las 1:20* edge case.
- **AI prompt strings** (*Explica la idea principal…*, *Reflexiona sobre patrones…*, *¿Cuáles de estos parques…?*) are sent to the on-device model. Test them with Foundation Models in Spanish once Apple Intelligence supports the locale.
- **Honesty.** No translated sentence should be more certain than the English. Watch for *visible*, *garantía* and *confirma*.
