# App Store metadata: Spanish (Mexico), first release

> **Must be rewritten after the native-speaker review.** Everything below is a draft by a non-native writer, updated on 2026-10-07 to match the English first-release page (`metadata.md`). Do not paste any Spanish field into App Store Connect until a native speaker of Mexican Spanish has reviewed and rewritten it (`INPUT_NEEDED.md`). If the review is not done before submission, ship the store page in English only; the in-app Spanish is a separate decision (AM-12).

One App Store Connect localization, **Spanish (Mexico)**, serves the Mexico storefront and Spanish-speaking customers on the US storefront (confirm in App Store Connect → App Information → Localizable Information). Glossary: `Research/localization/glossary-es.md` (tú throughout, *Luna* capitalized for the body, *Índice de oscuridad*). Counts were checked by script on 2026-10-07; keywords are counted in UTF-8 bytes, because accented letters take two.

The same "confirm before pasting" table as in `metadata.md` applies: delete the sentence for any feature that is not in build 8.

## Name (≤30)

**Nyx: Dark Sky Planner** — keep the English name. The Home Screen name stays **Nyx**.

## Subtitle (≤30)

**Cielo oscuro, parque a parque** (29)

The English subtitle's search terms ("stargazing", "national parks") are carried by the keywords here, because "Observación de estrellas en parques nacionales" does not fit in 30 characters. Alternative for the reviewer: `Astronomía en parques de EE. UU.` (32, two over; would need trimming).

## Promotional text (≤170)

```
¿Qué parque y qué noche tienen el cielo más oscuro? La Vía Láctea para cada parque, un pronóstico honesto y un modo rojo para tus ojos. Gratis y sin rastreo.
```

[157 characters]

## Keywords (≤100 bytes)

```
estrellas,parque nacional,vía láctea,lluvia de meteoros,fase lunar,astronomía,astrofotografía
```

[93 characters, 97 bytes]

"Nyx", "dark", "sky", "planner", "cielo", "oscuro" and "parque" are already in the name and subtitle; "parque nacional" stays because the subtitle has only "parque". "aurora" stays out: Nyx does not forecast auroras.

## Description (≤4000)

```
¿Qué parque y qué noche? Nyx compara noche a noche los 63 parques nacionales de Estados Unidos y le da a cada uno un Índice de oscuridad de 0 a 100, según la Luna, las nubes, el brillo del cielo y las horas de oscuridad total. Te dice lo que no sabe. Gratis. Sin cuenta, sin anuncios, sin rastreo.

UN ÍNDICE, CON SUS RAZONES
Cuatro partes se suman, y la más débil puede limitar el total: una noche nublada nunca parece buena. Debajo del índice se indica qué límite aplica. Los cierres del National Park Service aparecen junto al número.

PLANEA
Ve los parques más oscuros de esta noche dentro de un radio en línea recta. Mira el mes de un parque en un calendario, con la mejor racha de noches marcada, y recorre treinta noches mientras cambia la forma de la Luna. Dile a Nyx qué noches tienes libres y te sugiere un parque para cada una.

UN PRONÓSTICO HONESTO
En los próximos días, el pronóstico de nubes cuenta completo. Más adelante se ajusta hacia la nubosidad habitual del parque en ese mes, y después solo cuenta la nubosidad habitual; esas noches lo indican. Nyx compara tres modelos y muestra el rango cuando no coinciden. El humo denso puede limitar el índice.

QUÉ HAY EN EL CIELO ESTA NOCHE
Para cada parque: el núcleo de la Vía Láctea y sus horas sin Luna, los planetas, las lluvias de meteoros y los eclipses de Luna visibles. Son razones para ir; nunca cambian el índice.

MODO DE CAMPO
En el parque, una pantalla roja y tenue cuenta el tiempo hasta la oscuridad total y lleva un reloj de adaptación a la oscuridad. «Hacia dónde mirar» orienta el cielo real hacia donde apuntes tu iPhone, sin cámara. Las alarmas pueden despertarte cuando salga el núcleo.

EN TU MUÑECA Y EN TU ESPACIO
En el Apple Watch: el índice, la Digital Crown para ver las próximas noches y complicaciones que se vuelven rojas al anochecer. En el Apple Vision Pro: párate bajo el cielo calculado de un parque, con nombres de estrellas, y pon la Luna sobre tu mesa. En el iPad: el calendario y el parque, uno junto al otro.

BRILLO DEL CIELO Y ACCESO
Cada punto de observación compara su brillo del cielo con el de los demás parques, según los datos Black Marble de la NASA. Compara lugares; no es una medición. Las notas sin escalones citan las páginas de accesibilidad de cada parque.

GUARDA UN POCO DE LA NOCHE
Guarda parques y recibe recordatorios locales opcionales para las noches prometedoras. Lleva un diario privado con notas y las fotos que elijas; cada noche se vuelve una estrella de tu propia constelación. Expórtalo como un archivo que conservas tú. Los widgets muestran el mejor cielo entre tus parques guardados.

PARA MÁS PERSONAS
Nyx está diseñada para VoiceOver y para los tamaños de texto más grandes. Los gráficos de audio te dejan escuchar un mes de oscuridad, la vibración puede seguir la fase de la Luna y un modo rojo mantiene toda la app legible para los ojos adaptados a la oscuridad.

PRIVADA Y SIN CONEXIÓN
Tu ubicación, tu diario y tus fotos se quedan en tu dispositivo. Tres servicios públicos aportan datos, cada uno con su propio interruptor en Tu privacidad: las alertas de los parques del National Park Service, y los pronósticos y el humo de Open-Meteo. Nunca reciben tu ubicación. La Luna, el crepúsculo, la Vía Láctea, la biblioteca de parques, el calendario y tu diario funcionan sin conexión.

TEN EN CUENTA
Los índices son estimaciones para planear. No confirman cielos despejados ni caminos abiertos. Revisa el estado actual del parque antes de viajar.

Datos meteorológicos de Open-Meteo.com (CC BY 4.0). Humo y nubosidad habitual: Copernicus (CAMS, C3S). Luces nocturnas e imágenes de la Luna: NASA. Lluvias de meteoros: IMO. Eclipses de Luna: Fred Espenak, NASA's GSFC. Datos de los parques: National Park Service. Nyx no está afiliada al National Park Service, la NASA ni DarkSky International, ni cuenta con su respaldo.
```

