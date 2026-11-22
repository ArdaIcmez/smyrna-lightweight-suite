# 0.9.31 — private integration test

## Included

- Upgrader Suite tab, standalone Pawn snapshot scoring, optional shared Equipment DB, compact hover and Ctrl-click top ten.
- All/AH upgrade lists; explicit AH replicate scan, timestamped quotes and native item search. Requested upgrades survive quote-cap truncation.
- Loot-input guards retained across Workshop, Bestiary and Upgrader. Native loot behavior was confirmed by the owner on the preceding hotfix.
- Chat History is one native scrollable/selectable editor without page/top/bottom controls. Single-message copy editor remains at its confirmed working baseline.
- Class-specific Bestiary defenses, player-level armor estimates and Hunter ranged skill. Classic estimates retain provenance.
- Diary two-map revision-cache reuse/invalidation verified; no unnecessary aggregation rewrite.

## Validation

25 unit tests pass; 2,900 Pawn arithmetic parity fixtures pass. Native History handler/wheel/cancellation simulation with 650 messages passes. All shipped Lua parses as Lua 5.1; TOC references, package versions and ZIP CRC pass. Installed file hashes match source. No personal SavedVariables are included or edited. The previous 0.9.30.4 ZIP is the rollback package.

## Native acceptance flow

1. Fully restart WoW so the new SmyrnaEquipmentDB folder appears. Enable Suite and Equipment DB on the character AddOns page.
2. Open Suite > Upgrader. Confirm the selected profile matches the intended spec; choose it manually if needed.
3. Press C. Hover chest, weapon, ring and trinket; Ctrl + left-click to open top ten. Check level/source labels and close with X. Repeat on bag gear.
4. At the AH, open AH upgrades, click Scan AH, wait for quotes, then click an item's AH search button. Check listing names/variants before buying. No purchase automation is included.
5. Open History. Wheel-scroll, drag-select words and Ctrl+C. X/Escape close. Right-click a single chat message and confirm its separate editor still selects normally.
6. Loot a corpse with auto-loot off: default tooltip and manual click must work. Open Bestiary details and check only the character's relevant damage schools are shown.

## Still pending

Native Upgrader/UI/AH/History acceptance is not established by mocks. Fishing bite animation lacks a verified signal/anchor and is not implemented. Full Workshop material/output market UI, external validated weekly pipelines and the Field Diary explorer/sharing redesign remain separate unfinished projects. Equipment/source coverage and procs/set/variant scoring are incomplete; this is not a completeness guarantee.
