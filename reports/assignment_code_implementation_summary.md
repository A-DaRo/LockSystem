# Assignment Code Implementation Summary

## Overview
This document provides a detailed summary of the PlusCal/TLA+ implementations for the Panama-style lock system control software, covering both Task 1 (single lock/ship) and Task 2 (multiple locks/ships) as specified in the assignment description.

---

## Task 1: Single Lock & Single Ship Model (`lock_single.tla`)

### 1.1 Control Process Implementation (`controlProcess`)

The `controlProcess` (process ID 0) implements the main controller logic for managing a single lock serving a single ship. The implementation follows these key stages:

#### **Request Processing**
- **ControlReadRequest**: Reads ship requests from the central `requests` queue using the `read` macro
- Extracts the requested side ("west" or "east") and determines the opposite side
- Processes requests sequentially in a FIFO manner

#### **Door Safety Protocol**
- **ControlCloseDoors**: Ensures the requested door is closed before any water level adjustments
- **ControlCheckOppositeDoor**: Verification step ensuring both doors are checked
- **ControlCloseDoor2**: Closes the opposite door if open
- This two-phase closing ensures the critical safety invariant: both doors are never simultaneously open

#### **Water Level Adjustment**
- **ControlSetTargetLevel**: Uses `LowSide()` and `HighSide()` helper functions to determine the correct target water level based on:
  - The requested door side
  - The lock's orientation (`lockOrientation` = "west_low" or "east_low")
- **ControlAdjustWaterLevel**: Branches based on current vs. target water level
  - If water needs lowering: Opens low valve → waits for water to reach "low" → closes valve
  - If water needs raising: Opens high valve → waits for water to reach "high" → closes valve
- **Wait states**: `ControlWaitValveLow/High`, `ControlWaitWaterLow/High`, `ControlWaitCloseValveLow/High` ensure proper sequencing with the lock process through interleaving labels

#### **Door Opening & Permission Grant**
- **ControlOpenRequestedDoor**: Commands the lock to open the appropriate door
- **ControlGrantPermission**: Sends permission to the ship via the `permissions` queue with `[lock |-> 1, granted |-> TRUE]`

### 1.2 Properties Implemented (Invariants & Liveness)

#### **Safety Invariants**
- **DoorsMutex**: `~(doorsOpen["west"] /\ doorsOpen["east"])` - Ensures mutual exclusion of doors
- **DoorsOpenValvesClosed**: Uses `LowSide/HighSide` helpers to ensure:
  - When the lower door is open, the higher valve is closed
  - When the higher door is open, the lower valve is closed
- **DoorsOpenWaterlevelRight**: Ensures doors only open when water level matches:
  - Lower door open ⇒ water level is "low"
  - Higher door open ⇒ water level is "high"
- **TypeOK**: Validates all variable types match their expected domains
- **MessagesOK**: Ensures message queues don't overflow (≤1 message for single ship)

#### **Liveness Properties**
- **RequestLockFulfilled**: `(shipLocation = 0 ~> InLock)` - Eventually the ship enters the lock after requesting
- **WaterlevelChange**: `[]<>(waterLevel = "high") /\ []<>(waterLevel = "low")` - Water level changes infinitely often
- **RequestsShips**: `[]<>(Len(requests) > 0)` - Ship makes requests infinitely often
- **ShipsReachGoals**: Ship reaches both endpoints (`EastEnd` and `WestEnd`) infinitely often

### 1.3 Orientation-Agnostic Design
The implementation uses `LowSide(lockOrientation)` and `HighSide(lockOrientation)` helper functions throughout, making it work correctly regardless of whether the lock is oriented "west_low" or "east_low".

---

## Task 2: Multiple Locks & Multiple Ships Model (`lock_multiple.tla`)

### 2.1 Global Variable Extensions

The multiple model extends single-lock variables to arrays/maps:
- **Lock variables**: `lockOrientations[l]`, `doorsOpen[l][side]`, `valvesOpen[l][side]`, `waterLevel[l]`, `lockCommand[l]`
- **Ship variables**: `shipLocations[s]`, `shipStates[s]`, `permissions[s]` (per-ship permission queues)
- **New variable**: `moved[s]` - Boolean flag for each ship to signal movement completion

Lock orientations alternate: `[l \in Locks |-> IF l%2=0 THEN "west_low" ELSE "east_low"]`

### 2.2 Control Process Implementation (`controlProcess`)

The multi-lock controller extends the single-lock logic with capacity management and non-blocking behavior:

#### **Request Processing with Capacity Checking**
- **ControlReadRequest**: Reads from central `requests` queue (shared by all ships)
- **ControlCheckCapacity**: 
  - Determines target location based on ship's current position and request
  - Counts ships at target location using `Cardinality({s \in Ships : shipLocations[s] = targetLocation})`
  - Checks capacity constraints:
    - For lock chambers (odd locations): `shipsAtTarget < MaxShipsLock`
    - For outside locations (even): `shipsAtTarget < MaxShipsLocation`
  - Sets `canGrant` flag accordingly

