# 0.9.33 — Upgrader activation and compatibility

Press C, hover a character gear slot and hold Ctrl+Shift. The Dungeon, Quest (!) and AH circles appear below the slot after the scan. Pressing the modifiers while the mouse is stationary works too. Ordinary hover stays quiet. Moving into the circles/menu keeps them usable; leaving closes them. Ctrl+left-click remains the explicit ranked-details action.

## Fixed

- Automatic talent profile detection previously used the old GetTalentTabInfo return-3 layout and legacy GetSpecialization. The saved preference was automatic, while most tests supplied an explicit manual profile. The corrected reader prefers Forever C_SpecializationInfo, reads return 7 for points spent and supports return 5 in the deprecated shim. Druid's third Classic tree still maps to Restoration, not the separate Feral-tank weight profile.
- Missing profile, disabled Equipment DB, unsupported item and occupied off-hand failures previously returned via tooltip notices, leaving the separate details window on Checking. They now display an actionable terminal status there, including a Choose scoring profile action where appropriate.
- Async scan errors now terminate the loading state with visible details and allow retry. Open details keep their comparison request from being preempted by unrelated hovers. Equipment changes explicitly invalidate the displayed scan.
- Character ring/trinket slot handlers retain their exact slot; the generic modified-item-click hook does not override those handlers.
- Workshop's known-recipe check now uses the modern spellbook namespace even when legacy globals are absent. Equipment proficiency queries share the guarded compatibility helper.
- Version comparisons accept three- and four-part releases, so earlier hotfix versions do not disable update notifications.

## API audit evidence and limits

Primary client API source: https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpecializationInfoDocumentation.lua and https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_DeprecatedSpecialization/Deprecated_Specialization_Vanilla.lua . Known-spell lookup uses C_SpellBook.IsSpellKnown, with guarded legacy fallbacks.

Reviewed Suite item/container, addon loading/metadata, spell info, map, memory and optional weapon-skill call sites. Existing C_Item/C_Container/C_AddOns/C_Spell/C_Map paths were retained. Optional unavailable weapon-skill APIs omit their explanatory line; they are not prerequisites for armor estimates. This audit does not establish complete runtime compatibility or native input/rendering correctness.

39 automated tests pass, including namespace-only auto profiles, both talent return layouts, no scan on ordinary hover, stationary Ctrl+Shift, blocked prerequisite messages, injected timer error/retry, namespace-only known recipes and hotfix version ordering. Existing storage/source equivalence and loot/history/AH checks remain. Lua syntax/TOC/package/install hashes are validated separately. Native confirmation is still required after reload.
