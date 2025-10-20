# Deep Analysis: 3+ Ship Liveness Violation

**Date**: October 16, 2025  
**Configuration**: 1 Lock, 3 Ships, MaxShipsLocation=3, MaxShipsLock=1  
**Status**: All attempted solutions (B and D) have failed with assertion errors

---

## 1. Problem Statement

With 3+ ships and limited lock capacity (MaxShipsLock=1), the controller faces a **synchronization dilemma**:
- **If controller waits** for ship movement: Blocks processing other ships → Liveness violation
- **If controller doesn't wait**: Processes next request immediately → Closes door while ship is moving → Assertion failure

---

## 2. Understanding Ship Movement Flow

### 2.1 Ship Request Types

There are **4 types of requests** based on ship location and direction:

| Request Type | Ship Location | Direction | Request Side | Queue Used | Notes |
|--------------|---------------|-----------|--------------|------------|-------|
| **ENTRY_WEST** | Even (outside) | Going East | `"west"` | `entryRequests` | Ship wants to enter lock from west |
| **ENTRY_EAST** | Even (outside) | Going West | `"east"` | `entryRequests` | Ship wants to enter lock from east |
| **EXIT_EAST** | Odd (inside) | Going East | `"east"` | `exitRequests` | Ship wants to exit lock to east |
| **EXIT_WEST** | Odd (inside) | Going West | `"west"` | `exitRequests` | Ship wants to exit lock to west |

### 2.2 Ship Movement Mechanics

#### Entry Request (Outside → Inside Lock)
```
Ship at location 0 (outside, west end), going east:
1. ShipRequestWest: Append to entryRequests [ship, lock 1, side "west"]
2. ShipWaitForWest: Block until permission received
3. ShipMoveEast: Assert west door open, move from 0 → 1 (enter lock)
```

#### Exit Request (Inside → Outside Lock)
```
Ship at location 1 (inside lock 1), going east:
1. ShipRequestEastInLock: Append to exitRequests [ship, lock 1, side "east"]
2. ShipWaitForEastInLock: Block until permission received
3. ShipMoveEast: Assert east door open, move from 1 → 2 (exit lock)
```

**KEY INSIGHT**: The assertion checks that the **correct door** for the ship's movement direction is open:
- `ShipMoveEast`: Checks `doorsOpen[lock][IF InLock(self) THEN "east" ELSE "west"]`
  - If inside lock → check **east** door
  - If outside lock → check **west** door (to enter from west)
- `ShipMoveWest`: Checks `doorsOpen[lock][IF InLock(self) THEN "west" ELSE "east"]`
  - If inside lock → check **west** door
  - If outside lock → check **east** door (to enter from east)

---

## 3. Detailed Error Trace Analysis (Solution D Failure)

### Initial State (State 1)
- Ship 2: location 0, state "go_to_east"
- Ship 3: location 2, state "go_to_west"
- Ship 4: location 0, state "go_to_east"

### Critical Sequence

#### States 3-25: Controller Grants Ship 3 Permission
- **State 4**: Ship 3 (at location 2, inside lock 1) requests **east door** (going west, needs to enter from east side)
  - Appends to `entryRequests` (Ship 3 is at location 2, which is EVEN = outside perspective)
  - **WAIT**: Ship 3 is at location 2, but `GetLock(2) = (2+1)÷2 = 1`, so it's "near" lock 1
  - Ship 3 state is "go_to_west", so needs to move west (location 2 → 1)
  - From location 2 (outside), entering lock 1 via **east door**

- **State 5-24**: Controller processes Ship 3's request
  - Closes both doors
  - Water level already matches (low)
  - Opens **east door**
  - `doorsOpen = <<[west FALSE, east TRUE]>>`

- **State 25**: Controller grants permission
  - `permissions[3] = <<[lock 1, granted TRUE]>>`
  - Moves to `ControlCheckIfExitRequest`

#### State 26: **CRITICAL DECISION POINT**
```tlaplus
ControlCheckIfExitRequest:
  if IsLock(shipLocations[ship_id]) then
    goto ControlWaitForShipMovement;  // WAIT for exit
  else
    goto ControlNextRequest;  // NO WAIT for entry
  end if;
```

