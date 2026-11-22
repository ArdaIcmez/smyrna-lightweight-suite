# Smyrna Bestiary 0.1.0

**Choose a creature. See its loot. Grow a shared world guide as you play.**

This is the third standalone Smyrna addon. It works alongside Smyrna Chat and
Smyrna Field Diary. Local tests pass; actual WoW Forever-client testing is still pending.

## Install and play

Exit WoW. Extract all SmyrnaBestiary folders from the ZIP into the Forever client's
Interface/AddOns. Keep the eight SmyrnaBestiary_Data folders: they are optional,
load-on-demand reference packs, not eight extra running interfaces. Enable them and
Smyrna Bestiary in the addon list.

Click the small **Bestiary +** button below the minimap, or type `/sb`.
You get a horizontal list of creatures for your area. Click a creature to open its
loot, use arrows for more creatures/items, and hover an item for details.
The strip can be dragged. Its search field filters the current area's creatures.
Closing the strip also closes its loot dropdown.

Hovering a creature also adds up to five loot entries to its normal tooltip.
If the game hides its identity, use the area browser manually; we do not guess or
try to bypass the client's restrictions. NPC symbols are generic creature icons,
not individually rendered 3D portraits.

## Options

Click **Options** on the strip, or `/sb options`:

- Enable Bestiary: controls passive recording/tooltips and the launcher.
- Show loot when I hover a creature.
- Show the Bestiary button.
- Remember my discoveries.
- Show my results alongside reference data.
- Include clearly marked Classic estimates.
- Include skinning estimates / quest-drop estimates.

Recording starts on. No data is uploaded automatically. No map overlays are added
by Bestiary. Reference data loads when first needed; it does not download from the
internet while you play. New pack loads defer until after combat.
`/sb perf` reports addon memory and optional profiling CPU, for troubleshooting.

## Read the percentages

- **Forever sample:** published Everloot observations, with drops/sample windows.
- **Classic estimate:** a Classic database reference; Forever may differ.
- **Your finds:** your recorded item-presence count divided by attributed loot windows.
- **Shared sample:** player exports combined with the supplied database tool.

Missing information stays unknown. A zero in a recorded sample means not seen in
those samples, not impossible to drop. Small samples are marked. Hover for counts
and a statistical interval for your sample. These are observations/estimates, not
guaranteed per-kill probabilities. Quest eligibility, level, group/loot conditions,
changes to the game, and missing windows can affect results.

Reference snapshot: **17 November 2026**. Includes 4,427 NPC entries, 263 with Forever
sample data, and 75 indexed zone/dungeon contexts. Some entries have only skinning
estimates or lack a zone assignment. There are 596 unassigned entries; known IDs
can still work in tooltips, and newly observed creatures enter your local area list.
This is not complete authoritative coverage of all Forever content. New/hidden
dungeons may remain unknown. Sources are visible through **About & sources**.

## What our own database remembers

- Publicly identifiable NPCs you target or mouse over: name, observed level range,
  creature type, zone/dungeon and game build.
- Approximate **player** locations in 200-yard cells, not exact NPC spawn points.
- Attributed single-creature loot windows: which items appeared, how often, quantities
  and the sample denominator. We record the window, not just the loot you personally won.
- Separate records per area, NPC, difficulty, game build and record epoch.

Repeated sightings/loot windows for the same corpse are suppressed using a persisted,
bounded recent-ID cache: 1,024 entries and a 30-minute dedup interval. It is not an
unlimited kill ledger. Recent mob GUIDs stay local and are not exported.

Multiple-source windows, hidden identities, incomplete item information, gathering,
skinning, pickpocketing, fishing, opened items and disenchanting are excluded from
normal mob-loot samples when recognizable. Completely empty windows cannot reliably
be attributed and are counted separately, not treated as confirmed zero drops.
Money-only windows with a confirmed source can provide valid zero-item samples.
Therefore our denominator is **attributed loot windows**, not every kill or corpse.
Partial/group loot and unrecognized gathering event timing remain limitations.

Limits: 1,000 retained creature/area records, 64 item types and 16 observer-location
cells per record. Older inserted records are evicted when full. A new epoch prevents
an evicted/recreated record from replacing earlier exported history. If an item cap
is reached, missing items are unknown rather than falsely shown as measured zeroes.

## Grow the shared world guide

1. Play with Remember my discoveries enabled.
2. Options â†’ **Export discoveries**. Ctrl+A, Ctrl+C; save as a UTF-8 `.csv` file.
3. Friends can export the same way and explicitly give you their files.
4. Combine them with the included tool:

```text
python tools/merge_exports.py --database smyrna-world.db --publish community.json --addon-output shared-guide player-one.csv player-two.csv
```

This creates a local SQLite database, inspectable JSON, and
`shared-guide/SmyrnaBestiary_Community`. Install that generated folder alongside the
other addons, then restart/reload as appropriate. Its shared creatures and rates
appear in Bestiary, including newly discovered NPCs absent from the reference packs.

Repeated exports replace older snapshots rather than adding them twice. Separate
contributors' counts combine with a proper denominator, including their zero-item
samples where valid. Build/difficulty/area remain separate. Source tokens count
datasets, not verified individual humans. Cloned or dishonest datasets cannot be
authenticated by this offline prototype.

Nothing is uploaded, hosted or published automatically. There is no live server or
automatic cross-player sync. We now have an end-to-end collection â†’ database â†’ shared
addon flow; hosting, review and automated updates can be a later iteration.
Your collected exports remain under your control; third-party reference licences
do not automatically assign a licence to your personal observations.

## First in-game test

1. Open Bestiary + in a familiar zone; page, search, choose a mob and inspect loot.
2. Hover a known mob, then compare the source/sample label with the strip.
3. Target a creature, open its loot, reopen the same corpse and inspect the export.
4. Verify item quantity and windows-containing-item remain different counters.
5. Try an instance, hidden identity, skinning, group/AoE loot and an empty window.
6. Turn recording/tooltips off and verify the controls behave independently.
7. Export from two players, merge twice and confirm totals do not double.
8. Install the generated shared guide and check it through the same player UI.

PERFORMANCE.md documents synthetic measurements and actual-client profiling steps.
DATA_MODEL.md explains sampling/merge semantics. ATTRIBUTION.md names reference
sources and licences. Tests and tools never load as game UI modules.

## Minimap icon

Click the round minimap icon to open the addon. Right-click for options. Drag it around the minimap edge; the angle is saved. No idle update loop or external icon library is used.

0.2.1: loot tooltips exclude friendly/service NPCs and players; known attackable creatures and hostile corpses remain eligible. No added block for empty loot data. Friendly NPC services/quest tooltips are a future separate feature.
