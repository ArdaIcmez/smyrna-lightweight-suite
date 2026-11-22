# Smyrna Lightweight Addon Suite

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