- `ship_id = 3`
- `shipLocations[3] = 2`
- `IsLock(2) = 2 % 2 = 0` → **FALSE** (even location = outside)
- **Decision**: NOT an exit request → `goto ControlNextRequest` (NO WAIT)

**This is where the logic breaks down!**

#### State 27: Ship 2 Sends Request
- Ship 2 (at location 0, going east) requests west door
- `entryRequests = <<[ship 2, lock 1, side "west"]>>`
- Controller is at `ControlNextRequest` (no longer committed to Ship 3)

#### States 28-34: Controller Processes Ship 2
- Controller reads Ship 2's request
- Checks conditions, capacity → grants
- Starts closing doors: `lockCommand = [change_door, FALSE, "east"]`
- **East door starts closing** while Ship 3 still needs it!

#### State 35: **ASSERTION FAILURE**
- Ship 3 tries `ShipMoveWest`
- Ship 3 is at location 2 (outside), so `InLock(3) = FALSE`
- Assertion checks: `doorsOpen[1][IF FALSE THEN "west" ELSE "east"]`
  - → `doorsOpen[1]["east"]`
  - → **FALSE** (door was closed by controller)
- **ASSERTION FAILS**: Expected east door open for Ship 3 to move west

---

## 4. Root Cause Analysis

### 4.1 The Fundamental Problem

The issue is **NOT** about distinguishing entry vs exit requests. The issue is about **lock commitment**:

1. **When controller opens a door for a ship**, it creates a **contract**: "This door is open for YOU to move"
2. **The ship expects this contract to hold** until it completes its movement
3. **The controller breaks this contract** when it processes another request for the same lock before the ship moves

### 4.2 Why Solution B Failed (Queue-Based Wait)

Solution B tried to skip wait if queues were not empty:
```
if exitRequests = <<>> /\ entryRequests = <<>> then
  wait for ship movement
else
  goto next request  // PROBLEM: Door still open, contract broken
end if
```

**Failure**: Once door is open, controller is committed. Can't use queue state to decide.

### 4.3 Why Solution D Failed (Location-Based Wait)

Solution D tried to wait only for exits:
```
if IsLock(shipLocations[ship_id]) then
  wait for ship movement  // Exit
else
  goto next request  // Entry - PROBLEM: Misclassified Ship 3
end if
```

**Failure**: Ship 3 at location 2 is classified as "outside" because `IsLock(2) = FALSE`, but it still needs the door to remain open. The classification is **wrong** because:
- Ship 3 at location 2 is **entering** lock 1 from the east side
- It's an **entry** request but the door must stay open until entry completes
- Controller skips wait → processes Ship 2 → closes east door → Ship 3 fails

### 4.4 The Core Issue

**ALL entry and exit requests require the door to stay open until the ship moves!**

The difference is not "who needs synchronization" but rather:
- **When can we safely close the door?**
- **When can we safely process the next request for the same lock?**

Answer: **Only after the ship has moved and the door is closed.**

---

## 5. The Real Problem: Lock State Management

### 5.1 Lock States

A lock goes through these states during request processing:

1. **IDLE**: Both doors closed, ready for new request
2. **PREPARING**: Closing doors, adjusting water level
3. **DOOR_OPEN**: Door open for granted ship (**CONTRACT ACTIVE**)
4. **SHIP_MOVING**: Ship is moving through door (contract being fulfilled)
5. **CLEANUP**: Closing door after ship moved
6. Back to **IDLE**

### 5.2 The Contract Invariant

```
∀ ship s, lock l, side d:
  IF permissions[s] = <<[lock l, granted TRUE]>>
     AND doorsOpen[l][d] = TRUE
  THEN doorsOpen[l][d] must remain TRUE
       until s completes its move
```

### 5.3 Why Skipping Wait Breaks This

When controller skips `ControlWaitForShipMovement`:
1. Door is open (state = DOOR_OPEN)
2. Contract is active (ship has permission)
3. Controller goes to `ControlNextRequest`
4. Controller reads next request **for the same lock**
5. Controller starts processing → closes door
6. **CONTRACT VIOLATED** → Ship assertion fails

