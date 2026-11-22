Current release: **0.9.7**. Previous numbered release notes below are historical.

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
