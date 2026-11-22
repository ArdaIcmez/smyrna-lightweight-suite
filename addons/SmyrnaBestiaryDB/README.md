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

1.6.6 Bestiary details: Loot and Matchups tabs in the existing creature window, opened through Ctrl+left-click. Matchups lists Fire, Frost, Nature, Arcane, Holy and Shadow defenses, with physical armor/immunity separately; no additions to native hover tooltip. Damage-school guidance supports20damage-oriented spec profiles; mixed schools remain mixed, armor is not compared numerically with magic resistance, zero is not a vulnerability, and missing values remain unknown. Classic records obey the existing Classic toggle. Evidence carries scope/source/build. This is damage-type suitability, not a simulated DPS/class/tank/healer ranking.
Coverage: zero verified creature-defense records bundled so far (Bestiary DB Defenses.lua intentionally empty). Live pages therefore show Unknown and no supported recommendation until a sourced defense import exists. No fictional mob facts or test fixtures shipped. Tests use synthetic records only. 35/35 simulated scripts pass including school classification, source filtering, no hover additions, tab/reset/close, and100switches with no frame growth. Matchup page built once on first open, no combat polling or timers.

0.9.10 Bestiary: imports4399known creatures' base resistance, school-immunity mask and positive armor facts from CMaNGOS Classic1.12. Always marked Classic reference, never Forever verified; existing Classic estimates toggle applies. Replaces empty defense catalogue with129734bytes Lua source (~488KiB retained Lua heap in test),128entry bounded lazy decode cache. Zero armor is omitted because it can mean server-derived armor. Negative resistance retained as a number, not a fabricated extra-damage percentage. Source/GPL attribution and importer snapshot hash included.
Matchups detail shows only sourced rows and nonempty recommendation groups. No Unknown/placeholder lists. Creatures without evidence have no Matchups tab. Native hover now includes only the current player's class/spec schools (Holy/physical for Ret, Frost for Frost Mage, etc.), cached on talent/spec/spell changes; no talent scans on hover. Reports immunity, positive/negative/zero base resistance and known armor, with Classic label. Missing values produce no hint; no fictional vulnerabilities. Modern spec API, legacy talent-tab fallback, class-school fallback when no dominant spec. Pure damage-school suitability; not a DPS ranking and does not model level/gear/poison/bleed/phase immunity mechanics.
Tests: work/test_player_matchups.py checks imported masks/values, no placeholder text, player filtering, zero not weakness, Classic toggle, absent creature, bounded decode eviction. Remembrance activity regressions also pass. No claim of native hover verification yet.
