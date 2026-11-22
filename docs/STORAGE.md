# Data ownership and storage contracts

The Suite owns common services; optional packages own finite references. Equipment facts have one owner, SmyrnaEquipmentDB. Bestiary owns loot relationships and observations; Workshop owns recipe relationships, learned facts and ingredient indexes. Field Diary owns gathering aggregates; Remembrance owns encounters/activities. Chat uses WoW's native session buffer, not a persistent message archive. Market owns listing snapshots, not sales history.

| Service | Persistence | Runtime bounds |
|---|---|---|
| Equipment | Bundled packed records/source pool; no personal item catalog | 256 decoded items, 512 decoded source objects; per-slot character candidate IDs; top-ten source lists per slot |
| Workshop | Character packed learned-recipe fallbacks/settings | 3,000 learned recipes; twelve decoded ingredient-use lists; profession references decode as required |
| Bestiary | Account personal/guild observations; optional loot/defense references | 1,000 personal records, 64 items/16 locations per personal record, twelve merged-drop results |
| Guild samples | Inside Bestiary saved data | New data: eight guilds, 4,096 keys/guild, 256 items/key, 8,192 recent GUIDs/guild; existing legacy data is not deleted |
| Field Diary | Account personal/shared cell observations | 2,000 cells each; two cached map aggregations; 30-day prune policy |
| Remembrance | Character encounter/activity data in optional storage package | No player/activity count cap; append chunks bound copying, not total retained history |
| Chat | Account settings; messages session-only in native windows | 10x default; explicit 50x/100x/1000x supported; editor adds text/layout allocations |
| Market | Account scoped AH snapshots | Eight contexts, 8,192 quoted IDs/context, 200k scan rows, batches of 150 |

Decoded result objects can retain source rows beyond a cache's eviction, so a cache limit is not an exact object-count or memory limit. Load-on-demand does not unload packed reference strings after loading. Disabled features are not a guarantee that already loaded references/saved records disappear before reload.

Equipment pool rows are immutable shared objects. Do not mutate source fields inside UI/scoring consumers. Character candidate selection filters by slot, required level, class armor/proficiency before scoring; source rows decode only for positive upgrades. Ranking maintains bounded top-ten lists by earliest eligible level/source, then score; it does not sort the whole item catalog on hover. AH buying accessibility is separate from original source accessibility.

Keep learned recipe fallback facts when compacting: ID-only persistence would break disabled-reference/offline behavior. Activity append/iteration must accept both legacy strings and new chunks. Existing first-seen data must survive any migration. Never serialize decoded UI caches, publish player data or treat community copies as independent observations.

Use tools/benchmark_optimization.py and the unit tests before changing these formats. Memory reports must distinguish disk bytes, Lua retained heap, native engine allocations and personal saved-data growth.
