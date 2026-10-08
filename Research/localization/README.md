# Spanish localization (es-MX / US Spanish): draft

Prepared on 2026-10-05 as a translation memory and brought up to date on 2026-10-06 against commit a7825ec (branch `roadmap`). **Wired in on 2026-10-06:** `python3 Scripts/apply_translations.py` merges these files into the String Catalogs as the `es` localization (it also runs at the end of `sync_catalog.py` and `sync_vision_catalog.py`). Edit Spanish here, then run it; never edit the catalogs' Spanish by hand. The "Integration" section below is kept as the record of what was decided.

## Files

| File | What it is |
|---|---|
| `es-strings.json` | `{ "<English source key>": "<Spanish>" }` for the plain-string keys of `Nyx/Resources/Localizable.xcstrings` (1,643 keys on 2026-10-07, of which 27 are plurals kept in `es-plurals.json` and the data-backed `shower.*`, `access.*` keys come from their own files). It includes the `essay.*` values; the Learn essays themselves live in `learn-es/`, which wins. Every format specifier (`%@`, `%lld`, `%%`, positional `%1$@`) is checked by `apply_translations.py` against the English: same count and types, positions free. Keys that no longer exist in the app are harmless and stay as translation memory. |
| `es-plurals.json`, `en-plurals.json` | Counted strings as real String Catalog plural variations, `one` and `other` (Spanish `many` falls back to `other`). A string with one counted number is `{"one": "...", "other": "..."}`. A string with several is `{"format": "%#@nights@ under the stars at %#@parks@", "nights": {"arg": 1, "one": "%arg night", "other": "%arg nights"}, ...}` (Xcode's substitutions: `arg` is the argument number, `%arg` the formatted number; a form may omit it, as in *El parque*). The English file defines which keys are plural; `--check` reports a key with no Spanish form or a missing `one`/`other`. The Swift code keeps writing plain interpolation (`String(localized: "\(n) nights")`): the plural form is chosen by the catalog, so no `n == 1` branch is needed. `PluralTests` checks the compiled tables in both languages. |
| `es-vision-strings.json` | The keys of `NyxVision/Resources/Localizable.xcstrings` (352 on 2026-10-07), including the 40 `constellation.<abbr>` names the Vision Pro sky looks up (English from `NyxVision/Resources/constellations.json`). Strings the iPhone app shares reuse its Spanish word for word. |
| `es-shower-names.json` | Meteor shower code (`sky-events.json` `meteorShowers[].code`) → Spanish name, for all 13 showers. The integrator will localize shower names by code. |
| `es-access-notes.json` | Park id → Spanish access note (catalog keys `access.<id>`; English from `parks.json`), added 2026-10-06 for the 17 parks in `Research/park-access.md`. |
| `es-infoplist.json` | The keys of `Nyx/Resources/InfoPlist.xcstrings`: the three usage descriptions (`NSLocationWhenInUseUsageDescription`, `NSAlarmKitUsageDescription`, `NSMotionUsageDescription`) and the document and type names *Nyx Journal* and *Nyx Park* (the Info.plist localizes those by their English text). `sync_catalog.py` rebuilds the English from `project.yml`, so the catalog cannot drift from the plist. |
| `glossary-es.md` | Register (tú), term decisions, proper names, meteor shower and compass names. Read this first. |
| `learn-es/*.md` | The ten Learn essays in Spanish, one file per `Nyx/Resources/learn/<name>.md` (and `access.md`, whose English lives only in the catalog). The first line is the title, then paragraphs separated by blank lines, the same structure `EssayView` expects. `apply_translations.py` writes them as the `essay.<name>` Spanish and takes the English `essay.<name>` from `Nyx/Resources/learn/<name>.md`, so each essay has one source per language. |
| `appstore-es.md` | Spanish (Mexico) App Store metadata: name, subtitle, promotional text, description, keywords, What's New and screenshot captions, with character counts. |

## Workflow (after any copy change)

1. Build Debug for the iOS simulator (the `Nyx` scheme also builds the embedded watch app and the widgets) and for `NyxVision`; the compiler writes `.stringsdata` for every `Text("…")`, `String(localized:)` and `LocalizedStringResource`.
2. `python3 Scripts/sync_catalog.py <iOS DerivedData>` and `python3 Scripts/sync_vision_catalog.py <Vision DerivedData>`. New keys appear in the catalogs with the English as the value; keys no longer extracted are pruned **only** when their value is still the auto-added text, so hand-written entries (`essay.*`, `shower.*`, `access.*`, App Intent summaries with `${…}`) are never removed. Both scripts finish by running `apply_translations.py`.
3. `python3 Scripts/apply_translations.py --check` lists every key without Spanish, every counted string without both plural forms and every Spanish text whose format specifiers differ from the English. Fix those in the JSON files here; never in the catalogs.
4. `python3 Scripts/apply_translations.py` writes the catalogs. It is idempotent and byte-stable (same JSON layout as Xcode).

A counted string ("3 nights") is added to `en-plurals.json` and `es-plurals.json` instead of `es-strings.json`. Strings with several counts use the `format` layout; keep the argument positions explicit (`%2$lld`) in every form.

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

### Added 2026-10-07: strings flagged for native review

- **Times without "a las".** Bare times after *desde* and *hasta*, a colon after a verb (*Sale: %@*, *Se pone: %@*, *La Luna se pone: %@*), parentheses for a time inside a sentence (*Sale por el este (%@)*), and *aprox. %@* for "around". Check that *Oscuro desde %@*, *Con Luna hasta %@* and *Luna oculta desde %@* read well on the wrist.
- **Gender of the band words.** The five words stay feminine and agree with *noche* (*Noche Prístina*, *noches Buenas*). Where "Darkness score N" came first the sentence now says *índice de oscuridad 94, noche Prístina*, which fixes the clash with masculine *índice*. *Mala* and *Prístina* are still the glossary's open questions; the audit suggests *Excepcional / Excelente / Buena / Regular / Baja*.
- **Plans and streaks.** *Planear* for the Plan tab, *Mejor racha* and *Racha de luna más oscura* for the best stretch of nights, *Mis noches libres*.
- **Following a night.** *Seguir esta noche*, *Siguiendo esta noche*, *Dejar de seguir*; *Abrir el cielo* for the alarm action "Open sky" (it could read as "open heaven": *Abrir el cielo de esta noche* is the alternative).
- **Parks and sources.** *National Park Service* stays in English everywhere (the first draft had *Servicio de Parques Nacionales* in the credits); *International Dark Sky Park* stays in English; *Certificación Dark Sky*; *Cielo del centro de la ciudad* for Bortle 9.
- **Visibles / Ocultos** as the state of the "Other parks within reach" list (VoiceOver).
- **Copernicus and CAMS credits** (*Servicio de Cambio Climático de Copernicus*, *Servicio de Vigilancia Atmosférica de Copernicus*) and the long *About the data* blocks, which were translated from the English rewrite of 2026-10-07; read them once for tone.
- **Counted strings.** *Cerca de %lld horas de oscuridad total*, *Al segundo %lld* / *A los %lld segundos*, and the one-night forms *La mejor de la próxima noche*, *El parque con las noches más oscuras…* (the singular drops the number).
- **Not localized yet:** the Siri phrases of the App Shortcuts (there is no `AppShortcuts` catalog, so Siri answers in English only), park names, viewing-spot names, and the text NPS sends (alerts, programs, campgrounds).
