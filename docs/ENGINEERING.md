# Engineering record and current scope

## Verified release

0.9.32 adds source pooling, lazy positive-upgrade source decoding, character armor/trained-weapon filters, Dungeon/Quest/AH scrollable hover menus, packed learned-recipe fallbacks with bounded decode caches, chunked activities and conservative guild-growth budgets. See STORAGE.md and RELEASE-0.9.32.md. Chat default is now 10x for an unset preference; explicit saved choices are preserved. These changes have regression/benchmark coverage, not new native gameplay confirmation.
v0.9.31 combines the 0.9.30.4 hotfixes with Upgrader and its shared optional Equipment DB. The owner confirmed right-click message editor selection in 0.9.30 and loot interaction in 0.9.30.1. History selection, defense rendering and Upgrader/AH require native confirmation after this build. Do not claim all gameplay bugs are verified fixed.

## Current feature responsibilities
- Chat: timestamps, optional seconds/color, selectable message editor and session history retention (10/50/100/1000x). No nickname, roster metadata or profession-sharing features.
- Bestiary: records personal loot, guild aggregates, reference loot and Classic defense facts. Hover is compact; Ctrl+left-click opens details. References are optional. Class-based damage schools must not be mislabeled as inferred talent specs.
- Workshop: reagent uses, known/used recipe summaries, learned-first collapsible professions, source/vendor information. Bags, reagent bags, profession reagents and linked-item tooltips have integration hooks.
- Field Diary: profession-related finds. Current code still aggregates 50-yard cells, caps own/shared stores at 2,000 each and prunes after 30 days. Custom explorer, permanent interaction identity, automatic peer sharing and new provenance rendering remain incomplete. Color settings alone do not mean those features are implemented.
- Remembrance: players/recognized innkeepers; permanent first seen and retained activities. New daily snapshots are stopped. Compact summaries and bounded visible history are preferred. Do not publish personal history.
- Emoty is a separate pet project, not a Suite feature.

## Pending owner-approved direction
1. Reusable Python Bestiary updater: upstream download, complete consistent snapshots, validation, candidate package, change report and rollback. It has NOT been built yet. Preserve personal observations and existing reference scope.
2. Player contributions: stable origin/event identity, deduplication and separate normal-loot/skinning/gathering denominators. Relay copies must not create independent contributors. Never add cumulative snapshots repeatedly.
3. Weekly validated reference updates and distribution. No scheduler/service is currently configured. WoW addons cannot fetch HTTP; downloads/uploads belong in an external tool.
4. Workshop Market: material, recipe and crafted-output listing prices, crafting cost and estimated margin remain pending. Shared on-demand AH scan/quotes and Upgrader AH shopping are implemented in 0.9.31; they do not establish completed sales or implement the full Workshop Market UI.
5. Upgrader and shared SmyrnaEquipmentDB are implemented; see UPGRADER.md. No Pawn dependency. The optional reference DB includes 11,525 equipment records with labelled limitations.
6. Questie replacement is explicitly deferred.

## Upstream sources
Everloot provides observed Forever data with attribution/CC BY-SA requirements. QuestieDB has historical contributor caveats; preserve notices. Installed GatherMate/Auctionator code is not imported. The selected Auctioneer Forever CoreScan decoder is GPL-2.0-or-later; its attribution/source hashes are bundled. Private Pawn 2.14.8 arithmetic/weights adaptation retains original notices/hashes and is not for public distribution. Equipment facts include Forever client exports plus labelled Classic references.

## Queue verification for 0.9.31

0.9.31.1: saved screenshot WoWScrnShot_112226_023543.jpg confirms the Unicode right arrow renders as a missing-glyph box in the normal-hit line. Use ASCII numeric ranges and explicit "after armor" wording there. Sword/shield texture icons render correctly. No additional native rendering claim is implied.

- Loot guard covers Workshop, Bestiary and Upgrader; dialogs close on LOOT_OPENED. Original native loot clicks remain untouched.
- History has one InputScrollFrameTemplate editor with native handlers, scroll wheel, mouse-selection support and no page/top/bottom controls. The 650-message test passes; native mouse behavior remains unconfirmed.
- Bestiary gives class-specific resistance information and player-level armor estimates. Hunter skill now uses UnitRangedAttack; Mage has no physical section. Estimates are not verified Forever combat rules.
- Field Diary already has a two-map revision cache; new regression verifies reuse/invalidation. The raw aggregation benchmark was not idle CPU cost. Its long-term storage/sharing/explorer redesign remains pending as described above.
- Fishing bite animation is deferred: no reliable native bite signal or bobber anchoring has been verified. No invisible mouse-blocking overlay was added.
- 25 unit tests plus 2,900 arithmetic parity fixtures pass. Lua syntax/TOCs/ZIP/install hashes are checked by tools/package_suite.py. See reports for simulation measurements; no native FPS claim.

## Testing and release truthfulness
Mock tests cover logic/layout calls and cannot establish engine hit testing, OS clipboard, protected actions or actual native rendering. Record user-confirmed gameplay distinctly. Preserve previous ZIPs/manifests for rollback. Make no guarantees of complete recipes, complete loot, exact spawn coordinates or verified current resistances where sources do not establish them.
