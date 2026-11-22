# 0.9.32 — storage optimization and source menus

## Player changes

Character gear hover shows three reusable circular source buttons: Dungeon, Quest (!) and AH. Hover a button for up to ten ranked upgrades in a scrollable dropdown; hover a row for its normal item tooltip, or click to open source-filtered details. AH recommendations are confirmed BoE candidates, not proof a listing exists. Buying a BoE does not require reaching its original drop source. Native AH search/purchases remain player actions.

Default body-armor recommendations follow class progression: Warrior/Paladin Mail before 40, Plate at 40; Hunter/Shaman Leather before 40, Mail at 40; Rogue/Druid Leather; Mage/Priest/Warlock Cloth. Cloaks, shields, jewelry and relics retain their distinct slot rules. Upgrader settings can include all lighter wearable armor. Trained weapon spells filter candidates where reported by the native spellbook API; class rules are the explicit fallback if training is unavailable. Off-hand weapons require reported Dual Wield. Same one-hand/two-hand loadout rules remain.

Class proficiency input is the bundled Forever export (client build/provenance in Equipment MANIFEST.json). Native learned-spell lookup uses C_SpellBook.IsSpellKnown or legacy APIs. See the exported client API at https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua and the reference exporter https://github.com/gBlaku/wow-forever-kb. Static level rules do not prove that a character purchased an armor-training unlock.

## Storage changes

- Bestiary no longer loads all equipment facts merely to resolve an unknown item name.
- Equipment records refer to a shared pool of 4,601 acquisition rows. All 11,525 gear records and every original source row are compared against 0.9.31.1 in regression tests. Source decoding is deferred until after a positive score; source objects are shared in a bounded cache.
- Learned Workshop recipes migrate from nested tables to packed fallback records. Ingredient indexes retain keys, not duplicate decoded recipes; a twelve-item cache decodes requested uses. Full fallback facts are intentionally retained so learned recipes remain available with reference DBs disabled. This is not an IDs-only format.
- Remembrance activity strings migrate lazily to 1-KiB chunks on append. Existing events, first seen and legacy records remain. No activity cap or deletion was introduced. Huge history rendering and the existing login validation pass still have costs beyond append/lookup benchmarks.
- Guild samples accept up to 4,096 aggregate keys per guild, 256 item identities per key and eight guild stores for new data. Existing legacy data survives migration even above those limits. New entries exceeding a budget are skipped as whole samples, never partially added to denominators. Existing keys can continue updating within limits. Deduplication remains an 8,192-GUID window, not permanent deduplication.
- Chat defaults to 10x retention unless an explicit 50x/100x/1000x value is saved. Existing explicit selections remain. History assembly uses bounded batches; native editor text/layout memory remains additional. No automatic mid-session pruning or clipboard API was added.
- Diary already had a two-map revision cache; it is preserved and regression tested rather than rewritten.

## Verification

33 tests cover source pooling equivalence, Workshop migration/offline lookup/counts, 10,002 retained activity events, guild capacity preserving denominators, all nine classes at levels 1/39/40/60, learned weapon filtering, AH-only menu rows, scroll bounds, native History handler retention, loot guards and existing scoring/AH behavior. Lua 5.1 syntax, TOC references, consistent versions, ZIP CRC and installed hashes are checked separately.

Before/after measurements are in reports/OPTIMIZATION-0.9.32.json. New ingestion checks include 100,000 and 1,000,000 activity events. Simulations exclude native UI, gameplay rates and real personal data. UI mouse hit testing, texture appearance, protected AH actions and live frame time still require game verification.

## In-game check

Reload, press C, hover gear, then hover each source circle. Scroll its list and inspect a row; click for full details. Check class/armor/profile selection in Upgrader. At the AH, scan and search a tradable candidate. Check a learned ingredient with Workshop reference DB disabled, existing Remembrance activities, History mouse selection and manual corpse looting. Data schemas changed: downgrade only with matching pre-migration saved-data backup, not old code alone.
