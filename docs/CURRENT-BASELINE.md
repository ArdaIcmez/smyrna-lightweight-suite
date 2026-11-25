# Master and repository editions

Current master: installed 0.9.36 Suite, including subsequent owner-approved fixes. Keep it local and complete. Never deploy the repository snapshot over the installed master.

Repository edition: latest master code except Market.lua and Modules/MarketUI.lua. Market scanning, prices, profit/$$$$ UI, Market navigation, Market guide and its SavedVariables declaration are omitted. Upgrader retains tradable-item recommendations but hides unavailable Market scan/search actions.

Regenerate deliberately with `python tools/export_public.py --source <master AddOns directory>`. The export does not modify master or produce ZIPs. Personal Taylan photos, game state and captures are excluded. Emoty is standalone and outside this sync.

The GitHub repository remains PRIVATE. Market was previously committed; this exclusion removes it from the current tree, not historical commits. Do not make the repository public without a deliberate history and distribution review.

Older release documents and tests describe earlier baselines. The full historical test suite does not certify this expanded edition. Public-profile tests, Lua 5.1 compilation, TOC validation and staged privacy checks validate the export structurally; gameplay checks remain separate.
