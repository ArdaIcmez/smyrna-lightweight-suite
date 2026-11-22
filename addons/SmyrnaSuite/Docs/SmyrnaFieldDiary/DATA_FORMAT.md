# Data model and protocol v1

SmyrnaFieldDiaryDB contains schema version, origin, settings, own/shared stores and
a presentation-cache revision. Origin is random and account-wide for this saved
installation. It is not a character GUID.

## Compact persistent record arrays

| Index | Field |
| --- | --- |
| 1 | UI map ID |
| 2, 3 | 50-yard cell X/Y |
| 4 | mine / herb / skin / valuable |
| 5 | Counted sessions/observations |
| 6 | Item quantity |
| 7 | Vendor sum, copper |
| 8 | Monotonic bucket revision |
| 9 | Last seen, server epoch; system-time fallback if unavailable |
| 10 | Own-only item-ID table, values {quantity, vendorCopper} |
| 11 | Named item-type count, max 8 |
| 12 | Shared-only last sender |
| 13 | Shared-only origin |

Own keys: map:cellX:cellY:kind. Shared keys: origin:map:cellX:cellY:kind. Changing the
sending character cannot duplicate an originating dataset. Stores have fixed-size
insertion rings and slot lookup; eviction checks the current slot so an old reference
cannot delete a subsequently pruned/reinserted key.

No raw node coordinates, GUIDs, visits, movement trail, kills or time-spent denominator
are persisted. Position is reconstructable to a 50-yard square. Display grouping can
switch between 2x2, 4x4 and 8x8 cells without recollection. Rings cover square membership.

## Transport

Prefix SMYRNAFD1. One snapshot per addon message:

`1|origin|map|cellX|cellY|kind|revision|observations|quantity|vendorCopper|lastSeen`

Max validated length 220 characters. Origins are alphanumeric, length 8-24. Counters
must be bounded nonnegative integers, with positive observations/revision and quantity
at least observations. Unknown categories/versions/maps, invalid cell bounds, stale
timestamps (>30 inactive days) and future timestamps (>5 minutes) are rejected.

Existing imports require higher revision and nondecreasing counters, then **replace**
the previous snapshot. Imports are never forwarded. Origin tokens provide deduplication,
not cryptographic identity or proof of honest reports. One writer per originating saved
dataset is assumed; cloning it into concurrent independent writers is unsupported.

Manual zone batches: max 120 packets, 2/sec, cursor advances on completion. Cancellation
keeps the batch retryable. Receiver budgets: 8/sec globally, 4/sec per sender, 16 active
sender entries with inactivity expiry. No automatic requests/replies, acknowledgements,
relay or continuous broadcasts. Take turns for catch-up; repeat shares to recover
throttled/missing snapshots. There is no guarantee of all-zone synchronization.

## CSV

Bucket rows carry totals; item rows carry item-level quantities/value with bucket
aggregate columns blank. Provenance separates own origin from shared sender/origin.
Item zero means other/overflow. Missing shared item rows do not mean zero received items.

## Future iterations

- Acknowledged/digest-based catch-up with bounded traffic/state.
- Time-window/decay bins, at additional per-bucket memory cost.
- Yield normalized by visits/time, requiring an exposure denominator.
- More displayed hotspot points per area with a measured rendering budget.
- Adjacent-block merging; deterministic fixed cells currently keep share keys simple.