---

## 6. Configuration Analysis

### Why 2 Ships Work, 3 Ships Fail

#### With 2 Ships (WORKS):
```
State: Ship A inside, Ship B outside
1. Ship A requests exit → Controller grants → waits
2. Ship B is blocked (can't send request while controller waits)
3. Ship A moves → Controller closes door
4. Ship B now sends request → Controller processes
```
**No contention** because there are at most 2 ships trying to use 1 lock, and capacity is 1.

#### With 3 Ships (FAILS):
```
State: Ship A inside, Ships B & C outside
1. Ship A requests exit → Controller grants
2. If controller waits: Ship B sends request (queued)
   - Ship C may also send request (queued)
   - Controller blocks on Ship A → Ships B & C can't be processed
   - **LIVENESS VIOLATION**: Ships B & C starve
3. If controller doesn't wait: Ship B's request processed immediately
   - Controller closes door for Ship A
   - **SAFETY VIOLATION**: Ship A assertion fails
```

**Catch-22**: Wait causes liveness violation, no-wait causes safety violation.

---

## 7. Why This Is Hard

The problem is **not solvable** with the current controller architecture because:

1. **Single-threaded controller**: Can only process one request at a time
2. **Blocking wait on ship movement**: Controller can't do anything else while waiting
3. **Shared resource (lock)**: Multiple ships need the same lock
4. **Capacity constraint**: MaxShipsLock=1 means only one ship in lock at a time

The controller faces:
- **Option A**: Wait for ship → Blocks other ships → Liveness violation
- **Option B**: Don't wait → Processes conflicting requests → Safety violation

---

## 8. Proposed Solutions (Refined)

### Solution Alpha: Per-Lock Wait State (NEW)

**Idea**: Don't wait on the ship, wait on the **lock being ready**.

```tlaplus
\* Add new variable:
lockBusy: [Locks -> BOOLEAN]  \* TRUE when lock has active contract

ControlGrantPermission:
  write(permissions[ship_id], [lock |-> lock_id, granted |-> TRUE]);
  lockBusy[lock_id] := TRUE;  \* Mark lock as busy
  goto ControlNextRequest;  \* Don't wait here!

ControlReadRequest:
  if exitRequests /= <<>> then read(exitRequests, req)
  else read(entryRequests, req);
  ship_id := req.ship;
  lock_id := req.lock;
  side := req.side;
  \* CHECK IF LOCK IS AVAILABLE
  if lockBusy[lock_id] then
    \* Re-queue this request (put back)
    if IsLock(shipLocations[ship_id]) then
      write(exitRequests, req);
    else
      write(entryRequests, req);
    end if;
    goto ControlNextRequest;  \* Try next request
  else
    goto ControlCheckConditions;
  end if;

\* Ship process after moving:
ShipMoveEast/ShipMoveWest:
  if perm[self].granted then
    assert door is open;
    move ship;
    moved[self] := TRUE;
    \* IMPORTANT: Clear lock busy after moving
    lockBusy[perm[self].lock] := FALSE;
  end if;
```

**Pros**:
- Lock-centric instead of ship-centric
- Controller never blocks
- Requests for busy locks are re-queued
- Ships clear busy flag after moving

**Cons**:
- Modifies ship process (but minimal)
- Re-queuing might cause starvation (need fairness)

---

### Solution Beta: Explicit Door Contracts (NEW)

**Idea**: Track which ship has the "door contract" for each lock.

