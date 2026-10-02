# Performance evidence — October 2, 2026

Measured on the shared M1 Mac, 16 GB, Xcode 27.0. These are simulator/development observations, not hardware acceptance results.

## Native launch and navigation

`NyxUITests` uses Apple's `XCTApplicationLaunchMetric(waitUntilResponsive: true)`, verified in the installed XCTest header: first frame **and** main-thread responsiveness. Three measured launches follow a discarded warmup. The test runs Debug, an offline in-memory journal and a Reduce Motion review override. It does not represent production disk loading, network updates, a cold device reboot or on-device Release performance.

| Simulator | Mean | Individual runs |
|---|---:|---|
| iPhone 17 Pro / iOS 26.5 | 2.179 s | 2.136, 2.251, 2.151 s |
| iPhone 18 Pro / iOS 27.0 | 3.756 s | 3.732, 3.693, 3.842 s |

Both native tests also navigate all five tabs successfully. Full structured test/build evidence is in `test-26.json` and `test-27.json`: 15 Swift Testing tests + 2 UI tests, zero failures and zero build/analyzer warnings on each runtime. Earlier loaded runs averaged 2.635 s on iOS 26 and 5.287 s on iOS 27, with one run varying from 2.82–7.02 s. The final warm-cache result is not a guarantee. The slower iOS 27 launch requires on-device Release investigation before performance sign-off. No app splash timer blocks input; the post-paint reveal is decorative and skipped with Reduce Motion.

## CPU and hangs

A complete 15.794-second Time Profiler capture ran the iOS 26.5 detail screen, offline, with decorative animation active and no relaunch during recording. There were zero recorded hang events above the instrument's 250 ms threshold. Statistical samples attributed 3.571 CPU-seconds to Nyx across threads, 1,853 of 3,571 samples on the main thread. This is roughly 22.6% of one core averaged over that short trace, not a frame-rate or energy measurement. Most sampled leaf work was graphics convolution/interpolation. No scrolling, scrubbing, photo stress or AI was exercised in this trace. `profile26.json` contains the Nyx-specific summary.

Optimized on-Mac pure astronomy/scoring computed all 63 parks × 14 nights (882) in 0.209 s in the earlier run and 0.322 s under instrument load, checksum 78,957. `Scripts/benchmark.swift` contains the reproducible build/run commands. Device timings and UI scheduling differ. Bulk reminder calculation now runs in a detached utility task rather than holding the UI actor.

## Allocations and invalid attempts

A 15.686-second Allocations capture attached by numeric PID to Nyx and saved successfully. Xcode 27's export table inventory did not expose allocation lifetimes/statistics; the raw trace is kept locally under `Research/Traces/` for Instruments inspection. Allocation growth and leak absence are **not certified**. Raw recordings are Git-ignored because they are large and the all-process trace includes unrelated local process metadata.

The first profiler trace ended after 0.69 s when a capture script relaunched its target: invalid. App-path/name launch resolution was ambiguous with the widget extension; exact bundle ID resolved it. A separate App Launch capture had input-binding warnings and zero exported lifecycle rows: invalid timing evidence, replaced by the native XCTest metric above. The initial iOS 27 simulator service/install stall also supplied no app-performance evidence.

## Budgets and remaining gates

88 star particles; 12 gauge particles; 20 Hz decorative timelines; 160 moon strips; 65 samples per sky path. Low Power Mode and Reduce Motion pause decorative animation. These are source budgets, **not proof of 60/120 fps**.

Before release, use a signed Release build on supported iOS 26/27 hardware and the oldest supported phone. Measure cold/warm launch, scroll and scrub hitches, journal photos, AI streaming, memory growth, thermal behavior, Low Power Mode and real refresh rate. Tune haptics and dark-field readability with people. Follow `AUDIT.md`; neither the final 3.76-second result nor the earlier 5.29-second run establishes instant app readiness.
