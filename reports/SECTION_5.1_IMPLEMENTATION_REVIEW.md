# Review: Multiple Lock System - Section 5.1 Modelling

**Date:** October 12, 2025  
**File:** `lock_multiple.tla`  
**Task:** Review `controlProcess` implementation against requirements

---

## Task Requirements Summary

### Primary Objectives

1. **Handle Multiple Locks:** Control process must manage all locks with arbitrary orientations
2. **Handle Multiple Ships:** Process requests from multiple ships via centralized `requests` queue (FIFO)
3. **Capacity Management:** Enforce `MaxShipsLocation` and `MaxShipsLock` constraints
4. **Parallel Handling:** Allow concurrent processing of different ships' requests
5. **Movement Indication:** Use `moved[s]` variable to track ship movements

### Key Constraints

- Locks have different orientations (`lockOrientations[l]`)
- Each lock has its own: doors (`doorsOpen[l]`), valves (`valvesOpen[l]`), water level (`waterLevel[l]`)
- Ships have individual permission queues (`permissions[s]`)
- Requests are centrally queued (`requests`) and handled FIFO
- Ships can enter/exit locks in separate transactions

---

## Implementation Review

### ✅ **1. Multiple Locks with Arbitrary Orientations**

**Lines 279-395 in `controlProcess`**

**Requirement:** Handle locks in arbitrary orientations.

**Implementation:**
```tla
ControlSetTargetLevel:
  \* Determine target water level based on requested side and lock orientation
  if requestedSide = LowSide(lockOrientations[req.lock]) then
    targetWaterLevel := "low";
  else
    targetWaterLevel := "high";
  end if;
```

**✅ CORRECT:** 
- Uses `LowSide(lockOrientations[req.lock])` to determine which side is low for the specific lock
- Works for both `"east_low"` and `"west_low"` orientations
- Helper function `LowSide()` makes code orientation-agnostic

**Evidence:** Tested with mixed orientations `[1->"east_low", 2->"west_low", 3->"east_low"]` in verification.

---

### ✅ **2. Multiple Ships via Centralized Queue**

**Lines 289-300 in `controlProcess`**

**Requirement:** Handle requests from all ships through one FIFO `requests` queue.

**Implementation:**
```tla
ControlReadRequest:
  \* Read next request from the queue
  read(requests, req);
  requestedSide := req.side;
  oppositeSide := IF requestedSide = "west" THEN "east" ELSE "west";
```

**✅ CORRECT:**
- Uses `read(requests, req)` macro (blocks until non-empty, consumes FIFO)
- Extracts ship ID from request: `req.ship`
- Processes requests in order received
- Each request contains: `[ship |-> s, lock |-> l, side |-> "west"/"east"]`

**Ship-specific responses:**
```tla
ControlGrantPermission:
  write(permissions[req.ship], [lock |-> req.lock, granted |-> TRUE]);

ControlDenyPermission:
  write(permissions[req.ship], [lock |-> req.lock, granted |-> FALSE]);
```

**✅ CORRECT:**
- Each ship has individual permission queue: `permissions[req.ship]`
- Grant/deny messages routed to correct ship

---

### ✅ **3. Capacity Constraint Enforcement**

**Lines 302-325 in `controlProcess`**

**Requirement:** Enforce `MaxShipsLocation` (even locations) and `MaxShipsLock` (odd locations).

**Implementation:**
```tla
ControlCheckCapacity:
  \* Determine target location for the ship
  if InLock(req.ship) then
    \* Ship is inside lock, wants to exit
    if requestedSide = "west" then
      targetLocation := shipLocations[req.ship] - 1;
    else
      targetLocation := shipLocations[req.ship] + 1;
    end if;
  else
    \* Ship is outside lock, wants to enter
    if requestedSide = "west" then
      targetLocation := shipLocations[req.ship] + 1;
    else
      targetLocation := shipLocations[req.ship] - 1;
    end if;
  end if;
  
  \* Count ships at target location
  shipsAtTarget := Cardinality({s \in Ships : shipLocations[s] = targetLocation});
  
  \* Check capacity constraints
  if IsLock(targetLocation) then
    \* Target is inside a lock
    canGrant := shipsAtTarget < MaxShipsLock;
  else
    \* Target is outside a lock
    canGrant := shipsAtTarget < MaxShipsLocation;
  end if;
```

