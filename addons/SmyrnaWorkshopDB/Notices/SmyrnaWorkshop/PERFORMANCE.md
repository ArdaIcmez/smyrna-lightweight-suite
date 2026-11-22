# Workshop performance and verification

Mocked Lua 5.1 measurements, not live WoW profiling. Native frame/tooltip allocations are not accurately represented.

| Operation | Measurement |
| --- | ---: |
| Cached material lookup | 0.025 microseconds/call |
| Two-ingredient readiness | 0.217 microseconds/call |
| Unrelated item hover | 0.107 microseconds/call |
| Load/index 130 Cooking recipes | 0.638 milliseconds |
| Mock startup heap increase | 169 KiB |
| Startup plus Cooking | 281 KiB |
| Startup plus all nine databases | 2,507 KiB |

Hot operations: inside Lua, 100,000 calls per run, median of seven runs. Heap: after garbage collection, relative to the UI mock baseline. Cold load excludes disk IO. Results vary by machine/client.

Database tables are the heaviest part. A material shared by several professions can load several packs on first hover, rebuilding the index for each. If live profiling finds a hitch, batching those rebuilds is the next useful optimization. Disabling packs releases them after reload; an enabled pack still stays unloaded until a matching material is hovered.

No idle ticker, bag scan, combat-log capture, network traffic or permanent OnUpdate. Only dragging an icon uses OnUpdate. Bag changes invalidate count caches. Profession events coalesce over 250ms; the scanner never changes filters or expands headers. Capture skips ambiguous alternative/currency reagents and preserves complete old records when item data is missing. Own recipes are capped at 3,000. Tooltip work is capped at 50 matching recipes inspected, five displayed and six ingredients each. Disabled pack load failures cache for the session; first loading waits until outside combat.

Tests passed: actual Stringy Wolf Meat resolves to unlearned Charred Wolf Meat; have/need counts; bank exclusion; recipe filters; secret link guard; lazy profession loading; repeat-hover cache; disabled pack cache; all nine generated files compile; event coalescing; incomplete-data protection; legacy/modern capture; ambiguous alternatives excluded; reusable UI; Suite controls and four-feature coexistence. Chat/Diary/Bestiary regressions pass. Real Forever API/UI compatibility and live performance remain untested.

0.1.2 review: seven-pack first lookup now rebuilds once instead of seven times. Measured median 16.266 ms -> 13.044 ms (19.8% less time); memory remains about 2.2 MiB. See ../SMYRNA-ADDON-REVIEW.md and ../SMYRNA-INTERNAL-BENCHMARKS.json for scope and fixtures.
