# Performance measurement — 22 November 2026

Installed build: 0.9.30.4. Read-only Lua 5.1 simulation of installed source, retained heap after full GC. No personal SavedVariables read. These are not native WoW memory attribution, frame times or total Suite RAM. Engine widgets, real feature indexes and gameplay event rates are not simulated completely.

## Database check

Bestiary packed references: approximately 2.88 MiB retained; Workshop: 0.62 MiB. Remembrance's storage loader alone is under 1 KiB; player data is separate. Loading these reference files took approximately 15 ms and 4.5 ms respectively on this machine.

Forcing all eight loot blocks through the actual decoder retained approximately another 2.59 MiB; all twelve recipe blocks another 2.00 MiB. Registration consumers in this test retain the decoded tables but do not build production feature indexes. This is a stress case, not proof all blocks load during normal play. Packed references still occupy memory before decoding; load-on-demand is not unloading.

## Field Diary check

Actual Core.Insert stays bounded at 2,000 own + 2,000 shared records after one million unique inputs. Retained store: approximately 2.33 MiB with one item total per record. One million insertions require approximately 3.3 seconds of aggregate CPU work; they are not a normal gameplay burst.

At the cap, actual Core.Aggregate takes approximately 6–8 ms per forced rebuild. Follow-up review verified that production NS.Areas already has a two-map revision cache. Regression tests confirm unchanged queries reuse the same groups and revision changes rebuild them. This raw timing is not normal idle/refresh cost.

## Chat check

Reran the native PackageEntry/circular-buffer model using unique 180-byte messages. Full buffers per chat window: 10x / 1,280 messages ~0.98 MiB; 50x / 6,400 ~4.87 MiB; 100x / 12,800 ~9.74 MiB; 1000x / 128,000 ~96.40 MiB. Secure numeric wrappers are mocked. History's joined editor buffer and native text layout are additional costs. Filling capacities is different from allocating the whole capacity immediately.

History test: 650 messages, native template handlers retained, wheel clamping, text unchanged on scroll and cancellation on close passed. Native mouse selection and rendering still require gameplay confirmation.

## Remembrance check

Actual PackRecord with unique player keys: 100,000 players ~21.56 MiB, one million ~199.46 MiB. Includes names, first/last timestamps, map, level and location in each record, excludes activities, history and UI. At those sizes 100,000 hash lookups took ~69 / 81 ms, including construction of lookup strings. Bulk construction took ~2.1 / 26.5 seconds. Normal encounter additions are incremental; login validation of enormous stores needs a separate native test.

## Development-only Upgrader/AH check

Not included in installed 0.9.30.4. New modules + shared equipment reference in mock runtime: ~4.45 MiB; after one slot recommendation ~5.10 MiB. Slot recommendation: 13.3 ms total work, spread across scheduled batches in production. One million quote rows aggregate into 5,000 items using ~0.74 MiB retained, ~414 ms total. Optimized quote field projection: 5.69 ms per 100,000 versus 195.4 ms for full row decoding. 2,900 arithmetic parity fixtures and all 20 unit tests passed.

## Priorities and native follow-up

1. Preserve the existing Diary map/revision cache; route new consumers through NS.Areas rather than rebuilding unchanged groups directly.
2. Preserve lazy DB decoding; measure production indexes and transient GC peaks in game.
3. Keep chat retention moderate for low-memory setups; huge selectable editor buffers may stall native layout despite batched message extraction.
4. Benchmark Remembrance activities separately before estimating a large long-lived player's complete record.

No justified overall FPS/idle CPU claim is available from these simulations. Native follow-up: reload, note `/sc perf`, open each feature once, repeat tooltip/history interactions and note memory again after settling. Native CPU profiling must be enabled deliberately and compared with the same gameplay flow; it adds profiling overhead.

Raw installed-source results: PERFORMANCE-2026-11-22.json. Development results: UPGRADER-0.9.31.json. Chat model: dated workspace outputs/reports/CHAT-RETENTION-MEMORY.json. Reproduce installed DB/Diary/record checks with `python tools/benchmark_installed.py` (requires Lua 5.1 Lupa runtime).
