# Upgrader — requested design, not yet implemented

When the player opens Character (C) and hovers an equipped slot, show a compact next-upgrade recommendation for each supported source: Dungeon, Crafted/profession and World drop (creature/container/BoE where verified).

## Shared equipment ownership
SmyrnaEquipmentDB is the proposed optional shared reference package. It owns finite equipment metadata and acquisition references consumed by any Suite module. Do not copy equipment tables into Upgrader, Bestiary or Workshop. Audit existing item name/quality/source fragments and migrate applicable equipment records through an adapter while preserving non-equipment material data. Keep source licences and distinction between Forever observations and Classic references.

## Scoring
Pawn is OPTIONAL. The owner requests private optimization experiments and an installed-folder source link, with two guildmates as testers. tools/addon_sources.py captures original, attributed local snapshots and detects version or same-version file changes. Installed Pawn should be used live when available; a standalone scoring adaptation and equivalence tests are still pending. Snapshot capture does not itself implement the fallback or prove compatibility. Preserve upstream copyright/licensing; a private repository is not a blanket redistribution exception. Do not publicly release experimental adaptations without reassessing the specific licence terms.

The installed Pawn README is CC BY-NC-ND 3.0; its current ClassicHawsJon.lua identifies the Forever weights as curated by HawsJon. Do not describe these weights as an established open-source Icy Veins dataset.

Do not guess a Holy/Ret or other spec from the spells the player uses. Prefer explicit selected profile/Pawn scale and offer manual selection. User needs usable upgrades at their level; exclude known class/faction/slot/level restrictions. Compare the hovered slot, including correct ring/trinket slot. Two-handed changes require loadout-aware treatment; do not compare two hands as a single ordinary slot. Stat weights do not fully value trinket procs, set bonuses or encounter-specific effects.

## Source and progression rules
Recommend accessible positive upgrades, not merely the highest-level item in the catalog. Define and display the ranking policy (e.g. earliest eligible source, then improvement). Required item level does not prove dungeon accessibility. Keep verified dungeon entry level, faction restrictions and source provenance distinct from estimates. Missing metadata should be omitted or explained, never fabricated. Crafted items can be sourced from another crafter; distinguish obtaining an item from personally meeting recipe/skill requirements.

## Performance and acceptance
No full-catalog scoring on tooltip hover. Index by equipment slot/requirements; request uncached item information in bounded batches and handle unavailable data without infinite retries. Bounded score caches must invalidate for gear, player level, selected profile, Pawn settings/version and reference revisions. Test empty slots, both ring/trinket slots, weapon configurations, unknown/unusable items, Pawn present/absent and asynchronous item availability. Native hover and source accuracy need in-game confirmation.
