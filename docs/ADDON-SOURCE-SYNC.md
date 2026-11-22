# Installed-addon source sync (private research)

`tools/addon_sources.py` uses only Python's standard library. It reads the configured installed addon folder, never executes the addon, and never changes installed files or game SavedVariables.

```powershell
python tools/addon_sources.py refresh Pawn --addons "E:/World of Warcraft/_forever_/Interface/AddOns"
python tools/addon_sources.py watch Pawn --addons "E:/World of Warcraft/_forever_/Interface/AddOns" --interval 60
python tools/addon_sources.py status Pawn
python tools/addon_sources.py rollback Pawn
```

Alternatively set `SMYRNA_ADDONS_DIR` to your Interface/AddOns folder. Addon names are validated; the same commands work for other named addons, subject to their own rights and integration checks.

The watcher is outside WoW. It checks file hashes once per minute, catches same-version changes, and logs only changes/error transitions. It is optional and does not start itself at Windows login. Stopping it stops automatic source capture; refresh remains available before a build.

Snapshots are immutable local copies in ignored `.local/addon-sources/<addon>/snapshots/<hash>/source`. Version/file manifests are tracked in `upstream/<addon>.lock.json`. The current/previous pointers support rollback without changing Pawn itself. A missing/partial update, file changes during capture, altered snapshot or invalid TOC reference does not replace the active pointer. No automatic pruning or raw source code execution occurs. One watcher/build process should own a source at a time.

These are source-validation checks, not game compatibility tests. In 0.9.31, tools/build_equipment_dev.py consumes the active pinned snapshot to generate the standalone private scorer. Run the unit tests, arithmetic parity benchmark and tools/package_suite.py before installing a new snapshot. The watcher only captures changes; it does not rebuild, install or publicly release them. Runtime does not call installed Pawn. Invalid promotion must retain the previous installed build and ZIP; source-pointer rollback alone does not roll back installed Lua files.

Original source attribution and licence files are retained locally. No new permission is asserted by capturing a snapshot. Credentials, character data and game observations are excluded. Do not publicly publish private research adaptations without reviewing their terms.
