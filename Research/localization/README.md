# Spanish localization (es-MX / US Spanish): draft

Prepared on 2026-10-05 as a translation memory and brought up to date on 2026-10-06 against commit a7825ec (branch `roadmap`). **Nothing here is wired into the app yet.** The String Catalogs were not edited, because other work was editing them at the same time.

## Files

| File | What it is |
|---|---|
| `es-strings.json` | `{ "<English source key>": "<Spanish>" }` for all **1,088** keys in `Nyx/Resources/Localizable.xcstrings` as of commit a7825ec: 687 from the first pass plus **401 added on 2026-10-06** (400 UI strings and `essay.access`). It includes the six `essay.*` keys. No entry has plural or device variations, so every value is a plain string. Every format specifier (`%@`, `%lld`, `%%`) and `${park}` placeholder was checked by script against the English: same count, same type, same order. No positional reordering was needed. The English values of the `essay.*` keys did not change since the first pass. |
| `es-strings-obsolete.json` | The **5** first-pass entries whose keys are no longer in the catalog (the source text changed or the string was removed): *Darkness score %lld, %@*, *%@, %@. Darkness score %lld, %@. %@ %@ %@*, *Swipe up or down to move one night at a time.*, *Field mode offered*, *Nothing changes yet*. Kept for reference only; their replacements are in `es-strings.json`. |
| `es-vision-strings.json` | All **183** keys in `NyxVision/Resources/Localizable.xcstrings`. 138 reuse the iPhone translation word for word; 45 are Vision-only. |
| `es-shower-names.json` | Meteor shower code (`sky-events.json` `meteorShowers[].code`) → Spanish name, for all 13 showers. The integrator will localize shower names by code. |
| `es-infoplist.json` | The two keys in `Nyx/Resources/InfoPlist.xcstrings`: `NSLocationWhenInUseUsageDescription` and `NSAlarmKitUsageDescription`. |
| `glossary-es.md` | Register (tú), term decisions, proper names, meteor shower and compass names. Read this first. |
| `learn-es/*.md` | The six Learn essays in Spanish (`access.md`, *Un cielo para todos*, added 2026-10-06). They match the `essay.*` values in `es-strings.json` (the first line is the title, then paragraphs separated by blank lines, the same structure `EssayView` expects). |
| `appstore-es.md` | Spanish (Mexico) App Store metadata: name, subtitle, promotional text, description, keywords, What's New and screenshot captions, with character counts. |

## Integration (for whoever wires it in)

1. Add `es-419` or `es-MX` to the project's known regions in `project.yml` (decide which. `es-419` covers all of Latin America and the US, while App Store Connect calls the metadata locale "Spanish (Mexico)"). Run `xcodegen generate`.
2. Merge `es-strings.json` into `Localizable.xcstrings` as `"es"`/`"es-419"` `stringUnit`s with `state: "needs_review"` until the native review below is done. Merge `es-infoplist.json` into `InfoPlist.xcstrings` the same way. A small script modeled on `Scripts/sync_catalog.py` is the safest way.
3. Keys added to the catalog after commit a7825ec have no Spanish yet. Diff the catalog keys against `es-strings.json`. There is no watch- or widget-specific catalog: `NyxWatch`, `NyxWatchWidgets` and `NyxWidgets` compile `Nyx/Resources/Localizable.xcstrings`, so their strings are already in `es-strings.json`. `NyxVision` has its own catalog (`es-vision-strings.json`). `InfoPlist.xcstrings` is unchanged since the first pass.
4. Strings that do not come from the catalog stay English until they are localized at the source: park names (deliberately English), viewing-spot names, meteor shower names until `es-shower-names.json` is wired in (see the glossary warning about *Máximo de las %@*), the nps.gov accessibility evidence quotes and the solar-eclipse `region` text in `sky-events.json`, town names in sky-glow domes, and NPS alerts and programs (they come from the API in English).
   - `sky-events.json` names two showers with a month (*April Lyrids*, *October Draconids*). The Spanish map uses the plain names *Líridas* and *Dracónidas*, as the glossary does; add *de abril* / *de octubre* if the app ever shows another Lyrid or Draconid shower.
   - *You were out for the %@ at %@.* receives the eclipse name through `.lowercased()`, which turns *Eclipse total de Luna* into *eclipse total de luna*. Spanish needs *Luna* capitalized: drop `.lowercased()` for Spanish or add lowercase-initial eclipse keys.
