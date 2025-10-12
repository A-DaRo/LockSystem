# Copilot instructions for LockSystem (Tasks 1–2)

This project models a Panama-style lock system in PlusCal/TLA+. Use `assignment_description.md` as the source of truth. Implement and verify two models: single lock/ship and multiple locks/ships.

## Key files
- `lock_data.tla`: shared constants/types/helpers (Locks, Ships, Locations, LowSide/HighSide, GetLock, IsLock).
- `lock_single.tla`: single-lock model with `lockProcess`, `shipProcess`, and a placeholder `controlProcess = 0`.
- `lock_multiple.tla`: multi-lock/ship version using arrays/maps per lock/ship; adds `moved[s]` and per-ship `permissions[s]`.
- `lock_system.tla`: toggle the active model by EXTENDS `lock_single` or `lock_multiple`.
- `lock_system.toolbox/*`: TLC configs (`model_single/MC.cfg`, `model_multiple/MC.cfg`).

## Task 1 — Single lock controller + verification
1) In `lock_single.tla`, implement `controlProcess`:
   - Loop: read next request from `requests` (records `[ship, lock, side]`, single queue).
   - Prepare lock safely using `lockCommand` and `updateWaterLevel`:
     - Close both doors; set `valvesOpen[low/high]` to drive `waterLevel` to match the requested side (`LowSide(lockOrientation)` vs `HighSide(...)`).
     - Wait via interleaving labels until `waterLevel` matches; then open the requested door; ensure the opposite door is closed and the opposite valve is closed (see Notes 6–7).
   - Decide and respond: `write(permissions, [lock |-> 1, granted |-> BOOLEAN])`.
2) Replace property placeholders (currently `FALSE`) with formulas:
   - Invariants: DoorsMutex; DoorsOpenValvesClosed; DoorsOpenWaterlevelRight; TypeOK; MessagesOK.
   - Liveness: RequestLockFulfilled; WaterLevelChange; RequestsShip; ShipsReachGoals.
   - Make them orientation-agnostic with `LowSide/HighSide`.
3) In `lock_system.tla`, EXTEND `lock_single` and use `lock_system.toolbox/model_single/MC.cfg` to model check (enable Deadlock check, add Invariants/Properties). Document WF/SF if needed.

## Task 2 — Multiple locks/ships controller + verification
1) In `lock_multiple.tla`, implement `controlProcess` to handle all locks/ships:
   - Consume `requests` FIFO globally; for each message `[ship, lock, side]`:
     - Enforce capacities: `MaxShipsLocation` for even (outside) locations; `MaxShipsLock` for odd (inside/chamber) locations.
     - Prepare lock `l` safely as in Task 1 but using arrays: `lockCommand[l]`, `doorsOpen[l][*]`, `valvesOpen[l][*]`, `waterLevel[l]`, `lockOrientations[l]`.
     - Interleave: do not block on a ship; after granting a request, continue with other requests. Use `moved[s]` to observe that ship `s` completed a step; clear `moved[s]` when observed.
     - Grant/deny via `write(permissions[s], [lock |-> l, granted |-> BOOLEAN])`.
2) Replace property placeholders with array-quantified formulas (for all locks/ships):
   - Invariants: DoorsMutex; DoorsOpenValvesClosed; DoorsOpenWaterlevelRight; MaxShipsPerLocation; TypeOK; MessagesOK.
   - Liveness: RequestLockFulfilled; WaterLevelChange (per lock); RequestsShips (per ship); ShipsReachGoals (per ship). State WF/SF assumptions.
3) In `lock_system.tla`, EXTEND `lock_multiple` and use `lock_system.toolbox/model_multiple/MC.cfg`. Verify deadlock freedom for 3 locks/2 ships and 4 locks/2 ships. Adjust constants in the model cfgs.

## Build, verify, and report
- Translate PlusCal to TLA+ with the Toolbox PlusCal translator (keep the `(* --algorithm ...)` block; Toolbox writes the `BEGIN TRANSLATION` after saving).
- Use TLC configs in `lock_system.toolbox/model_single/MC.cfg` or `model_multiple/MC.cfg`:
   - Set CONSTANTS (NumLocks, NumShips, MaxShipsLocation, MaxShipsLock).
   - SPECIFICATION: `Spec`; add invariants/properties you defined; enable Deadlock check.
- Run TLC and create markdown reports under `reports/`:
   - `reports/single_model_results.md` and `reports/multiple_model_results.md` should include: constants used, invariants (PASS/FAIL), liveness (PASS/FAIL, fairness used), deadlock, states/time, and any counterexample summary.
- Add a short header with date and cfg name for reproducibility.

## Fairness and example properties
- Fairness: You may need WF on `controlProcess` and/or SF on specific actions to discharge liveness.
   - Example Toolbox setting: add `WF_vars(controlProcess)` (weak fairness) or `SF_vars(controlProcess)` if starvation appears.
- Example (single) invariant sketches, orientation-agnostic:
   - DoorsMutex: ¬(doorsOpen["west"] ∧ doorsOpen["east"]).
   - DoorsOpenValvesClosed: doorsOpen[LowSide(lockOrientation)] ⇒ ¬valvesOpen["high"] ∧ doorsOpen[HighSide(lockOrientation)] ⇒ ¬valvesOpen["low"].
   - DoorsOpenWaterlevelRight: doorsOpen[LowSide(lockOrientation)] ⇒ waterLevel = "low" ∧ doorsOpen[HighSide(lockOrientation)] ⇒ waterLevel = "high".
- Example (multi) invariant forms (∀ l ∈ Locks):
   - DoorsMutex: ¬(doorsOpen[l]["west"] ∧ doorsOpen[l]["east"]).
   - MaxShipsPerLocation: for even k, |{ s ∈ Ships : shipLocations[s] = k }| ≤ MaxShipsLocation; for odd k, |{ s : shipLocations[s] = k }| ≤ MaxShipsLock.
- Liveness examples:
   - RequestsShip(s): infinitely often ship s writes to `requests`.
   - RequestLockFulfilled(s): always (request by s) eventually InLock(s) for that lock.

## Current example scenarios (from Toolbox models)
- Single model constants: NumLocks=1, NumShips=1, MaxShipsLocation=2, MaxShipsLock=1.
- Multiple model constants (example): NumLocks=2, NumShips=3, MaxShipsLocation=2, MaxShipsLock=1. Adjust to 3/2 and 4/2 for required checks.

## Patterns, queues, and gotchas
- Queues: `write(queue,msg)` appends; `read(queue,res)` blocks until non-empty—use labels between writes/reads to avoid large atomic steps.
- Process ids: Locks first (1..NumLocks), then Ships; controller is process id 0.
- Locations: even = outside; odd = inside; `GetLock(odd)` gives lock id.
- Environment assumption: outside water level is constant; only chamber level changes via valves/doors. Don’t open doors when levels mismatch.
- In multi model, `Len(permissions[s]) <= 1` by `MessagesOK`. Keep controller replies bounded.

## Quick examples
- Single: West entry grant → set water to low if needed, open `"west"` door, then `write(permissions, [lock |-> 1, granted |-> TRUE])`.
- Multi: To open east doors of lock `l` → `lockCommand[l] := [command |-> "change_door", open |-> TRUE, side |-> "east"]`; grant to ship `s` via `write(permissions[s], [lock |-> l, granted |-> TRUE])`.
