# Nyx icon layers

The shipping icon is the Icon Composer document `Nyx/Resources/AppIcon.icon`. Xcode compiles it into the asset catalog (`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`). The SVGs here are the same layers, kept for editing:

- `Arc.svg` — the score dial: a faint full track and the amber arc at 88%, drawn as three strokes (wide soft glow, mid glow, bright core). Not glass, so it stays luminous.
- `Star.svg` — the dial's leading star with its amber halo, plus four starlight dots. Front group.
- `Moon.svg` — the lit crescent, shaded as a sphere (radial gradient toward the lit limb), with faint maria and a soft terminator. Glass.
- `Disc.svg` — the unlit disc with earthshine, a soft radial gradient. Glass, grouped with the moon.

The background is the document's own fill: a linear gradient from nebula violet `#2A1B4E` to void black. Groups run front to back: leading star, arc, moon; the system adds depth and specular highlights between them.

Earlier concepts (the original moon-and-orbit icon, the Milky Way "Horizon" draft) and a comparison sheet live in `Concepts/`.

## Preview from the command line

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  Nyx/Resources/AppIcon.icon --export-image --output-file /tmp/nyx-icon.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
```

Renditions: `Default`, `Dark`, `TintedLight`, `TintedDark`, `ClearLight`, `ClearDark`. Check the crescent stays recognizable at 60 px.

## Editing

Open `AppIcon.icon` in Icon Composer (Xcode → Open Developer Tool → Icon Composer) to adjust glass, translucency or lighting; save in place. No project change is needed.