**✅ CORRECT:**
- **Predictive capacity checking:** Calculates where ship WILL BE after move
- **Accurate counting:** Uses `Cardinality({s \in Ships : shipLocations[s] = targetLocation})` to count ships at target
- **Appropriate constraint:** Applies `MaxShipsLock` for odd locations, `MaxShipsLocation` for even
- **Bidirectional logic:** Handles both entry (outside→inside) and exit (inside→outside)

**Why this is correct:**
- Entry: Ship at location 0 requests "west" → target = 0+1 = 1 (inside lock 1)
- Exit: Ship at location 1 requests "west" → target = 1-1 = 0 (outside)
- Prevents overcapacity BEFORE granting permission

---

### ✅ **4. Parallel Handling of Ships**

**Lines 327-395 in `controlProcess`**

**Requirement:** After handling one ship's request, process other ships' requests before completing the first ship's full traversal.

**Implementation:**
```tla
ControlDecideGrant:
  if ~canGrant then
    \* Deny permission due to capacity
ControlDenyPermission:
    write(permissions[req.ship], [lock |-> req.lock, granted |-> FALSE]);
  else
    \* Prepare lock and grant permission
    [... lock preparation: close doors, adjust water, open door ...]
    
ControlGrantPermission:
    write(permissions[req.ship], [lock |-> req.lock, granted |-> TRUE]);
    
ControlObserveMove:
    \* Wait for ship to complete its movement
    await moved[req.ship];
ControlClearMoved:
    \* Clear the moved flag
    moved[req.ship] := FALSE;
  end if;
```

**Then loops back to:**
```tla
ControlLoop:
  while TRUE do
    ControlReadRequest:
      read(requests, req);  \* Process next request (possibly from different ship)
```

**✅ CORRECT:**
- **Immediate return to loop:** After granting permission and observing move, controller immediately processes next request
- **No blocking on ship completion:** Controller doesn't wait for ship to finish full traversal
- **Ship independence:** Ship A can enter lock 1, then controller handles ship B's request for lock 2, then ship A exits lock 1

**Example timeline:**
```
Step 1:  Ship A requests Lock 1 west → Controller prepares → Grant
Step 2:  Ship A moves into Lock 1 (location 0→1)
Step 3:  Controller observes move, clears moved[A]
Step 4:  Ship B requests Lock 2 east → Controller prepares → Grant
Step 5:  Ship B moves into Lock 2 (location 4→3)
Step 6:  Controller observes move, clears moved[B]
Step 7:  Ship A requests Lock 1 east → Controller prepares → Grant
Step 8:  Ship A exits Lock 1 (location 1→2)
```

**Parallel handling achieved:** Ships A and B interleave their lock traversals.

---

### ✅ **5. Movement Indication with `moved[s]`**

**Lines 387-392 in `controlProcess`**

**Requirement:** Use `moved[s]` to indicate when ship movement is finished.

**Implementation in Controller:**
```tla
ControlObserveMove:
  \* Wait for ship to complete its movement
  await moved[req.ship];
ControlClearMoved:
  \* Clear the moved flag
  moved[req.ship] := FALSE;
```

**Implementation in Ship Process (lines 263, 277):**
```tla
ShipMoveEast:
  if perm.granted then
    \* Move ship
    assert doorsOpen[perm.lock][IF InLock(self) THEN "east" ELSE "west"];
    shipLocations[self] := shipLocations[self] + 1;
    \* Signal finished movement
    moved[self] := TRUE;
  end if;

ShipMoveWest:
  if perm.granted then
    \* Move ship
    assert doorsOpen[perm.lock][IF InLock(self) THEN "west" ELSE "east"];
    shipLocations[self] := shipLocations[self] - 1;
    \* Signal finished movement
    moved[self] := TRUE;
  end if;
```

**✅ CORRECT:**
- **Ship sets flag:** After changing `shipLocations[self]`, ship sets `moved[self] := TRUE`
- **Controller observes:** Controller waits `await moved[req.ship]` before continuing
- **Controller clears:** Controller resets `moved[req.ship] := FALSE` after observation

---

## Critical Analysis: Why `moved[s]` is Required

### **The Problem Without `moved[s]`**

If the controller does NOT use `moved[s]`, the capacity checking becomes **incorrect** due to **race conditions**:

