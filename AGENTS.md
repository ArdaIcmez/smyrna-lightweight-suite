# Smyrna Suite — instructions for developers and coding agents

Read docs/ENGINEERING.md before making changes. Update it when gameplay establishes a new fact.

## Product and architecture
- Product name: Smyrna Lightweight Addon Suite. Target the installed Blizzard WoW Forever client, not arbitrary Classic/private-server APIs.
- One Suite minimap launcher, alphabetically ordered feature tabs and a compact Settings entry. Optional databases are separate load-on-demand packages grouped under SmyrnaSuite. Do not create a package per profession, class or source.
- Equipment facts have one owner: SmyrnaEquipmentDB, implemented in v0.9.31. Use Suite.Equipment.Ensure/Get/Candidates/Eligible instead of independent weapon, armor, jewelry, trinket or equipment-stat catalogs. Feature loot/recipe relationships stay with their modules.
- Item identity, equip restrictions, requirement levels and acquisition provenance belong to the shared equipment service. Feature-specific UI, scoring and observations do not.
- Pawn is not a dependency. Standalone private scoring uses an attributed Pawn 2.14.8 arithmetic/weights snapshot with hashes and adaptation notices. Runtime does not switch to installed Pawn. Preserve private-only distribution to the owner and two guildmate testers; no public release without a fresh licence/distribution review.
- Use tools/addon_sources.py for installed-addon snapshots; .local stores unmodified snapshots and rollback pointers, upstream/*.lock.json stores source hashes/version. Never edit a snapshot in place. New upstream snapshots must pass runtime compatibility/equivalence tests before promotion into a fallback. No downloaded/installed source execution by the sync tool.
- Preserve third-party attribution, original licences, input hashes, game flavor/build and dates. Do not treat Classic references as verified Forever facts or an absent observation as zero.

## Workflow
- Make incremental changes to existing code. Do not rewrite functioning modules to satisfy hypothetical future needs.
- Keep source commits, version tags, installable ZIPs, readable diffs and relevant test evidence. Repository must remain PRIVATE unless the owner explicitly changes that instruction.
- addons/ is the repository source layout. The historical dated workspace outputs/ mirrors installed builds; compare and synchronize deliberately. Never overwrite newer source from a stale mirror.
- Test actual Lua code, not only mock expectations. Report simulated and native gameplay validation separately. Never claim mouse input works solely because frame mocks pass.
- No personal SavedVariables, chat, player histories, screenshots, credentials, API tokens or uploader identities in Git/release artifacts. Keep developer configuration outside the repository.
- Deploy only addon code/reference files to E:/World of Warcraft/_forever_/Interface/AddOns. Do not edit the player's WTF directory or recover/reintroduce obsolete D-drive paths.
- No recursive move/delete without resolving and validating the full target within its intended directory.

## Performance
- Event-driven work, bounded caches and pooled visible UI. No idle polling unless required and documented; cancel scheduled work on hide/disable.
- Decode relevant data lazily. Packed strings and load-on-demand addons still occupy memory after loading; do not claim they unload automatically.
- Avoid full-catalog scans, mass item requests, repeated tooltip parsing or database rebuilds in a mouse-hover handler. Schedule bounded work and cache by meaningful revisions.
- Benchmark relevant changes with realistic inputs. Large ingestion/aggregation changes need 100k/1m input checks; do not present synthetic Lua heap as native WoW memory/FPS.

## Confirmed chat regression baseline
- The owner confirmed mouse drag-selection in v0.9.30, commit c8d6f21.
- Keep the plain EditBox directly parented to the message window, above its decorative border, with native default input handling.
- No forced focus/caret/highlight on open. No mouse down/up handlers or typing/cursor-triggered layout changes on this control.
- X and resize live outside the text region. Message-editor scrolling is deferred; history has separate scrolling.
- Five isolated native variants selected correctly in v0.9.29, while previous integrated editors did not. The exact root cause is unproven; do not claim a particular template or API was definitively responsible.

## Queue regression rules
- LootFrame/LootButton owners and ancestors bypass Workshop/Bestiary/Upgrader augmentation; LOOT_OPENED hides Suite dialogs. Never override Blizzard loot clicks. Owner confirmed this fix in 0.9.30.1.
- History uses InputScrollFrameTemplate with native text/cursor/update handlers, one selectable buffer, no page/top/bottom controls and no forced focus/caret on open. Automated checks cannot prove native mouse selection.
- Bestiary defenses use player class/level. Mage gets Fire/Frost/Arcane without melee information; Hunter uses ranged damage/skill. Armor mitigation remains a labelled Classic estimate.
- Field Diary NS.Areas already caches two maps by revision. Raw Core.Aggregate rebuild timing is not idle/normal refresh cost.
- AH scans require a user action at an open AH; no automatic purchases. Cancelled/incomplete scans preserve previous prices. Quote values are listings, not completed sales.
