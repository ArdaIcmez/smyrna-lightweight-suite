# Smyrna Suite — instructions for developers and coding agents

Read docs/ENGINEERING.md before making changes. Update it when gameplay establishes a new fact.

## Product and architecture
- Product name: Smyrna Lightweight Addon Suite. Target the installed Blizzard WoW Forever client, not arbitrary Classic/private-server APIs.
- One Suite minimap launcher, alphabetically ordered feature tabs and a compact Settings entry. Optional databases are separate load-on-demand packages grouped under SmyrnaSuite. Do not create a package per profession, class or source.
- Equipment facts must have one owner: the planned SmyrnaEquipmentDB shared service. Future features consume that service instead of creating independent weapon, armor, ring, neck, trinket or equipment-stat catalogs. It is planned, not implemented in v0.9.30.
- Item identity, equip restrictions, requirement levels and acquisition provenance belong to the shared equipment service. Feature-specific UI, scoring and observations do not.
- Pawn must remain optional. The owner explicitly requests a private optimization playground, with the owner and two guildmate testers. Local attributed upstream snapshots and private scoring experiments are authorized; preserve the original licence and authorship. Do not treat the private audience as blanket permission for redistributing modified third-party code. No public release of such experiments without a fresh licence/distribution review. Prefer installed Pawn live when present; the planned standalone fallback must keep its upstream version and adaptation history visible.
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