[3,855 of 4,000 characters; 3,890 if each line break counts twice]

## Calques fixed from the previous draft (ES-1)

| Previous draft | Problem | New draft |
|---|---|---|
| Dale tiempo a un cielo más oscuro (opening line) | "Dale tiempo" means "be patient with it", not "make time for" | Removed; the description now opens with the question, as the English does: «¿Qué parque y qué noche?» |
| Dale tiempo a la noche (caption) | Same calque | **Hazle espacio a la noche** (or the reviewer's choice: *Date tiempo para la noche*) |
| Planea una noche más oscura (subtitle) | Fine, but described the 1.0 page | Replaced by the new subtitle above |
| Solo Luna y oscuridad / Las noches sin relleno solo tienen Luna y oscuridad | Lost the meaning, and no longer what the app does (score v2 uses the usual clouds) | **Aún sin pronóstico de nubes** / **Vista anticipada** |
| Resplandor (score part) | Ambiguous alone | **Brillo del cielo** |
| la semana que viene (widgets), "no incluyen la calidad de imagen para telescopios", no Watch / Vision Pro / planner | Stale against 1.1 | Rewritten above from the English first-release text |
| "Nyx no está afiliado" | Nyx is *la app*; the reviewer should pick one gender and keep it | Draft uses the feminine (*diseñada*, *afiliada*) throughout; the in-app watch credits use the masculine (*afiliado*), so the reviewer should settle one |

## Screenshot captions (for `Scripts/make_store_frames.swift`, `spanishFrames`)

Align with the English captions when the frames are recaptured from build 8:

| English | Spanish draft |
|---|---|
| Where is the sky darkest tonight? | ¿Dónde está más oscuro el cielo esta noche? |
| One number, and its reasons. | Un número, con sus razones. |
| The Milky Way, and when to look. | La Vía Láctea, y cuándo mirar. |
| Red light for dark-adapted eyes. | Luz roja para ojos adaptados a la oscuridad. |
| Point your iPhone. Find the core. | Apunta tu iPhone. Encuentra el núcleo. |
| Choose the night worth the drive. | Elige la noche que vale el viaje. |
| A park for every free night. | Un parque para cada noche libre. |
| Every night becomes a star. | Cada noche se vuelve una estrella. |
| Hear the shape of the night. | Escucha la forma de la noche. |
| City glow, named. Step-free spots, marked. | El brillo de cada ciudad, con nombre. Los puntos sin escalones, marcados. |

## What's New

None: 1.1 is the first public release, so App Store Connect shows no What's New field.
