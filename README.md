# Smyrna Lightweight Addon Suite

Current private build: **0.9.35**. Hold **Ctrl while hovering character gear** for Dungeon, Quest (!) and AH circles with scrollable top-ten lists. Ctrl+left-click opens details. [Coverage/menu update](docs/RELEASE-0.9.35.md) adds WoWSims Forever data, future level/training markers, icon cards and a charcoal/gold theme. [Hover fixes](docs/RELEASE-0.9.34.md), [compatibility notes](docs/RELEASE-0.9.33.md) and [storage contracts](docs/STORAGE.md) describe prior work. Earlier sections describe their respective baselines.

## 0.9.31 private test build

Upgrader is integrated into the Suite with one optional shared Equipment DB. Press C, hover gear, then Ctrl + left-click for ranked upgrades; select a profile in the Upgrader tab if automatic talent selection is unavailable. At an AH, scan listing prices and use each confirmed BoE item's search button. Pawn is not required. This experimental scorer is private owner/two-guildmate research, with original notices retained; do not publish this build publicly.

This build includes the loot interaction fix, native scrollable/selectable History without page controls, and class-specific Bestiary defense estimates. Automated checks pass; native input, AH actions and rendering still require gameplay confirmation. See docs/UPGRADER.md, docs/ENGINEERING.md and reports/PERFORMANCE-2026-11-22.md for scope, unfinished work and measured limits.

Development baseline: **0.9.28** for WoW Forever.

## Packages

- `addons/SmyrnaSuite`: core, Chat, Field Diary, Bestiary, Workshop and Remembrance UI.
- `addons/SmyrnaBestiaryDB`: optional packed creature/loot references and Classic defense references.
- `addons/SmyrnaWorkshopDB`: optional recipe and item-acquisition references.
- `addons/SmyrnaRemembranceDB`: optional personal encounter storage loader; no player history is included here.

Third-party data attribution and licence files remain inside their respective packages.
The source folders contain addon code and bundled reference data, not game SavedVariables.

## Work in progress

1. A Python Bestiary data updater with validation, candidate releases and rollback.
2. Workshop market information: explicit AH scanning, material/recipe/output listing prices, crafting costs and estimated margins.
3. Community contribution imports and validated weekly database releases.

These items are planned; this baseline does not implement them.
Auctionator's installed code is not included. Its licence lists All Rights Reserved.

## Releases

`v0.9.28` identifies the baseline. New source changes and DB snapshots will be versioned independently.
Generated ZIPs and local configuration are excluded from source commits. Releases will contain checked installable packages.

## 0.9.30 message editor

Restores the user-confirmed configuration 1 native text input. X and resize controls stay outside the text area. Single-message scrolling is deferred while confirming mouse selection; history remains scrollable. `/sc selecttest` opens the five-way diagnostic if needed.