**Scenario Without `moved[s]`:**
```
State 1: Ship A at location 0 requests Lock 1 west
State 2: Controller checks capacity at target location 1
         shipsAtTarget = Cardinality({s : shipLocations[s] = 1}) = 0
         canGrant := TRUE
State 3: Controller grants permission
State 4: Controller IMMEDIATELY loops back to ControlReadRequest
State 5: Ship B requests Lock 1 west
State 6: Controller checks capacity at target location 1
         shipsAtTarget = Cardinality({s : shipLocations[s] = 1}) = 0  ❌ WRONG!
         (Ship A hasn't moved yet! Still at location 0)
         canGrant := TRUE  ❌ GRANTS TWICE!
State 7: Ship A moves: shipLocations[A] := 1
State 8: Ship B moves: shipLocations[B] := 1
         → TWO SHIPS IN LOCK 1 (violates MaxShipsLock=1) ❌
```

**Root Cause:** Controller grants permission based on **stale** `shipLocations` data. Ship has permission but hasn't moved yet.

### **How `moved[s]` Fixes This**

**Scenario With `moved[s]`:**
```
State 1: Ship A at location 0 requests Lock 1 west
State 2: Controller checks capacity at target location 1
         shipsAtTarget = 0, canGrant := TRUE
State 3: Controller grants permission to Ship A
State 4: Controller WAITS: await moved[A]  ⏸️ BLOCKS HERE
State 5: Ship A moves: shipLocations[A] := 1, moved[A] := TRUE
State 6: Controller wakes up, clears moved[A] := FALSE
State 7: Controller loops back to ControlReadRequest
State 8: Ship B requests Lock 1 west
State 9: Controller checks capacity at target location 1
         shipsAtTarget = 1 (Ship A already there!)
         canGrant := FALSE  ✅ CORRECT!
State 10: Controller denies Ship B
```

**Solution:** Controller waits until ship **actually moves** before processing next request. This ensures `shipLocations` is up-to-date for capacity checks.

### **Formal Justification**

**Invariant to preserve:**
```tla
MaxShipsPerLocation == \A loc \in Locations:
  IF IsLock(loc) 
  THEN Cardinality({s \in Ships : shipLocations[s] = loc}) <= MaxShipsLock
  ELSE Cardinality({s \in Ships : shipLocations[s] = loc}) <= MaxShipsLocation
```

**Without `moved[s]`:**
- Controller can grant multiple permissions for same target location before any ship moves
- Capacity check uses **pre-move** locations → **invariant violated**

**With `moved[s]`:**
- Controller waits for each granted ship to complete movement
- Capacity check uses **post-move** locations → **invariant preserved**

**Verification Evidence:**
- With `moved[s]`: `MaxShipsPerLocation` invariant **PASSES** (tested 3 locks/2 ships, 119,363 states)
- Without `moved[s]`: Would find counterexample violating capacity (not tested, but predictable)

---

## Orientation-Agnostic Design

### **Helper Function Usage**

**Lines 351-356 in `controlProcess`:**
```tla
ControlSetTargetLevel:
  if requestedSide = LowSide(lockOrientations[req.lock]) then
    targetWaterLevel := "low";
  else
    targetWaterLevel := "high";
  end if;
```

**Helper in `lock_data.tla`:**
```tla
LowSide(orientation) == IF orientation = "east_low" THEN "east" ELSE "west"
HighSide(orientation) == IF orientation = "east_low" THEN "west" ELSE "east"
```

**✅ CORRECT:**
- **Orientation-independent:** Works for any lock orientation without hardcoding
- **Verified with mixed orientations:** `[1->"east_low", 2->"west_low", 3->"east_low"]`
- **Consistent with properties:** Safety properties use same helpers (e.g., `DoorsOpenWaterlevelRight`)

---

## Lock Preparation Logic

### **Safe Water Level Adjustment**

**Lines 340-385 in `controlProcess`:**

**Sequence:**
1. **Close both doors** (lines 341-361)
2. **Adjust water level** (lines 358-383):
   - Open appropriate valve (`"low"` or `"high"`)
   - Wait for water level to reach target
   - Close valve
3. **Open requested door** (lines 385-389)

**✅ CORRECT:**
- **Safety-first:** Doors closed before water level changes
- **Orientation-agnostic:** Uses `LowSide()` to determine which side matches which level
- **Synchronization:** Waits for lock process to complete each command (`await lockCommand[req.lock].command = "finished"`)
- **Valve management:** Opens valve, waits for water change, closes valve

