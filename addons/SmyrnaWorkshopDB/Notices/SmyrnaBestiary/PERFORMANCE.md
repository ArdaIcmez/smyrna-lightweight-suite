# Bestiary: performance and test report

Measured locally on 2026-11-18 using Lupa 2.8 / Lua 5.1 on Windows. These are
**synthetic measurements**, not actual WoW CPU, RAM, frame-time or rendering results.
Native frames, secure UI behavior, game API latency and real message/loot timing
still need client testing. The ImageGen presentation is a concept simulation.

## Local measurements

Median of five runs, normal garbage collection enabled, os.clock(). Source parsing
and merge use a real published NPC table, with the mock personal/community samples.
Iteration counts and retained deltas are included in BENCHMARK.json.

| Operation | Median |
| --- | ---: |
| Cached mob loot lookup | 0.77 microseconds |
| Parse/merge one mob's loot sources | 41 microseconds |
| Determine current area/difficulty | 0.80 microseconds |
| Build/sort the current test-zone creature list | 0.336 ms |
| Record a loot-window summary in an existing record | 2.03 microseconds |
| Serialize a one-record export | 3 microseconds |
| Build five added tooltip rows | 14.8 microseconds |

The test-zone sort originally took 1.71 ms after adding live/community name priority.
Computing each name once before sorting reduced it to 0.336 ms in successive local
runs (about 80% lower). This comparison is directional; run-to-run noise exists.

## Memory and first-use costs

- Mocked startup Lua growth, including index/code and empty saved data: **508 KiB**.
  No reference pack or repeating timer loads at startup.
- First reference pack in the cold profile: **880 KiB additional Lua memory**.
- All eight reference packs cumulatively: **4,485 KiB additional Lua memory**.
- Own dataset with 1,000 creature/area records and five item types/cell per record:
  **1,504 KiB**. More retained item types can use more memory.
- Individual reference pack load/compile in this harness: roughly **2-6 ms wall time**.
  Real client disk, compilation, frame and engine costs are not established here.

These are isolated Lua measurements, not WoW-attributed total addon RAM. Cold memory
uses mocked frames. Loaded reference packs remain resident until reload; disabling
Classic estimates changes displayed rows, not already loaded pack memory. Several
packs may load for a zone with creatures indexed to different reference groups.
The eight-pack layout bounds the imported catalog but is not a hard RAM guarantee.
Own records have separate 1,000/64-item/16-cell bounds, plus a 1,024-key recent cache.

No additional steady-state retained growth was measured in the lookup/record loops
after GC. Temporary allocations still occur; this is not proof of no possible leak.
Only one-record export timing is measured; a full 1,000-record export can allocate
and lay out much more text. Its UI cost is intentionally explicit and not periodic.

## What costs the most

1. **First reference use:** loading/compiling a source pack is heavier than lookups.
   New loads are deferred during combat. Sources are static local files; there are
   no live web requests or scans while playing.
2. **Area list rebuilding:** source names are resolved once and reused for sorting.
   Changes to a visible browser are coalesced through one 0.2-second callback.
3. **Uncached mob loot parsing:** only the selected/hovered mob is expanded. At most
   twelve parsed results are cached. We do not parse the world's item-drop tables
   every zone change or allocate a frame for every creature/item.
4. **Own history/export:** history is bounded; export is manual and clears its text
   when closed. SQLite merging and reference rebuilding run outside the game only.

The browser reuses six creature buttons and eight loot rows. Options, export and
source windows are created on demand. The startup launcher is a small button.
No OnUpdate script, repeating ticker, background upload, addon-message flood, map
overlay or combat-log polling is added by Bestiary. Recording off unregisters its
sighting/loot/spell events. Tooltip-off hooks return immediately.

## Tests passed

- All runtime Lua modules load under Lua 5.1; TOC files/paths exist.
- No startup reference pack or repeating timer; separate current-area/instance and
  difficulty context; new pack loading deferred through combat.
- Public/hidden GUID handling, unique sighting/corpse dedup, stack quantity versus
  item-presence counts, money-only zero-item windows, empty and multi-source exclusions,
  recognized skinning exclusion, recorder off and original per-build record keys.
- Personal, reference and shared rates/provenance, small samples, Wilson interval,
  source filtering, twelve-result cache and unknown rather than fabricated drops.
- Lazy browser/options/export, repeated opening without rebuilding all controls,
  export-close cleanup, 1,000-record cap, fresh epochs after eviction, 64-item truncation.
- Validation of all 4,427 real reference entries and bounded percentages.
- 23-column CSV round trip; two simulated contributors merged into SQLite;
  repeated exports do not add counts twice; missing items contribute zero only to
  eligible denominators; generated shared-creature/rate addon loads back into Bestiary.
- All three Smyrna addons loaded together in one mock runtime: distinct namespaces
  and slash commands, map overlays off by default, Diary and Bestiary independently
  record one window, and Chat nickname formatting still works.

These mocks do not verify game-engine frame templates, actual addon-load ordering,
tooltip restrictions, localization, gathering spell ranks, live event ordering,
group/AoE capture accuracy or real client rendering. Follow README.md's smoke tests
before relying on the data as an accurate measurement of the game.

## Actual-client profiling

Run `/sb perf` after login, after a first hover/open, and after several different
zones. Its memory report includes the main addon and loaded reference modules.
Observe recording, browser open/closed and source options separately. Normal GC
can later reduce snapshots; do not force recurring collections.

For CPU, `/console scriptProfile 1`, restart, record `/sb perf`, play normally for
five timed minutes, record again. CPU delta / 300000 * 100 gives the share of elapsed
time attributed to that addon, not game CPU or FPS. Profiling adds overhead. Finish
with `/console scriptProfile 0` and restart. Native/global memory attribution and
hooks are approximate; watch the whole UI as well as a single addon counter.

## Next performance choices to discuss after testing

- Fewer/optional reference packs versus immediate coverage of more areas.
- A separate small Forever-only catalog if reference memory matters more than Classic coverage.
- A lower own-history/item cap for long sessions, with regular explicit exports.
- Paginated exports if a real full-history editor causes stalls.
- Incremental creature-list changes if observed source changes are frequent.
- A reviewed update service later; the current offline merger makes no network calls.