```tlaplus
\* Add new variables:
doorContract: [Locks -> {0} \cup Ships]  \* 0 = no contract, else ship id

ControlGrantPermission:
  write(permissions[ship_id], [lock |-> lock_id, granted |-> TRUE]);
  doorContract[lock_id] := ship_id;  \* Ship now owns door contract
  goto ControlNextRequest;

ControlReadRequest:
  \* Read request as before
  \* CHECK IF LOCK HAS ACTIVE CONTRACT
  if doorContract[lock_id] /= 0 /\ doorContract[lock_id] /= ship_id then
    \* Another ship owns door contract, re-queue
    if IsLock(shipLocations[ship_id]) then
      write(exitRequests, req);
    else
      write(entryRequests, req);
    end if;
    goto ControlNextRequest;
  else
    goto ControlCheckConditions;
  end if;

ControlWaitForShipMovement:
  \* NEW: Wait for ship to clear contract
  await doorContract[lock_id] = 0;
  lockCommand[lock_id] := [command |-> "change_door", open |-> FALSE, side |-> side];
  goto ControlWaitDoorClosed;

\* Ship process:
ShipMoveEast/ShipMoveWest:
  if perm[self].granted then
    assert door is open;
    move ship;
    moved[self] := TRUE;
    doorContract[perm[self].lock] := 0;  \* Clear contract
  end if;
```

**Pros**:
- Explicitly models the contract
- Controller checks for conflicts before processing
- Ship releases contract after moving

**Cons**:
- Still requires ship modification
- Controller still waits at cleanup phase

---

### Solution Gamma: Asynchronous Lock Cleanup (NEW)

**Idea**: Separate the "grant permission" phase from the "cleanup" phase.

```tlaplus
\* Add new controller process for cleanup:
process cleanupProcess = -1
variables
  cleanup_lock = 0;
  cleanup_side = "west";
begin
CleanupLoop:
  while TRUE do
    \* Wait for a lock that needs cleanup
    await \E l \in Locks: 
      lockCommand[l].command = "finished" 
      /\ lockCommand[l].open = TRUE
      /\ \E s \in Ships: 
           moved[s] /\ permissions[s] /= <<>> 
           /\ Head(permissions[s]).lock = l;
    
    \* Pick a lock to clean up
    with l \in {lock \in Locks: 
                lockCommand[lock].command = "finished" 
                /\ lockCommand[lock].open = TRUE
                /\ \E s \in Ships: moved[s] 
                     /\ permissions[s] /= <<>> 
                     /\ Head(permissions[s]).lock = lock} do
      cleanup_lock := l;
      cleanup_side := lockCommand[l].side;
    end with;
    
CleanupCloseDoor:
    lockCommand[cleanup_lock] := [command |-> "change_door", 
                                   open |-> FALSE, 
                                   side |-> cleanup_side];
CleanupWaitClosed:
    await lockCommand[cleanup_lock].command = "finished";
  end while;
end process;

\* Main controller:
ControlGrantPermission:
  write(permissions[ship_id], [lock |-> lock_id, granted |-> TRUE]);
  goto ControlNextRequest;  \* NO WAIT, let cleanup process handle it

ControlNextRequest:
  \* Just loop immediately
  goto ControlReadRequest;
```

**Pros**:
- Completely separates granting from cleanup
- Main controller never blocks
- Cleanup happens asynchronously

**Cons**:
- Adds complexity (second controller process)
- Need to ensure cleanup doesn't interfere with new requests

---

### Solution Delta: State Machine with Explicit Phases (NEW)

**Idea**: Add explicit state tracking per lock to know when it's safe to process next request.

```tlaplus
\* Add variable:
lockState: [Locks -> {"IDLE", "PREPARING", "DOOR_OPEN", "SHIP_MOVING", "CLEANUP"}]

ControlDecideGrantOrRetry:
  if grant then
    lockState[lock_id] := "PREPARING";
    goto ControlCloseBothDoors;
  else
    \* deny logic
  end if;

ControlWaitDoorOpen:
  await lockCommand[lock_id].command = "finished" /\ lockCommand[lock_id].open = TRUE;
  lockState[lock_id] := "DOOR_OPEN";
  goto ControlGrantPermission;

ControlGrantPermission:
  write(permissions[ship_id], [lock |-> lock_id, granted |-> TRUE]);
  lockState[lock_id] := "SHIP_MOVING";
  goto ControlNextRequest;  \* Don't wait

ControlReadRequest:
  \* Read as before
  if lockState[lock_id] /= "IDLE" then
    \* Lock not ready, re-queue
    if IsLock(shipLocations[ship_id]) then
      write(exitRequests, req);
    else
      write(entryRequests, req);
    end if;
    goto ControlNextRequest;
  else
    goto ControlCheckConditions;
  end if;

\* Separate cleanup loop in controller:
ControlCleanupCheck:
  \* Check if any lock needs cleanup
  if \E l \in Locks: lockState[l] = "SHIP_MOVING" /\ 
       \E s \in Ships: moved[s] /\ permissions[s] /= <<>> /\ Head(permissions[s]).lock = l then
    \* Pick lock to cleanup
    with l \in {lock \in Locks: lockState[lock] = "SHIP_MOVING" /\ ...} do
      cleanup_lock := l;
      lockState[l] := "CLEANUP";
    end with;
    goto ControlCleanupDoor;
  else
    goto ControlNextRequest;
  end if;

ControlCleanupDoor:
  lockCommand[cleanup_lock] := [change_door, FALSE, side];
  await lockCommand[cleanup_lock].command = "finished";
  lockState[cleanup_lock] := "IDLE";
  goto ControlNextRequest;
```