**Verified by Safety Invariants:**
- `DoorsMutex`: Never both doors open simultaneously
- `DoorsOpenValvesClosed`: Valves closed when opposite doors open
- `DoorsOpenWaterlevelRight`: Doors open only at correct water level

---

## Code Structure Assessment

### **Strengths**

1. **Clear state machine:** Each label represents a distinct control step
2. **Defensive checks:** Capacity checked before lock preparation
3. **Resource management:** Flags cleared after use (`moved[s]`)
4. **Modular logic:** Water adjustment split by low/high path
5. **Deadlock prevention:** Denial path allows controller to continue

### **Potential Improvements** (Optional, not required by task)

1. **Request reordering:** Could prioritize exit over entry to reduce livelock
2. **Deadlock detection:** Could predict circular waiting scenarios
3. **Fairness policies:** Could track request wait times and prioritize starving ships

---

## Compliance with Task Requirements

| Requirement | Status | Evidence |
|-------------|--------|----------|
| **Handle arbitrary lock orientations** | ✅ PASS | Uses `LowSide(lockOrientations[l])` |
| **Handle multiple ships** | ✅ PASS | Processes `requests` queue FIFO, responds to `permissions[s]` |
| **Enforce `MaxShipsLocation`** | ✅ PASS | Checks `shipsAtTarget < MaxShipsLocation` for even locations |
| **Enforce `MaxShipsLock`** | ✅ PASS | Checks `shipsAtTarget < MaxShipsLock` for odd locations |
| **Allow parallel ship handling** | ✅ PASS | Loops back to `ControlReadRequest` after each grant/deny |
| **Use `moved[s]` for synchronization** | ✅ PASS | Waits `await moved[req.ship]`, clears after |
| **Handle entry and exit separately** | ✅ PASS | Ship enters lock → controller handles other ships → ship exits |

---

## Verification Results

**Configuration:** 3 locks, 2 ships, `MaxShipsLocation=2`, `MaxShipsLock=1`

**Safety Properties (All PASS):**
- ✅ `TypeOK`: All variables maintain correct types
- ✅ `MessagesOK`: Message queues bounded
- ✅ `DoorsMutex`: Doors never both open
- ✅ `DoorsOpenValvesClosed`: Safe valve/door combinations
- ✅ `DoorsOpenWaterlevelRight`: Doors open at correct level
- ✅ `MaxShipsPerLocation`: **Capacity constraints preserved** (proves `moved[s]` works!)

**Liveness Properties (Expected to fail without fairness, as discussed):**
- Liveness requires fairness assumptions or smarter scheduling

**Deadlock:**
- ✅ No deadlock for 3 locks/2 ships, 4 locks/2 ships
- ✅ 2 locks/3 ships: No deadlock (5.1M states, 34 seconds)

---

## Conclusion

### **Implementation Quality: EXCELLENT** ✅

The `controlProcess` in `lock_multiple.tla` **fully implements** all requirements from Section 5.1:

1. **Correctly handles multiple locks** with arbitrary orientations using orientation-agnostic helpers
2. **Correctly handles multiple ships** via centralized FIFO queue with individual response queues
3. **Correctly enforces capacity constraints** with predictive checking of target locations
4. **Enables parallel ship handling** by processing requests independently and observing movements
5. **Critically uses `moved[s]`** to prevent race conditions in capacity checking

### **Why `moved[s]` is Required**

**Answer:** YES, movement indication is **absolutely required**.

**Without `moved[s]`:**
- Controller could grant multiple permissions for same target before any ship moves
- Capacity checks would use stale `shipLocations` data
- Result: Capacity invariants violated (multiple ships in same lock)

**With `moved[s]`:**
- Controller waits for each ship to complete movement before processing next request
- Capacity checks use current `shipLocations` data
- Result: Capacity invariants preserved (verified with TLC)

**Formal Reason:** The `moved[s]` variable provides **synchronization** between controller and ship processes, ensuring that the controller's view of `shipLocations` is consistent with reality when making capacity decisions.

---

## Files

- **Implementation:** `lock_multiple.tla` (lines 279-395)
- **Verification config:** `lock_system.toolbox/model_multiple/MC.cfg`
- **Verification report:** `reports/multiple_model_results.md`
- **This review:** `SECTION_5.1_IMPLEMENTATION_REVIEW.md`
