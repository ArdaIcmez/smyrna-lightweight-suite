# 0.9.35 — Forever coverage, next upgrades and menu presentation

## Equipment data

Manascale Treads is item 273042, Mail feet, required level 28, Strength 7, Intellect 7, Armor 157 and CritRating 7. WoWSims Forever contains its baseline and Mana Devourer source. Icy Veins' own item page independently confirms its name/identity/stats: https://db.icy-veins.com/wow-forever/items/273042 . No changing observed drop percentage was imported.

Source: https://github.com/wowsims/forever , MIT. Added 1,155 supported missing equipment records, bringing the shared catalog from 11,525 to 12,680. Replaced 4,097 explicitly Classic-estimated records with WoWSims Forever base stats. Existing verified records and old source rows are preserved. Binding is absent in this export: new rows do not become AH candidates merely because they have a drop/craft source. Manascale's BoP is independently established. Unmapped/non-equipment entries, unknown phases and unverified profession requirements are not promoted into usable recommendations.

Algae Fists 6906 was previously Strength 10/Stamina 4 from a Classic estimate. The Forever supplement gives Strength 8/Stamina 5/Nature resistance 5. In the level-37 Ret regression scenario its Dungeon list contains Stormgale Fists and Scarlet Gauntlets; its Quest list contains Warsong Gauntlets and Fists of Impending Doom. Source accessibility/completed quests/profile selection can change results. These are reference recommendations, not a claim that quest prerequisites or entry access have been verified.

Only base scaling option 0 and mapped numeric stats are imported. Random suffixes, procs, set bonuses and conditional stats remain incompletely valued. The published databases still cannot expose all hidden/unrevealed items. A newer client build alone does not prove more complete item facts; keep provenance distinct.

## Future armor and upgrades

Show current usable upgrades first. If Dungeon, Quest or AH has no current result, run a second batched pass for that empty category and keep its next ten positive upgrades. Body armor follows the character's level/class tier; Warrior/Paladin can transition Mail to Plate at 40, Hunter/Shaman Leather to Mail at 40. Rogue/Druid stay Leather; casters stay Cloth. Upgrader settings explain the current class transition and retain the all-wearable-armor option.

Future cards explicitly say Next at Lv X and identify Plate/Mail training where required. Their source-level threshold uses the existing +3 proximity heuristic and is an estimate, not a verified entrance level. AH future accessibility uses wear level/armor unlock rather than the original monster level. Unknown phases, required professions and known faction/class restrictions are filtered. A future recommendation must never be displayed as usable now.

## Menu

The owner's DungeonJournal screenshot informed warm gold accents, charcoal framed panels, a distinct header strip, rarity-colored names and item-icon cards. This uses Suite code and existing WoW assets, not the other addon's implementation. Upgrader details and compact dropdown rows include slot/level information and visible future markers. Shared theme changes do not add input overlays to the working chat editors or change feature navigation. Ctrl-hover activation and the stable source-popup hover family remain.

## Updating and rollback

tools/fetch_equipment_supplement.py downloads all inputs from one pinned commit into a new ignored candidate directory; it never replaces active input files. It checks basic counts, the regression item, MIT notice and input hashes. Review/promote the candidate into the ignored active input cache, rebuild the base catalog with tools/build_equipment_dev.py, then apply tools/supplement_equipment.py (the base builder now invokes it automatically when that active cache exists). Rebuilding the base is needed before refreshing previously supplemented rows. The active reference package records the pin/hashes in SUPPLEMENT.json. Run tests and package validation before installing. No in-game HTTP or automatic background promotion was added.

Previous ZIPs remain available; personal saved-data schemas do not change in this release. Tests compare old source relationships and verify that only flagged estimates changed. No player data is part of the imported references or package.

## Verification and footprint

45 tests pass, including exact Manascale facts/source, Algae current Dungeon/Quest results, future armor/training labels, all class tiers, source pooling/metadata preservation, popup lifetime, chat, loot and AH regressions. Lua syntax/TOC/version/ZIP/install checks are separate. Native rendering/input of the themed menu and live performance still need gameplay confirmation.

Fresh Lua 5.1 simulation against 0.9.34: all packed optional references/shared services rise from about 6.68 to 7.14 MiB, approximately 0.47 MiB for the broader coverage. One sample chest recommendation uses about 8.4 ms total scheduled work versus 6.8 ms; loaded equipment/Upgrader modules rise from about 3.48 to 3.96 MiB. These are not native FPS or total Suite memory. Exact values and scope: reports/COVERAGE-0.9.35.json.
