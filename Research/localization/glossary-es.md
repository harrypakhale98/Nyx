# Nyx Spanish glossary (es-MX / US Spanish)

Every translation in `es-strings.json`, `es-infoplist.json`, `learn-es/` and `appstore-es.md` follows this file. Change a term here first, then update it everywhere.

## Register and style

- **Tú, used throughout.** Apple uses tú in Latin American Spanish system text, and it fits a ranger talking to one visitor. Never usted, never vos. Imperatives are tú forms: *Elige*, *Confirma*, *Revisa*.
- **Button and menu labels use the infinitive** (*Guardar parque*, *Abrir Configuración*, *Iniciar modo de campo*), the way iOS does. Headlines and invitations use the tú imperative (*Encuentra tu cielo oscuro*, *Guarda un poco de la noche*).
- Calm and short. No exclamation marks, no ¡…!, no marketing adjectives. Questions use the opening ¿.
- **Gender-neutral second person.** Avoid forms like *estacionado* or *cómodo* when they would refer to the reader (*cuando te hayas estacionado*, *estar a gusto*).
- **Capitals: Luna and Sol** when they mean the bodies, matching the English *Moon* and *Sun* (*la Luna se pone*). Moon phases are lowercase mid-sentence (*cerca de la luna nueva*) and capitalized only at the start of a label (*Luna nueva*). *luz de luna* is lowercase.
- **Numbers:** the decimal point stays a period (0.25, 29.53), which matches Mexico and the US. Write *40%* with no space. Format specifiers, units and `Measurement` output are untouched.
- **Times:** *a las %@*, *hasta las %@*, *hacia las %@* (time strings come from the system formatter). Known limitation: 1:xx o'clock times need *a la 1:20*. This is rare at night and acceptable for v1. The reviewer may want to rephrase as *a %@* if it reads badly on device.
- Quotation marks follow the English source (“ ” or \" \").

## Core terms

| English | Spanish | Notes |
|---|---|---|
| Darkness Score | **Índice de oscuridad** (in-app mid-sentence: *índice de oscuridad*; alone: *el índice*) | *Puntuación* sounds like a game; *índice* is the weather-and-air-quality register (UV index). |
| score (generic) | índice | *el índice podría ir de 60 a 72* |
| out of 100 | de 100 | *94 de 100* |
| score breakdown | desglose del índice | |
| Pristine / Excellent / Good / Fair / Poor | **Prístina / Excelente / Buena / Regular / Mala** | Feminine, agreeing with the implied *noche*. *Excelente* and *Regular* do not change with gender. *Mala* is plain and honest; reject the anglicism *Pobre*. |
| estimate (noun) | estimación | |
| true darkness | **oscuridad total** | The plain-language term the app uses for astronomical darkness. *No true darkness* = *Sin oscuridad total*. |
| astronomical darkness | oscuridad astronómica | Only where the source says "astronomical". |
| dark window | periodo de oscuridad | Not *ventana*, which reads as an anglicism here. |
| five-night moon window / new moon window | ventana de luna nueva (cinco noches) | *ventana* is kept here because it names a planning window. |
| moon and darkness only | solo Luna y oscuridad | Score label when no cloud forecast exists. |
| forecast horizon / hollow nights | sin relleno, punteadas | *Las noches punteadas y sin relleno…* |
| time river | río del tiempo | |
| civil / nautical / astronomical twilight | crepúsculo civil / náutico / astronómico | |
| twilight | crepúsculo | |
| dawn / dawn twilight | alba / crepúsculo del alba | *before dawn* = *antes del amanecer* (more natural). |
| dusk | anochecer | |
| sunrise / sunset | salida del sol / puesta del sol | Short countdown labels use *Sale el sol a las*, *Sale el sol en*. |
| moonrise / moonset | salida de la Luna / puesta de la Luna | |
| rises / sets (verbs) | sale / se pone | *sale por el este* (rising uses *por*), *en el oeste* elsewhere. |
| Moon up / Moon down | Luna en el cielo / Luna oculta | *Moon-free* = *sin Luna*. |
| N° up | a N° de altura | |
| waxing / waning | creciente / menguante | |
| New moon, Waxing crescent, First quarter, Waxing gibbous, Full moon, Waning gibbous, Last quarter, Waning crescent | Luna nueva, Luna creciente, Cuarto creciente, Gibosa creciente, Luna llena, Gibosa menguante, Cuarto menguante, Luna menguante | |
| lunar eclipse (total / partial / penumbral) | eclipse total / parcial / penumbral de Luna | *Totality* = *Totalidad*. |
| Milky Way | Vía Láctea | |
| Milky Way core / bright center | núcleo de la Vía Láctea / centro brillante | *Core* = *Núcleo*. |
| Bortle scale / class | escala Bortle / clase Bortle | "Bortle" is never translated. *Bortle estimado*, *Bortle observado*. |
| light pollution | contaminación lumínica | |
| skyglow / sky glow | resplandor del cielo (short: *resplandor*) | |
| artificial sky brightness | brillo artificial del cielo | |
| cloud cover | nubosidad | *Clouds* = *Nubes*. |
| forecast models agree / roughly agree / disagree | coinciden / casi coinciden / discrepan | Badges: *Modelos coinciden*, *Casi coinciden*, *Modelos difieren*. |
| haze / smoke | bruma / humo | *Heavy smoke or haze* = *Humo o bruma densos*. |
| dew | rocío | |
| night vision / night-vision mode | visión nocturna / modo de visión nocturna | |
| field mode | **modo de campo** | |
| dark adaptation | adaptación a la oscuridad | Cones and rods = *conos* and *bastones*. |
| Focus (iOS) | Concentración (*modo de concentración*) | **Verify against the current es-MX iOS UI.** The Focus filter is named *Observación de estrellas*. |
| Silent mode | modo Silencio | Same verification. |
| Settings (iOS app) | Configuración | Apple's es-MX name. |
| Lock Screen / Home Screen | pantalla bloqueada / pantalla de inicio | |
| Done / OK | OK | iOS es-MX uses *OK* in navigation bars. |
| viewing spot | punto de observación | *viewing area* = *zona de observación*. |
| starting park | parque de partida | |
| as the crow flies / straight-line | en línea recta | |
| ranger | guardaparques | Same form for singular and plural. Used by NPS Spanish pages. |
| visitor center | centro de visitantes | |
| ranger night-sky programs | programas de cielo nocturno con guardaparques | |
| park alerts / closures | alertas del parque / cierres | |
| International Dark Sky Park / Dark-Sky designated | certificación Dark Sky / *Con certificación Dark Sky* | Program names stay in English. |
| journal / entry | diario / entrada | |
| saved parks | parques guardados | *Unsave* = *Quitar parque*. |
| Learn (tab) | Aprender | |
| Tonight (tab) | Esta noche | |
| Your privacy | Tu privacidad | |
| About the data | Sobre los datos | |
| Ask Nyx | Pregunta a Nyx | |
| radiant | radiante | |
| ZHR | tasa horaria cenital (THZ) | The essay glosses it as *THZ (ZHR en inglés)*. |
| peak (meteor shower) | máximo | *máximo esta noche*, *máximo en 3 noches*. |
| meteor shower | lluvia de meteoros | |
| … an hour | … por hora | *unos 20 por hora*, *menos de 1 por hora* (masculine, agreeing with *meteoros*). |

## Proper names

- **Park names stay in English** (*Joshua Tree*, *Gates of the Arctic*), matching NPS practice: nps.gov Spanish pages keep the proper name and translate only the generic part (*Parque Nacional Joshua Tree*). Park names come from `parks.json` and are not in the catalog. Generic mentions are translated: *parque nacional*.
- **Never translated:** Nyx, Open-Meteo, NASA, NOAA, ECMWF, DWD, GFS, IFS, ICON, CAMS (Copernicus Atmosphere Monitoring Service), IMO (International Meteor Organization), NPS / National Park Service, Yale Bright Star Catalogue, NASA HEASARC, Scientific Visualization Studio, CGI Moon Kit, IANA, iCloud, Dynamic Island, CC BY 4.0, hostnames.
- **Places:** Estados Unidos, Samoa Americana.
- **Constellations:** Sagitario, Escorpio, Géminis, Perseo, Casiopea, Orión. *Sagitario A\** for Sagittarius A*.

### Planets

Mercurio, Venus, Marte, Júpiter, Saturno (all in the catalog).

### Meteor showers (for `SkyAlmanac` data when it is localized; these names are not in the catalog yet)

| English | Spanish |
|---|---|
| Quadrantids | Cuadrántidas |
| Lyrids | Líridas |
| Eta Aquariids | Eta Acuáridas |
| Southern Delta Aquariids | Delta Acuáridas del Sur |
| Alpha Capricornids | Alfa Capricórnidas |
| Perseids | Perseidas |
| Draconids | Dracónidas |
| Orionids | Oriónidas |
| Southern / Northern Taurids | Táuridas del Sur / Táuridas del Norte |
| Leonids | Leónidas |
| Geminids | Gemínidas |
| Ursids | Úrsidas |

Every shower name is feminine plural, so the catalog strings build on that: *Máximo de las %@*, *Radiante de las %@*, *%@ en su mejor momento*. **If shower names stay in English at runtime, these will read "Máximo de las Geminids". Localize the names, or the integrator should switch to *Máximo: %@*.**

## Compass

| English | Spanish | English | Spanish |
|---|---|---|---|
| N / E / S / W | N / E / S / **O** | north | norte |
| north-northeast | nornoreste | northeast | noreste |
| east-northeast | estenoreste | east | este |
| east-southeast | estesureste | southeast | sureste |
| south-southeast | sursureste | south | sur |
| south-southwest | sursuroeste | southwest | suroeste |
| west-southwest | oestesuroeste | west | oeste |
| west-northwest | oestenoroeste | northwest | noroeste |
| north-northwest | nornoroeste | | |

The compound points use the closed RAE spelling with the *-noreste/-sureste* forms common in Latin America. The reviewer may prefer hyphens (*este-noreste*) for readability. Every direction is masculine, so *en el %@* and *por el %@* work for all of them.

### Moon lit side (VoiceOver)

The frame *con luz desde %@* takes: arriba, abajo, la izquierda, la derecha, arriba a la izquierda, arriba a la derecha, abajo a la izquierda, abajo a la derecha.
