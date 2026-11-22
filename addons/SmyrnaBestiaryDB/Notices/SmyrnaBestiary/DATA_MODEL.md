# Collection and corpus contract v1

Context is M<UI-map-ID> outdoors or I<instance-ID> in a dungeon/raid. Known outdoor
floor maps can resolve to an indexed parent for browsing. Observer cells separately
retain their actual UI map/floor. Difficulty and game build partition observations.

Local arrays: 1 context, 2 NPC ID, 3 difficulty, 4 name, 5 sightings, 6 attributed loot
windows, 7 snapshot revision, 8 last seen, 9 items, 10 observer cells, 11 item-cap flag,
12 record epoch, 13 build, 14/15 minimum/maximum seen level, 16 creature type.
Item tuples contain windows-with-item and total quantity; a stack of ten counts one
window hit. Cells contain map ID, 200-yard X/Y indices and observation count.

Sampling policy: only a single public creature source across the loot window; no
source guessing from the selected target. A target name may decorate an already
confirmed source, never establish it. Missing/restricted/incomplete/multi-source
windows are excluded. Completely empty windows have no reliable source and do not
enter a creature denominator. Attributed money-only windows can enter with no items.
Gathering, skinning, pickpocket and disenchant spell contexts exclude a short window;
unrecognized ranks/timing can still contaminate samples and require live checks.

This measures item presence in the recorded subset of loot windows, not an unbiased
per-kill probability. NPC levels and player eligibility can vary within a stratum;
quest/group conditions are not fully controlled. The binomial Wilson interval shown
for a personal sample describes sampling variability, not these systematic biases.
Old and changed game builds do not silently combine.

Local record cap is 1,000 with insertion-order eviction, not an expensive LRU. Each
record holds at most 64 item types and 16 location cells. Truncated missing item types
are unknown. Recent sighting/corpse keys are bounded at 1,024 for 30 minutes and persist
across reloads; once expired/evicted, very late revisits can be counted again.
Raw mob GUIDs are not exported. No character names, chat, account identifiers, routes
or exact unit spawn coordinates are included in the export.

## Explicit export and merge

CSV rows are record, item or cell. A record snapshot is identified by originating
dataset token, context, NPC, difficulty, record epoch and build. The epoch changes
when a discarded record is recreated, preserving earlier exported history.

The SQLite importer parses CSV only, validates dimensions, bounded counters, item
hits <= windows, text sizes, row/record/item/cell limits and timestamps. It never
evaluates Lua or Python input. Replayed/older revisions are ignored. Newer snapshots
replace item/cell child rows transactionally, with decreasing counters rejected.
All SQL values are parameters; dynamic table choices are fixed internal names.

The rate view starts from every known item/source and joins all corresponding
contributors' sample windows. Missing items contribute zero hits only for untruncated
snapshots. Truncated records contribute to an item's denominator only if that item
was actually retained. Hits and window counts are summed before division; percentages
are never averaged directly. Data-source tokens are not authenticated people.

Different contributors can observe the same physical corpse. Export deduplication
does not deduplicate those cross-player observations, since no corpse GUIDs/events
are exported. Shared window counts are not guaranteed independent unique kills.

JSON exposes creatures, rates and observer_cells. Those cells are where observers
stood, not verified spawn locations. Future map visualizations must preserve that
distinction. The generated Community addon carries creature names, zone membership
and rates, keyed by area/difficulty/NPC/build. Imported community rates and your
personal sample are displayed separately, never double-added in the game UI.

Reference packs are a separate provenance layer: Forever observations from Everloot,
Classic estimates from CMaNGOS, and area/name references from QuestieDB. They are not
inserted into the personal corpus as if players had collected them. Snapshot dates,+sample sizes and incomplete coverage remain visible.

Future work: a reviewed upload service, contributor dedup/trust policy, patch-aware
freshness, capture audits, robust per-kill denominators when supported, better quest/
group condition strata, and more detailed spatial inference. No such hosted service
or official-probability guarantee is part of this prototype.
