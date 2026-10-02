# Nyx icon layers

The app currently includes an original 1024×1024 PNG in `Nyx/Resources/Assets.xcassets/AppIcon.appiconset`. The SVGs here separate Background, Moon, and Orbit on a 1024×1024 canvas. No borrowed imagery or logos are used.

Final Liquid Glass export is an owner step in Icon Composer.

1. Open Xcode → Open Developer Tool → Icon Composer (or the installed Icon Composer app).
2. Create an iOS icon named **AppIcon**. Import Background.svg as the background, Moon.svg above it, Orbit.svg as the shallow foreground accent. Keep the supplied positioning and generous margins.
3. Give Moon a restrained glass material; keep the background opaque and dark. Keep Orbit low contrast and avoid a glow that erases the crescent at small sizes. Preview Default, Dark and Tinted appearances and multiple lighting directions.
4. Save the native `.icon` document. Add it to Nyx's synchronized source folder as `AppIcon.icon`; resolve the existing AppIcon asset name conflict using Xcode's current Icon Composer integration instructions. If project settings must change, edit `project.yml` and regenerate with XcodeGen.
5. Build both simulator versions and a signed device archive. Confirm the crescent remains recognizable at Home Screen and Spotlight sizes. Recapture store images after finalizing it.

The PNG is a functional fallback, not a claim that the native Icon Composer export has been completed. Layer depths/material choices need a visual judgment in the actual tool. Do not fabricate an `.icon` bundle or hand-edit the Xcode project.
