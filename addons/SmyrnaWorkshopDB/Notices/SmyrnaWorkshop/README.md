# Smyrna Workshop 0.1.1

Hover meat, ore, herbs, cloth or another material in your bags. Workshop tells you what it is used for, including recipes you have not learned. It shows the profession, recipe name, required skill (when available), learning status and bag ingredient counts. Green counts satisfy that ingredient; red counts mean you need more. “Materials for N” describes ingredients, not a guarantee that you can craft: tools, profession skill, cooldowns and a cooking fire may still be required.

For example, Stringy Wolf Meat resolves to Charred Wolf Meat even before learning Cooking. Opening a profession window records the recipes currently exposed by the client. Unavailable learning information says “Learning status unknown”; it never silently means “learned.”

Click the hammer minimap icon or type `/sw` for options and the recipe list. Drag the icon around the minimap rim; its position is saved. The list includes your captures and reference packs already loaded by hovering materials. Counts exclude the bank. Tooltip display is capped at five recipes and six ingredients per recipe; the list has the rest.

## Optional data

Nine independent load-on-demand databases contain 2,335 community-reference recipes: Cooking (130), Alchemy (182), Blacksmithing (474), Enchanting (239), Engineering (263), First Aid (32), Leatherworking (557), Mining (17), and Tailoring (441). A tiny item-to-profession manifest loads only the packs matching the hovered material. Reference recipes are not copied into saved variables. Your observed recipes are saved per character, capped at 3,000. Recipe names in the reference snapshot are English; captured names follow your client language.

Type `/smyrna` to switch the four feature addons, individual profession databases, or the mob-loot references on/off. Apply & reload releases disabled modules and their data from memory. Main feature switches preserve the separate recipe/reference selections. Diary’s map bridge follows its feature switch. Each addon also works without the Suite controller. These are local records and packaged snapshots; there is no automatic upload or online service.

Reference data is derived from NorgannonDB (Maro), pinned commit 7e1368e755b2cc6ef76f0199aa624cb02526e00b, described upstream as a work-in-progress Forever 1.60.1 database. Coverage and required skill values need in-game verification. Missing data does not prove an item has no use. The source snapshot, GPL-3.0 licence, upstream notice and reproducible literal-only builder are in `sources/` and `tools/`. Each data pack carries its source notice and licence. No Questie code or data is required.

## Testing

The tests use mocked Lua 5.1 APIs, including real generated Cooking rows, unlearned meat lookup, ingredient bottlenecks, bank exclusion, disabled packs, lazy loading, legacy/modern profession capture and Suite switches. Real Forever UI/API compatibility still requires an in-game test. Close and restart WoW after installing new folders.

0.1.1: Forever item tooltips now use TooltipDataProcessor post-processing; older clients retain the SetBagItem fallback. Modern-path regression test added.

0.1.2: batched reference-index rebuilds, tooltip lifecycle deduplication and displayed-item fallback, optional event validation, saved-default merging and /sw status diagnostics.