5. Check on device in Spanish, at AX5 Dynamic Type: SkyArc canvas labels (*Salida de la Luna*, *Puesta del sol*), the Live Activity (*Sale el sol a las*), the Lock Screen widgets, the time-river badges, the field-mode milestone list, the Apple Watch complications (*Puesta del sol %@*, *Crepúsculo del alba %@*, *La Luna se pone %@* in the inline and rectangular families), the watch "now" line (*Ahora: oscuridad total*, *Ahora: crepúsculo*) and the Vision Pro night detail (*En el cielo toda la noche*).

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

### Added 2026-10-06: strings flagged for native review

- **Too long for tight layouts (more than about 130% of the English).** Watch and complications: *Puesta del sol %@* (Sunset %@), *Salida del sol %@*, *Crepúsculo del alba %@*, *La Luna se pone %@*, *Oscuridad* (Dark, the watch's short milestone title), *Ahora: oscuridad total* (Truly dark now), *Guardados en el iPhone*, *Próxima noche oscura* (widget name). Phone: *En parte sin escalones* (Partly step-free), *Observación sin escalones*, *Solo fines de semana*, *Ventana de luna nueva* (rotor, VoiceOver only), *Sentir una Luna medio iluminada* (Feel a half Moon), *Observación de estrellas en %@* (Calendar event title). Vision Pro: *En el cielo toda la noche* (Up all night), *Oculta toda la noche*. VoiceOver-only and sentence strings are longer too, where length does not matter.
- **Apple UI names to verify against the current es-MX iOS 26/27 UI:** *Gráfica de audio* (Audio Graph rotor item), *Pila inteligente* (Smart Stack), *En espera* (StandBy, debug strings only), *Control por voz* (Voice Control), *Diferenciar sin color*, *Reducir efectos de resaltado* (Reduce Highlighting Effects), *Preferir transiciones de fundido* (Prefer Cross-Fade Transitions), *Atajos* (Shortcuts), *Complicaciones*.
- **Uncertain choices:**
  - *step-free* = *sin escalones*; *Steps or trail* = *Escalones o sendero*. Check against NPS Spanish accessibility wording.
  - *Primera luz* for the First light moment (the astronomers' term for a telescope's first night; it may read oddly to non-astronomers).
  - *Noches afuera* (Nights out) in the year recap.
  - *Un cielo para todos* as the title of *Stargazing for everyone* (freer than the English).
  - *Escuchar la noche* (Listen to this night) versus *Escuchar esta noche* (Listen to tonight): *esta noche* always means tonight in Spanish, so the non-tonight button cannot say it.
  - *Sentir una Luna medio iluminada* instead of *media luna*, which in everyday Spanish means a crescent.
  - *Entrar en este cielo* / *Salir del cielo* (Vision Pro: Stand under this sky / Leave the sky).
  - *Mostrar en Esta noche*, *En Esta noche*, *Esta noche muestra %@* (watch): the tab name *Esta noche* is also the everyday word for tonight.
  - *Hawaiʻi* kept with the ʻokina, as in the English, rather than the RAE *Hawái*.
  - *En %@ pasaste %@ bajo las estrellas en %@ que no conocías* (each one new to you): rephrased so it works for one park and for many.
  - *una población al %@* (a town to the %@) and *población* for "town" in the Black Marble text, because the light can come from a city.
  - *Índice de oscuridad (0–100)* as the chart axis title for *Darkness score, out of 100*.
- **AI tool strings** (*%@, %@; a %lld millas en línea recta de %@; esta noche %lld/100 %@*, *%@ horas de oscuridad total*) are read by the on-device model. Test them in Spanish with Foundation Models, as for the first-pass prompts.
