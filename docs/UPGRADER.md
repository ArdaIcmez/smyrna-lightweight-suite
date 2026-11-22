# Upgrader — 0.9.31 private test build

Press C, hover equipment and Ctrl + left-click for up to ten ranked upgrades. Bags and linked equipment use the same service. Details offer All upgrades and AH upgrades (confirmed BoE only). Settings are under the Suite Upgrader tab or /su.

Rank by max(item requirement level, source level), then source level, stat score descending and item ID. Sources: dungeon, quest, profession, world drop. Known class/faction/level restrictions, completed nonrepeatable quests, unique paired items and incompatible armor are filtered. Weapon recommendations keep the current one-hand/two-hand configuration. Quest chains, keys, lockouts and learned weapon skills are not fully modelled.

No Pawn dependency: attributed Pawn 2.14.8 arithmetic and 29 Forever profiles are imported into PrivateScoring. Scores use reference base stats, excluding complete treatment of enchants, random suffixes, procs and set effects. Percentages are score differences, not predicted DPS/healing. Automatic profiles use talent points; explicit profiles are selectable. Private owner/two-guildmate research build only; preserve notices and hashes.

SmyrnaEquipmentDB owns 11,525 equipment records plus slot/proficiency/source indexes. Other Suite features consume Suite.Equipment.Ensure/Get/Candidates/Eligible. Packed data loads on demand; decoded cache is bounded to 256 entries. Recommendation caches separately retain their top candidates. Scoring runs 32 relevant candidates per scheduled batch. Duplicate Bestiary equipment-name rows were removed; loot relationships remain in Bestiary.

Data uses pinned Forever knowledge-base exports (client build 1.60.1.71037). Classic loot/stat fallbacks are labelled and incomplete. Input hashes/provenance are in the Equipment MANIFEST.json. Required level is not verified dungeon access. Unscoped zero-level containers are excluded when progression cannot be established.

At an AH, click Scan AH for these upgrades, or /sah. Replicate scans have a 15-minute local cooldown, 30-second timeout, 200,000-row limit and 8,192-item quote cap, reserving requested items. Processing batches 150 rows; cancellation preserves previous quotes. Up to eight realm/faction/house contexts retain one snapshot each. Quotes are asking prices; random suffix variants may be combined by item ID. Native item search is user initiated; purchasing remains in Blizzard UI.

Build: refresh an immutable Pawn snapshot with tools/addon_sources.py, run tools/build_equipment_dev.py against pinned .local/equipment-input exports using Lua 5.1 Lupa, then tools/package_suite.py. The source watcher captures new upstream versions; it does not automatically promote runtime files. A new snapshot must be rebuilt/tested before packaging. --install targets an explicit Interface/AddOns directory and leaves WTF untouched.

25 unit tests cover scoring without Pawn, restrictions, hover baseline, cache invalidation, AH tabs/limits/cancellation, loot guards, Diary caching and class-specific defenses. 2,900 imported arithmetic parity fixtures also pass. Native hover/Ctrl-click, AH actions, layout and mouse selection still need gameplay confirmation.