#### **Decision Point**
- **ControlDecideGrant**: Branches based on capacity
- **ControlDenyPermission**: If capacity exceeded, sends `[lock |-> req.lock, granted |-> FALSE]` to `permissions[req.ship]`
- Otherwise, proceeds with lock preparation (identical to Task 1 but using array indices `[req.lock]`)

#### **Lock Preparation (Per-Lock Operations)**
- All lock operations index by `req.lock`:
  - `doorsOpen[req.lock][side]`
  - `waterLevel[req.lock]`
  - `lockCommand[req.lock]`
- Uses `lockOrientations[req.lock]` for orientation-specific logic

#### **Non-Blocking Continuation**
- **ControlObserveMove**: After granting permission, waits for `moved[req.ship]` to be TRUE
- **ControlClearMoved**: Clears the flag `moved[req.ship] := FALSE`
- This allows the controller to observe ship movement without blocking other requests

### 2.3 Ship Process Extensions

Ships are modified to:
- Use `shipLocations[self]` and `shipStates[self]` for per-ship state
- Calculate lock IDs dynamically: `GetLock(shipLocations[self] ± 1)`
- Write to per-ship permission queues: `permissions[self]`
- Set `moved[self] := TRUE` after each successful movement
- Initialize at alternating endpoints: even-ID ships start at WestEnd (0), odd-ID ships at EastEnd

### 2.4 Lock Process Extensions

Lock processes operate independently per lock:
- Each lock `self` manages its own:
  - `doorsOpen[self][side]`
  - `valvesOpen[self][side]`
  - `waterLevel[self]`
  - `lockCommand[self]`
- Uses `lockOrientations[self]` in water level updates

### 2.5 Properties Implemented (Extended for Multiple Entities)

#### **Safety Invariants (Quantified over Locks/Ships)**
- **DoorsMutex**: `\A l \in Locks: ~(doorsOpen[l]["west"] /\ doorsOpen[l]["east"])`
- **DoorsOpenValvesClosed**: `\A l \in Locks: ...` (same logic per lock)
- **DoorsOpenWaterlevelRight**: `\A l \in Locks: ...` (same logic per lock)
- **MaxShipsPerLocation**: New capacity invariant:
  ```tla
  \A loc \in Locations:
    IF IsLock(loc) 
    THEN Cardinality({s \in Ships : shipLocations[s] = loc}) <= MaxShipsLock
    ELSE Cardinality({s \in Ships : shipLocations[s] = loc}) <= MaxShipsLocation
  ```
- **TypeOK**: Extended to check all locks and ships
- **MessagesOK**: `Len(requests) <= NumShips /\ \A s \in Ships: Len(permissions[s]) <= 1`

#### **Liveness Properties (Quantified over Locks/Ships)**
- **RequestLockFulfilled**: `\A s \in Ships: [](ShipRequestingLock(s) => <>(InLock(s)))`
  - Uses helper: `ShipRequestingLock(s) == \E i \in 1..Len(requests): requests[i].ship = s /\ ~InLock(s)`
- **WaterlevelChange**: `\A l \in Locks: []<>(waterLevel[l] = "high") /\ []<>(waterLevel[l] = "low")`
- **RequestsShips**: `\A s \in Ships: []<>(\E i \in 1..Len(requests): requests[i].ship = s)`
- **ShipsReachGoals**: `\A s \in Ships: []<>(shipLocations[s] = WestEnd) /\ []<>(shipLocations[s] = EastEnd)`

### 2.6 Bonus Property
- **AllShipsCannotReachGoal**: `~(\A s \in Ships: shipStates[s] = "goal_reached")`
  - When TLC finds this property FALSE, the counterexample demonstrates a deadlock-free schedule where all ships successfully reach their goals

---

## Key Implementation Patterns

### Communication Architecture
- **Central request queue**: Single FIFO `requests` queue for all ships
- **Per-ship permission queues**: `permissions[s]` ensures ships receive their own responses
- **Command-response protocol**: Lock processes await commands via `lockCommand[l]`, respond by setting `.command := "finished"`

### Safety Mechanisms
1. **Two-phase door closing**: Always close both doors before water level changes
2. **Water-level synchronization**: Only open doors when chamber water level matches outside
3. **Valve-door interlocking**: Valves closed when doors open, preventing uncontrolled flow
4. **Capacity enforcement**: Controller checks location capacity before granting permissions

### Non-Blocking Controller
- The multiple-locks controller uses `moved[s]` flags to observe ship movements
- After granting permission, it waits for the ship to signal completion before processing next request
- This prevents the controller from being blocked on any single ship

### Orientation Independence
Both models use `LowSide(orientation)` and `HighSide(orientation)` helpers extensively, ensuring correctness for both "west_low" and "east_low" orientations without duplicating logic.

---

## Verification Approach

Both models have been verified using TLC model checker with:
- **Constants**: Configurable via `MC.cfg` files in `lock_system.toolbox/model_single/` and `model_multiple/`
- **Fairness**: `FairSpec` includes weak fairness on all processes to ensure liveness properties hold
- **State space exploration**: Exhaustive for small configurations (1 lock/ship, 2-4 locks/2-3 ships)
- **Deadlock checking**: Enabled to ensure system never reaches an unrecoverable state

The implementations satisfy all required safety invariants and liveness properties as specified in the assignment description sections 4 and 5.
