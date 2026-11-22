Current release: **0.9.8**. Previous numbered release notes below are historical.

# Smyrna Suite 1.6.1

## AddOns layout

Smyrna Suite - Main Core contains all shared utilities and the reagent/profession index. There is no separate SmyrnaDB addon. The internal SmyrnaDB Lua API remains for compatibility with reference block readers.

The Main Core and its three optional packages share `Group: SmyrnaSuite`, matching DBM's installed grouping mechanism:
- Smyrna Bestiary DB: bundled mob and loot reference data.
- Smyrna Workshop DB: bundled recipes, item sources and recipe acquisition data.
- Smyrna Remembrance DB: personal encounter-history storage.

All optional packages depend only on SmyrnaSuite and are load-on-demand. This means enabled packages wait until requested; disabled packages are not forced on. Bestiary/Workshop load when their data is needed. Remembrance requests its history store at PLAYER_LOGIN, then installs tracking hooks only if loading succeeds. All packages may be enabled/disabled in WoW AddOns. Main Core disables the dependent packages. Emoty remains independent.

Restart WoW to refresh addon folders after installing. Keep Remembrance DB enabled for the first migration login. Existing SmyrnaRemembranceData and legacy SmyrnaRemembranceDB records are preserved; the latter migrates by adopting the table, without duplicating records. Disabled storage preserves legacy variables until a later enabled login. No saved-variable files are edited by the installer.

33/33 simulated test scripts pass. Native addon-list grouping and saved-history migration still need in-game verification. No additional repeating timers or per-frame handlers were added.

0.9.8 Remembrance shared-activity timeline: stops NEW daily position snapshots while preserving legacy history and first/last seen. Detailed history now lists dated dungeon/raid visits, reported dungeon completions, successful boss kills, battleground participation/completion, and mutually confirmed quest turn-ins. No ten-entry activity cap. Meaningful repeated events keep their dates. Instance visits are not labeled clears. Requires group membership and same-instance position evidence or a locally visible unit when coordinates are unavailable. Session dedup persists across reload, resets on leaving/changing instance. Completion requires supported client events; unsupported events are safely skipped.
Quests: both players must have this version with Confirm quests enabled; exchange quest IDs on PARTY/RAID/INSTANCE_CHAT only. Both must turn in the same quest within10minutes while grouped. Sender resolved against current roster; no GUIDs supplied by messages trusted. Incoming pending buffer capped256. No guild/global broadcast, no historical reconstruction. Activities and quest confirmation have separate toggles. First seen and player records remain GUID keyed; per-player activity log is one packed string and titles shared in a dictionary. No polling timers. Current tests: work/test_remembrance_activities.py and reports/REMEMBRANCE-ACTIVITIES-TESTS.json. Former full-suite test sources were absent after workspace cleanup, so no claim of rerunning those tests for this release. All runtime Lua syntax and TOC references validated. Native dungeon/BG/two-client verification remains pending.
