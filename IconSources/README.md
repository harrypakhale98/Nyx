# Nyx icon layers

The shipping icon is the Icon Composer document `Nyx/Resources/AppIcon.icon`. Xcode compiles it into the asset catalog (`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`). The SVGs here are the same layers, kept for editing:

- `Disc.svg` — the moon's unlit disc (earthshine), a glass layer.
- `Moon.svg` — the lit crescent, a glass layer above it.
- `Orbit.svg` — a thin amber orbit with one amber "star particle" and a few starlight dots, echoing the celestial gauge. Not glass.

The background is the document's own fill: a linear gradient from nebula violet `#2A1B4E` to void black.

## Preview from the command line

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  Nyx/Resources/AppIcon.icon --export-image --output-file /tmp/nyx-icon.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
```

Renditions: `Default`, `Dark`, `TintedLight`, `TintedDark`, `ClearLight`, `ClearDark`. Check the crescent stays recognizable at 60 px.

## Editing

Open `AppIcon.icon` in Icon Composer (Xcode → Open Developer Tool → Icon Composer) to adjust glass, translucency or lighting; save in place. No project change is needed.
