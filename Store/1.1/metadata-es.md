<!-- Copied from Research/localization/appstore-es.md on 2026-10-06 (the translation memory keeps the working copy). Native-speaker review is pending: see INPUT_NEEDED.md. -->

# App Store metadata: Spanish (Mexico)

One App Store Connect localization, **Spanish (Mexico)**, serves both the Mexico storefront and Spanish-speaking customers on the US storefront (the US storefront lists Spanish (Mexico) as a supported metadata language; confirm in App Store Connect → App Information → Localizable Information before submitting). Source: `SUBMISSION.md` (English draft). Limits checked by script on 2026-10-05.

## Name (≤30)

**Nyx: Dark Sky Planner** — keep the English name unchanged. The Home Screen name stays **Nyx**. App names must be unique across the store, and the English name is already reserved by the owner, so reusing it avoids a second availability check.

If the owner wants a Spanish name, the candidate is **Nyx: Planea tu cielo oscuro** (27). Its availability must be checked in App Store Connect first.

## Subtitle (≤30)

**Planea una noche más oscura** (27)

## Promotional text (≤170)

Compara parques y noches, entiende qué sigue siendo incierto y guarda un poco de la noche en un diario privado.

(111 characters)

## Keywords (≤100 bytes, no spaces after commas)

```
astronomía,estrellas,parques nacionales,fase lunar,vía láctea,cielo nocturno,bortle,meteoros
```

92 characters, 95 UTF-8 bytes. "noche", "oscura" and "planea" are already in the subtitle, and "Nyx", "dark", "sky" and "planner" are in the name, so they are not repeated. "aurora" from the English list is left out because Nyx does not forecast auroras. If space allows after review, add `acampar`. App Store search mostly ignores accents, but the accents stay so the list reads correctly.

## Description

Dale tiempo a un cielo más oscuro.

Nyx compara las noches de los 63 parques nacionales de Estados Unidos. La luz de la Luna, la nubosidad, la luz artificial estimada y la duración de la oscuridad total se combinan en un solo Índice de oscuridad, con un desglose que lo explica.

Encuentra parques cercanos dentro de un radio en línea recta, elige tu propio parque de partida u ordena todos los parques según la oscuridad de esta noche. Explora el calendario y la ventana de cinco noches de luna nueva. Sigue los cambios de las condiciones a lo largo de una línea de tiempo de treinta noches. Las horas locales de cada parque te ayudan a planear la noche sin convertir zonas horarias.

Guarda parques, recibe recordatorios locales opcionales para las noches prometedoras y lleva un diario privado con notas y las fotos que elijas. Los widgets de la pantalla de inicio y de la pantalla bloqueada muestran el mejor cielo entre tus parques guardados y la semana que viene. El modo de visión nocturna usa una paleta roja. En Aprender encontrarás ensayos breves sobre cómo encontrar la Vía Láctea, leer la escala Bortle, el resplandor del cielo y cómo compartir la noche.

Los cálculos de la Luna y el crepúsculo, la biblioteca de parques, el calendario, el diario y los parques guardados funcionan sin conexión. Los pronósticos de nubes llegan a unos dieciséis días. Cuando no se conocen las nubes, Nyx lo dice y recalcula la estimación sin ellas. Las clases Bortle son estimaciones conservadoras, no mediciones. Las horas de salida y puesta de la Luna son aproximadas y pueden variar con el terreno.

Nyx no tiene cuentas, anuncios ni rastreo. La ubicación del dispositivo se queda en tu iPhone. Las actualizaciones opcionales del clima y de los parques contactan a sus proveedores de datos; consulta la política de privacidad para conocer esas solicitudes y cómo las procesan los proveedores.

El índice no confirma cielos despejados ni un acceso seguro. Revisa el estado actual de los caminos y del parque antes de viajar. El humo y la bruma se muestran como contexto, pero no forman parte del índice, y los pronósticos no incluyen la calidad de imagen para telescopios. Las alertas de los parques y los programas con guardaparques provienen del National Park Service y pueden no estar disponibles.

Datos meteorológicos: Open-Meteo, CC BY 4.0. Datos de calidad del aire: CAMS vía Open-Meteo, CC BY 4.0. Datos de parques: National Park Service. Nyx no está afiliado al National Park Service ni cuenta con su respaldo.

### Departures from the English draft (on purpose)

- The English draft says "Forecasts do not include smoke, haze or telescope seeing." Since commit 1945d2c, Nyx shows a CAMS smoke and haze forecast as context outside the score. The Spanish text says that, and adds the CAMS credit line. **The English description should get the same fix.**
- Opening line: "Make time for a darker sky" becomes "Dale tiempo a un cielo más oscuro", which matches the in-app caption "Dale tiempo a la noche".

### Optional paragraph (only if the release includes these features)

Add this after the widgets paragraph when "What's up tonight" and field mode ship:

> Cada noche, Nyx muestra qué hay en el cielo: el núcleo de la Vía Láctea, los planetas, los máximos de las lluvias de meteoros y los eclipses de Luna, calculados en tu iPhone para cada parque. Al llegar, el modo de campo abre una pantalla roja y oscura con los momentos clave de la noche y hacia dónde mirar.

## What's New

For the first release that ships Spanish (fill in the version):

> Nyx ya está disponible en español.
>
> En el cielo esta noche: el núcleo de la Vía Láctea, los planetas, las lluvias de meteoros y los eclipses de Luna de cada parque, calculados en tu iPhone. Nada de esto cambia el índice.
>
> Un pronóstico más honesto: Nyx compara tres modelos meteorológicos, muestra las capas de nubes, el rocío y el viento, y avisa cuando el humo o la bruma pueden ocultar las estrellas débiles.

If field mode ships in the same release, add:

> Modo de campo: una pantalla roja y oscura para la noche en el parque, con cuenta regresiva hasta la oscuridad total, hacia dónde mirar y alarmas opcionales.

Minimal version, if the release only adds the language:

> Nyx ya está disponible en español. Las horas, las distancias y las temperaturas siguen la configuración de tu región.

## Screenshot captions (if captioned frames are used)

| English | Spanish |
|---|---|
| Where the sky is darkest | Donde el cielo es más oscuro |
| A number with a reason | Un número con sus razones |
| Make time for the night | Dale tiempo a la noche |
| Find your park | Encuentra tu parque |
| Keep a little of the night | Guarda un poco de la noche |
| Room for your eyes to adjust | Tiempo para que tus ojos se adapten |

Capture the Spanish screenshots from a Spanish (Mexico) simulator so the scores, dates and caveats are real renders, as `SUBMISSION.md` requires.
