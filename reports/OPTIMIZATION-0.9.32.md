# 0.9.32 before/after measurements

Compared with v0.9.31.1 in fresh Lua 5.1 VMs on the same machine. Values are retained heap after GC and synthetic CPU timings, not native WoW RAM/FPS. Reference measurements exclude decoded feature indexes and personal saved data. Upgrader measurements include its mocked UI/module environment. Do not add overlapping rows together to claim total Suite memory.

| Scenario | Before | After |
|---|---:|---:|
| All packed optional references + shared data service | 7.62 MiB | 6.68 MiB |
| Equipment/Upgrader/AH loaded modules | 4.38 MiB | 3.46 MiB |
| Above, after one chest recommendation | 5.02 MiB | 4.02 MiB |
| Learned Workshop recipes + index, 3,000 recipes | 3.18 MiB | 1.33 MiB |
| Installed code/reference/assets/notices on disk | 8.25 MiB | 7.01 MiB |
| One Paladin chest recommendation, total simulated work | 12.76 ms | 7.07 ms |
| Candidate/current-item scoring calls in that scenario | 301 | 113 |
| Repeated cached hover, mean | 0.039 ms | 0.040 ms |
| Append 10,000 activity events | 292 ms | 7.36 ms |

Warm hover is approximately unchanged, with a small increase from the new filters/menu work. Cold improvement includes the narrower default armor policy, not merely an equivalent unfiltered search running faster. All 11,525 catalog records and acquisition facts remain available. An explicit option restores lighter wearable armor to the search.

New activity ingestion: 100,000 events took ~78 ms, retaining ~1.94 MiB; one million took ~1.39 seconds, retaining ~20.43 MiB. The old quadratic append was compared at 10,000 events only, not one million. No claim is made that rendering a million-event history is fast.

Reference details: Equipment DB retained contribution falls from ~4.09 to ~3.13 MiB in the combined reference-load scenario. Bestiary (~2.8 MiB) and Workshop (~0.62 MiB) finite references are largely unchanged. Bestiary now avoids loading Equipment DB just for an unknown loot name. Diary's existing bounds/cache and Remembrance player records are unchanged; their previous memory figures are not reductions delivered by this patch.

Chat: a new/unset preference uses 10x rather than 50x. Prior native-buffer simulation estimated ~0.98 vs ~4.87 MiB per full window for 180-byte messages. This is a default-policy difference, not a new message-compression algorithm. Explicit 50x/100x/1000x choices are retained. Native editor layout and the joined History string still add memory/work.

Guild growth is bounded for new keys without discarding existing observations. Once a new-entry/item/guild budget is reached, whole samples are skipped; this is a retention tradeoff, not lossless unlimited compression. Legacy migration preserves old data even above the budgets.

33 regression tests pass. Source pooling compares every source row against the previous tag. Workshop offline lookup, event migration, guild denominators, all class armor tiers, trained weapons, source menus, chat assembly, scroll clamps and existing loot/AH behavior are covered. Package validation checks Lua syntax, TOCs, versions and ZIP CRC. Native menu appearance/mouse input and live CPU/FPS remain to be checked after reload.

Reproduce with `python tools/benchmark_optimization.py`; raw results are in OPTIMIZATION-0.9.32.json. Requires git tag v0.9.31.1, Lua 5.1 Lupa and the ignored baseline archive. The pre-migration on-disk Smyrna saved-data backup is kept privately in .local/saved-backups and excluded from Git and release ZIPs.
