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

## Device measurements

Pending: iPhone and iPad were not connected during this session.

- [ ] `[Launch]` summary line, first launch after update (no snapshot yet)
- [ ] `[Launch]` summary line, second launch (from snapshot)
- [ ] `LaunchBudgetUITests` result, iPhone and iPad (`-O` build)
- [ ] Task 8 gate: if device `catalogDecoded→catalogPrepared` is ≥ 5 s, evaluate persisting metadata and group-index stages