**Pros**:
- Explicit state machine
- Controller can check if lock is available before processing request
- No blocking on ship movement

**Cons**:
- Complex state management
- Need non-deterministic choice for cleanup checking

---

## 9. Comparison of Solutions

| Solution | Modifies Ship? | Adds Process? | Blocking? | Complexity | Likely to Work? |
|----------|----------------|---------------|-----------|------------|-----------------|
| **Alpha (Lock Busy)** | Yes (minimal) | No | No | Medium | **HIGH** |
| **Beta (Door Contract)** | Yes | No | Partial | Medium | **HIGH** |
| **Gamma (Async Cleanup)** | No | Yes | No | High | **MEDIUM** |
| **Delta (State Machine)** | No | No | No | Very High | **MEDIUM** |

---

## 10. Recommendation

**Implement Solution Alpha (Per-Lock Wait State)** because:

1. **Simplest effective solution**: Adds one boolean variable per lock
2. **Controller-focused**: Main logic change is in controller
3. **Minimal ship changes**: Only need to clear `lockBusy[lock]` after moving
4. **No blocking**: Controller never waits on ship movement
5. **Natural semantics**: Lock is busy when door contract exists

### Implementation Strategy

1. Add `lockBusy: [Locks -> BOOLEAN]` variable
2. Set `lockBusy[lock_id] := TRUE` when granting permission
3. Check `lockBusy[lock_id]` before processing requests in `ControlReadRequest`
4. Re-queue requests for busy locks
5. Ship clears `lockBusy[lock]` after moving (in `ShipMoveEast`/`ShipMoveWest`)
6. Remove original `ControlWaitForShipMovement` label entirely

### Why This Should Work

- **Prevents contract violation**: Can't process request for busy lock
- **Non-blocking**: Controller keeps processing other locks/ships
- **Lock-centric**: Natural alignment with the problem domain
- **Fairness**: Re-queued requests will be tried again (priority queues help)

---

## 11. Alternative: Simplest Possible Solution

If Solution Alpha still fails, consider **Solution Epsilon: Complete Removal of Wait + Ship-Controlled Cleanup**:

```tlaplus
\* Controller: NEVER wait for ship movement
ControlGrantPermission:
  write(permissions[ship_id], [lock |-> lock_id, granted |-> TRUE]);
  goto ControlNextRequest;  \* No wait at all

\* Ship: Close door AFTER moving
ShipMoveEast/ShipMoveWest:
  if perm[self].granted then
    assert door is open;
    move ship;
    \* SHIP CLOSES THE DOOR ITSELF
    lockCommand[perm[self].lock] := [change_door, FALSE, side];
    await lockCommand[perm[self].lock].command = "finished";
  end if;
```

**Trade-off**: Ships become responsible for closing doors. Controller never touches doors after opening.

---

## Conclusion

The 3+ ship problem is fundamentally a **resource contention + synchronization** problem. The controller's single-threaded, blocking architecture creates a deadlock between:
- **Safety** (don't close door while ship moving)
- **Liveness** (don't block indefinitely on one ship)

**Solution Alpha** (lock busy flag) is the most promising because it converts ship-level synchronization to lock-level availability checking, allowing the controller to remain non-blocking while preserving safety.
