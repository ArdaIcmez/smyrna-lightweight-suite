# Engineering record and current scope

## Verified release
v0.9.30 is the current source baseline. The owner confirmed right-click message editor mouse selection in game. Do not regress it while adding other features.

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
4. Workshop Market: material, recipe and crafted-output listing prices, market scope and scan age; crafting cost and estimated margin. Listed prices do not establish completed sales. AH scan and Market tab are NOT implemented yet.
5. Upgrader and a shared equipment DB; see UPGRADER.md. Not implemented at this checkpoint.
6. Questie replacement is explicitly deferred.

## Upstream sources
Everloot provides licensed observed Forever data through documented APIs; data credit and CC BY-SA terms must be retained. Questie/QuestieDB have historical-contributor licensing caveats; no blanket unrestricted-reuse assumption. GatherMate2/Data and installed Auctionator list All Rights Reserved. Auctioneer Forever is a possible GPL source but its actual selected package/file licences and compatibility must be audited before reuse. Pawn is an optional integration, not code to embed under a guessed licence.

## Testing and release truthfulness
Mock tests cover logic/layout calls and cannot establish engine hit testing, OS clipboard, protected actions or actual native rendering. Record user-confirmed gameplay distinctly. Preserve previous ZIPs/manifests for rollback. Make no guarantees of complete recipes, complete loot, exact spawn coordinates or verified current resistances where sources do not establish them.

## 0.9.30.1 loot-input hotfix

User reports autoloot succeeds while mouse hover/manual loot fails. This does not establish a single root cause. Added a shared active-loot/loot-owner guard: Workshop does not augment item tooltips or hook item owners during looting; Bestiary does not augment tooltips then. Opening loot closes Suite dialogs that could cover the loot window. Original Blizzard loot scripts are never replaced. Mock checks verify owner/ancestor rejection, original click retention and dialog closure; owner confirmed native loot hover/clicks work. Unfinished Upgrader changes are excluded from this release.

## 0.9.30.2 history scrolling

History now uses the native UIPanelScrollFrameTemplate and a plain mouse-enabled EditBox, as tested successfully in isolated configuration 3. Removed cursor/focus scrolling and typing-triggered geometry changes. Mouse wheel handlers clamp offset; Top/Bottom/Page up/Page down remain. Users can select and Ctrl+C; no restricted clipboard calls. Simulated scrolling/paging/text-preservation tests pass, native history confirmation pending.

## 0.9.30.3 player-relative defenses

Armor calculations use the player level and Classic armor/(armor+400+85*attackerLevel), capped 75%, supported by CMaNGOS mangos-classic Unit::CalcArmorReducedDamage. Estimates are explicitly not verified Forever formula/current debuffed armor. Same-level/rank Classic reference quartiles classify armor low/typical/high (minimum ten comparison records). The UI uses the current UnitDamage or Hunter UnitRangedDamage for an estimated normal-hit range. UnitAttackBothHands skill is compared with creature-level*5 estimated defense when available, without inventing an exact miss rate. Weapon skill does not change armor mitigation. Mages only see Arcane/Fire/Frost status; no melee/armor section. No-resistance, resistant, immune and known vulnerabilities are shown only for the current class damage schools.
