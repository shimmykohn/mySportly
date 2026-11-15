# Instant launch — measurements

Numbers only. No channel names, URLs or credentials.

## Mac benchmarks (2026-11-08)

Release build (`swift test -c release`, `SPORTLY_BENCHMARK=1`), synthetic workload of 57,033 channels and 220,500 listings, on the development Mac. Device timing will differ.

| Stage | Before | After `StableID` fix |
|---|---|---|
| `ChannelDirectory` (total) | 12.1 s | 5.9 s |
| ↳ `CatalogGroupIndex` | 9.2 s | 2.8 s |
| ↳ metadata resolve | 2.1 s | 2.1 s |
| ↳ localized sort | 0.45 s | 0.45 s |
| `GuideMappingResolver` | 0.86 s | 0.89 s |
| `CatalogQueryIndex` | 2.07 s | 2.08 s |
| Full `PreparedCatalog` | 15.9 s | 9.2 s |
| `StableID.hash` × 57,033 | 1.55 s | 0.04 s |

Catalog file decode: JSON 1.24 s (75 MB), binary property list 2.20 s (31 MB). JSON was kept (`CatalogCodec`).

A sampling profile after the fix shows no single dominant function. What's left is string work spread across the metadata and grouping rules.

## Simulator, real catalog (2026-11-08)

iPhone simulator (iOS 27.0) on the development Mac (8 GB RAM), Debug configuration with `SWIFT_OPTIMIZATION_LEVEL=-O`. Catalog: 56,705 channels and about 107,600 listings after pruning. Files: sealed catalog 77 MB, launch snapshot 162 KB (300 channels), saved stages 13.8 MB.

**Timer anchor.** Since `d771b93`, `processStart` is the kernel's process start time (`sysctl` `p_starttime`). Before that it was the moment `AppStore` was created, which hid process creation, dyld, and SwiftUI graph setup. Earlier simulator numbers in commit messages (≈0.5 s) used the old anchor.

**Accessibility automation.** The simulator-control tool and XCUITest turn on `ApplicationAccessibilityEnabled`. With it on, `storeCreated` alone took 2.5–7 s. A sampling profile of that time: 55% UIKit loading accessibility bundles, 31% Swift protocol-conformance lookups during SwiftUI graph setup. Both are much cheaper on a device (no VoiceOver, prebuilt conformance tables), so the rows below turn it off to match a typical phone.

| Launch (accessibility automation off, load average < 6) | Process start → Home interactive |
|---|---|
| Warm, from snapshot (5 runs) | 699, 707, 747, 808, 1,139 ms (median 747 ms) |
| First after a settings change | 3,045 ms |

| Full catalog, `catalogDecoded → catalogPrepared` (alternating pairs) | Without saved stages | With saved stages |
|---|---|---|
| Run 1 | 10.95 s | 8.36 s |
| Run 2 | 11.42 s | 8.37 s |
| Run 3 | 10.91 s | 8.49 s |
| Run 4 | 11.55 s | 8.37 s |

Catalog decode (`snapshotLoaded → catalogDecoded`): 0.85–0.95 s. Memory: `phys_footprint` peak 455 MB, 375 MB once prepared.

`LaunchBudgetUITests` on the simulator: **failed**, 6,689 ms against the 1,500 ms budget. The run has accessibility automation on (XCUITest always enables it), so this is not representative of a phone. The first run did not parse `launch-ms=` because SwiftUI formatted the localized value as `1,234`; fixed with `Text(verbatim:)`.

Outliers excluded: runs during macOS daemon load spikes (load average 10–114) and two simulator reboots under memory pressure gave 15–30 s launches.

## Task 8 decision: adopted

- Prepare is ≥ 5 s: 11.2 s on the simulator; a phone is expected to be slower.
- Decoding is ≥ 2× faster than computing (release build, Mac, synthetic 57k channels): metadata 0.16 s vs 2.2 s, guide matches 0.003 s vs 0.88 s. Full prepare 10.1 s → 7.0 s with saved stages.
- Implemented as `PreparedStages` (`b880168`). Each part is reused only when a SHA-256 of exactly the inputs its resolver reads matches, and it is recomputed and saved otherwise.

What remains in prepare: `CatalogGroupIndex` ≈ 3 s and `CatalogQueryIndex` ≈ 2.1 s on the Mac.

## Known gap

Before the full catalog is ready, Live shows only Choose Interests, All Channels, and Organize Channels. Categories appear when the catalog is prepared, about 8–10 s after launch on the simulator. The launch snapshot does not carry categories. Home (redesign sub-project 2) replaces this screen; its first rows should come from snapshot data.

## Device measurements

Pending: iPhone and iPad were not connected during this session.

- [ ] `[Launch]` summary line, first launch after update (no snapshot yet)
- [ ] `[Launch]` summary line, second launch (from snapshot)
- [ ] `LaunchBudgetUITests` result, iPhone and iPad (`-O` build)
