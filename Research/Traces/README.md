# Local Instruments recordings

The `.trace` bundles are deliberately ignored by Git: the all-process capture includes unrelated local process metadata, and raw recordings are large. They are saved in this working directory for the owner's Instruments review, not bundled with Nyx. Only a Nyx-specific statistical summary is committed in `Research/profile26.json`.

- `nyx-all-profile26.trace`: 15.794 s, iOS 26.5 detail/offline, animations active, no relaunch during capture. Time Profiler and >250 ms hang detection. No scrolling or scrubbing exercised.
- `nyx-alloc26.trace`: 15.686 s attached by PID to Nyx. Allocations captured; this Xcode version exposes no allocation tables through xctrace export. Inspect growth/lifetimes in Instruments; no leak-free claim has been made.
- `nyx-launch26.trace`: App Launch recorded, but lifecycle export contained zero rows and instrument binding warnings. Not valid first-frame timing evidence. Use the native XCTest launch metric in `NyxUITests` instead.

Reproduce the first two after booting/installing/launching the Debug app, and let the trace finish saving before export. For Allocations pass the numeric PID from `simctl launch`. For App Launch pass the exact bundle ID `com.harrypakhale.nyx`; Xcode's resolver treated the app path/name as ambiguous with its widget extension.

```sh
xcrun xctrace record --template 'Time Profiler' --device SIMULATOR_UUID \
  --all-processes --time-limit 15s --output /tmp/nyx-profile.trace
xcrun xctrace record --template 'Allocations' --device SIMULATOR_UUID \
  --attach NYX_PID --time-limit 15s --output /tmp/nyx-alloc.trace
```

Raw capture and a short idle trace do not establish hardware frame rate, field usability or absence of memory leaks. Complete the device procedure in `AUDIT.md` before release.
