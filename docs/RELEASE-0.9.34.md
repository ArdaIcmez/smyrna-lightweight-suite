# 0.9.34 — accessible Upgrader hover menus

Hold Ctrl while hovering character gear; Shift is no longer required. Pressing Ctrl after parking the cursor on a slot also activates it. Circles appear immediately, with a loading row until results arrive. Ctrl+left-click still opens detailed upgrades.

Reviewed the owner's saved 36-second recording. The prior UI placed the controls over the next equipment button and reused a minimap border whose artwork was incomplete at this size. That also made mouse travel activate neighboring gear and destabilize the dropdown. The previous per-control leave timeout did not reliably cover native scrollbar/child mouse focus.

The controls now have 44x44 hit areas, full original circular border/mask textures and readable Dungeon/Quest/AH captions. The 158x66 dock scales with its gear owner and anchors inward beside the equipment column, avoiding the next slot. Both dock and menu clamp to the screen. Geometry/rendering still require native confirmation.

The popup tracks the full owner/dock/menu hover family, including scrollbar descendants, with a 0.65-second travel grace. Pointer tracking runs at 10Hz only while visible (up to three geometry queries per tick), cancels on hide, and uses no permanent idle updater. Entering a row keeps the menu open; scrolling does not reset it. Unrelated modifier changes no longer restart the scan/menu. Background slot enters cannot replace a popup while its controls own the mouse.

Async completion updates the existing dock even after leaving the gear and closing its native tooltip. Blocked scans replace the loading row with status rather than disappearing or waiting forever. The existing pooled ten rows and one dock/menu remain; no per-hover frame allocation was introduced. Two original uncompressed 64x64 RGBA TGA assets add about 32KiB on disk/texels, excluding engine texture overhead. Development generator: tools/build_upgrade_icons.py (Pillow).

42 tests pass, including Ctrl-only/stationary activation, immediate loading controls, completion after native-tooltip close, pointer travel through circle/row/scrollbar, row clicking, closing outside the whole family and stopping the tracker. Existing scoring/data/storage/loot/history/AH checks pass. Lua syntax, TOCs, ZIP CRC and installed hashes are checked separately. Native game input and the appearance of the changed assets remain unverified until the next in-game test.
