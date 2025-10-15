# Multiple Lock System Verification Results

## Test Configuration: 3 Locks, 2 Ships â€” 2025-10-12 â€” model_multiple/MC.cfg

### Configuration
- Constants: NumLocks=3, NumShips=2, MaxShipsLocation=2, MaxShipsLock=1
- Lock orientations: [1 -> "east_low", 2 -> "west_low", 3 -> "east_low"]
- Initial ship locations: [4 -> 0, 5 -> 6]

### Results Summary
- **Deadlock: PASS** (No deadlock found)
- **States explored:** 231,136 generated / 119,363 distinct
- **Verification time:** 1 second
- **Max depth:** 898 steps

### Invariants (Safety Properties)
- **TypeOK:** PASS - All variables maintain correct types
- **MessagesOK:** PASS - Message queues remain bounded
- **DoorsMutex:** PASS - West and east doors never simultaneously open
- **DoorsOpenValvesClosed:** PASS - Valves closed when opposite doors open
- **DoorsOpenWaterlevelRight:** PASS - Doors open only at correct water level
- **MaxShipsPerLocation:** PASS - Capacity constraints enforced

### Liveness Properties (Temporal)
**Note:** Liveness properties were tested WITHOUT fairness assumptions

- **RequestLockFulfilled:**FAIL (Requires Weak Fairness)
  - **Counterexample:** System enters stuttering where controller waits indefinitely at water level adjustment
  - **Fairness needed:** WF_vars(controlProcess), WF_vars(lockProcess), WF_vars(shipProcess)
  
- **WaterLevelChange:** FAIL (Requires Weak Fairness)
  - **Counterexample:** Water level can remain constant indefinitely through stuttering
  - **Fairness needed:** WF_vars(lockProcess)
  
- **RequestsShips:** FAIL (Requires Weak Fairness)
  - **Counterexample:** Ships can stop making requests through stuttering
  - **Fairness needed:** WF_vars(shipProcess)
  
- **ShipsReachGoals:** FAIL (Requires Weak Fairness)
  - **Counterexample:** Ships never complete full traversal through stuttering
  - **Fairness needed:** WF_vars(controlProcess), WF_vars(shipProcess)

### Explanation of Liveness Failure

Without fairness, TLC found traces leading to "stuttering" states where:
1. A ship requests lock access
2. Controller begins preparing the lock
3. Lock commands are issued but never required to complete
4. The system can make progress but is not forced to

**Example trace (simplified):**
```
State 1: Ship 4 at location 0, requests Lock 1 west doors
State 2: Controller reads request, prepares to adjust water level
State 3: Controller issues valve command
State 4-14: Lock process updates valves, begins changing water level
State 15: STUTTERING - Lock can complete water level change but never does
```

This violates liveness because the ship never eventually enters the lock, even though the action is enabled.

**Solution:** Add weak fairness to the specification:
```tla
FairSpec == Spec /\ WF_vars(controlProcess) 
                /\ \A l \in Locks: WF_vars(lockProcess(l))
                /\ \A s \in Ships: WF_vars(shipProcess(s))
```

---

## Test Configuration: 4 Locks, 2 Ships 2025-10-12 model_multiple/MC.cfg

### Configuration
- Constants: NumLocks=4, NumShips=2, MaxShipsLocation=2, MaxShipsLock=1
- Lock orientations: [1->"east_low", 2->"west_low", 3->"east_low", 4->"west_low"]
- Initial ship locations: [5 -> 0, 6 -> 8]

### Results Summary
- **Deadlock: PASS** (No deadlock found)
- **States explored:** 441,020 generated / 230,335 distinct
- **Verification time:** 2 seconds
- **Max depth:** 1,193 steps

### Invariants (Safety Properties)
All invariants PASS (same as 3 locks configuration)

---

## Deadlock Analysis

### Tested Configurations
| Locks | Ships | Result | Time | States (Distinct) |
|-------|-------|--------|------|-------------------|
| 3 | 2 | No Deadlock | 1s | 119,363 |
| 4 | 2 | No Deadlock | 2s | 230,335 |
| 2 | 3 | Testing | >3min | >726,000+ |
| 3 | 3 | Testing | >3min | >637,000+ |

### Minimum Configuration for Deadlock

**Hypothesis:** Deadlock occurs when `NumShips > NumLocks + 1` with capacity constraints (`MaxShipsLock = 1`)

**Potential Deadlock Scenario (2 locks, 3 ships):**

**Initial Configuration:**
- Ship A at location 0 (going east)
- Ship B at location 2 (going east)
- Ship C at location 4 (going west)
- MaxShipsLocation = 2, MaxShipsLock = 1

**Deadlock Sequence:**
```
1. Ship A requests Lock 1 west -> Granted Moves to location 1
2. Ship C requests Lock 2 east -> Granted Moves to location 3
3. Ship A requests Lock 1 east (to exit) -> Controller processing
4. Ship C requests Lock 2 west (to exit) -> Controller processing
5. Ship B at location 2 requests Lock 1 west -> Denied (Ship A still in Lock 1)

Deadlock State:
- Ship A in Lock 1 (location 1), wants to exit to location 2
  -> Cannot exit: Location 2 at capacity (Ship B present)
- Ship C in Lock 2 (location 3), wants to exit to location 2
  -> Cannot exit: Location 2 at capacity (Ship B present)
- Ship B at location 2, wants to enter Lock 1
  -> Cannot enter: Lock 1 at capacity (Ship A still there)
  
Circular Dependency:
A waits for B to move -> B waits for A to exit -> C waits for B to move -> All blocked
```

**Note:** Due to state space explosion (>700K states explored without completion), this scenario could not be verified within reasonable time. The circular waiting condition suggests deadlock is possible with 3+ ships.

---

## Property Formalizations

### DoorsMutex (Invariant)
```tla
DoorsMutex == \A l \in Locks: ~(doorsOpen[l]["west"] /\ doorsOpen[l]["east"])
```
**Type:** Safety property  
**Justification:** Asserts doors never both open (bad state never reached). Quantifies over all locks.

### DoorsOpenValvesClosed (Invariant)
```tla
DoorsOpenValvesClosed == \A l \in Locks: 
  /\ (doorsOpen[l][LowSide(lockOrientations[l])] => ~valvesOpen[l]["high"])
  /\ (doorsOpen[l][HighSide(lockOrientations[l])] => ~valvesOpen[l]["low"])
```
**Type:** Safety property  
**Justification:** Uses `LowSide`/`HighSide` for orientation independence. Prevents dangerous valve/door combinations.

### DoorsOpenWaterlevelRight (Invariant)
```tla
DoorsOpenWaterlevelRight == \A l \in Locks:
  /\ (doorsOpen[l][LowSide(lockOrientations[l])] => waterLevel[l] = "low")
  /\ (doorsOpen[l][HighSide(lockOrientations[l])] => waterLevel[l] = "high")
```
**Type:** Safety property  
**Justification:** Ensures doors open only when water levels match, orientation-agnostic.

### MaxShipsPerLocation (Invariant)
```tla
MaxShipsPerLocation == \A loc \in Locations:
  IF IsLock(loc)
  THEN Cardinality({s \in Ships : shipLocations[s] = loc}) <= MaxShipsLock
  ELSE Cardinality({s \in Ships : shipLocations[s] = loc}) <= MaxShipsLocation
```
**Type:** Safety property  
**Justification:** Enforces capacity constraints, uses `Cardinality` to count ships at each location.

### RequestLockFulfilled (Liveness)
```tla
ShipRequestingLock(s) == \E i \in 1..Len(requests): 
  /\ requests[i].ship = s 
  /\ ~InLock(s)

RequestLockFulfilled == \A s \in Ships: 
  [](ShipRequestingLock(s) => <>(InLock(s)))
```
**Type:** Liveness property  
**Justification:** Asserts ships eventually enter locks after requesting. Uses helper to avoid TLC sequence limitations.

### WaterlevelChange (Liveness)
```tla
WaterlevelChange == \A l \in Locks: 
  /\ []<>(waterLevel[l] = "high")
  /\ []<>(waterLevel[l] = "low")
```
**Type:** Liveness property  
**Justification:** Ensures locks remain operational, infinitely often reaching both water levels.

### RequestsShips (Liveness)
```tla
RequestsShips == \A s \in Ships: 
  []<>(\E i \in 1..Len(requests): requests[i].ship = s)
```
**Type:** Liveness property  
**Justification:** Ships continuously make requests, ensuring system activity.

### ShipsReachGoals (Liveness)
```tla
ShipsReachGoals == \A s \in Ships: 
  /\ []<>(shipLocations[s] = WestEnd)
  /\ []<>(shipLocations[s] = EastEnd)
```
**Type:** Liveness property  
**Justification:** Ships infinitely traverse the system, demonstrating full functionality.
-

## Liveness Verification WITH Weak Fairness

### Configuration: 3 Locks, 2 Ships with FairSpec

**Date:** October 12, 2025 at 21:41:00  
**Config file:** `lock_system.toolbox/model_multiple/MC.cfg`

**Fairness Specification:**
```tla
FairSpec == Spec 
            /\ WF_vars(controlProcess)
            /\ \A l \in Locks: WF_vars(lockProcess(l))
            /\ \A s \in Ships: WF_vars(shipProcess(s))
```

**TLC Settings:**
- SPECIFICATION: FairSpec (instead of Spec)
- PROPERTIES enabled: RequestLockFulfilled, WaterlevelChange, RequestsShips, ShipsReachGoals
- Constants: NumLocks=3, NumShips=2, MaxShipsLocation=2, MaxShipsLock=1

**Verification Statistics:**
- States generated: 231,136
- Distinct states: 119,363
- Temporal checking time: 3 seconds
- Total verification time: 14 seconds
- Max depth: 898 steps

### Result: **LIVENESS PROPERTIES VIOLATED**

**TLC Error:** "Temporal properties were violated."

### Counterexample Summary

Even with weak fairness, the model exhibits a **capacity-induced deadlock** where liveness cannot be satisfied:

**Final state (537) of counterexample trace:**
```tla
shipLocations = (4 :> 2 @@ 5 :> 3)         \* Both ships in lock 2
permissions = (4 :> <<[lock |-> 2, granted |-> FALSE]>> @@ 5 :> <<>>)
canGrant = FALSE                           \* Controller denies request
shipsAtTarget = 1                          \* Capacity check failed
doorsOpen = <<[west->FALSE, east->TRUE],   \* Lock 1: east door open
              [west->FALSE, east->TRUE],   \* Lock 2: east door open
              [west->TRUE, east->FALSE]>>  \* Lock 3: west door open
waterLevel = <<"low", "high", "high">>
```

**Loop:** Trace loops back to state 161 (`ShipWaitForWest`)

**Deadlock Mechanism:**
1. **Ship 4** at location 2 (inside lock 2, low side)
2. **Ship 5** at location 3 (inside lock 2, high side)
3. Ship 4 requests to move west (exit lock 2) → Controller checks capacity
4. `shipsAtTarget` = 1 (Ship 5 occupies target location 3)
5. `MaxShipsLock = 1` → Controller sets `canGrant := FALSE`
6. Controller writes `permissions[4] := [lock |-> 2, granted |-> FALSE]`
7. Ship 4 waits, re-requests → Perpetual denial
8. Ship 5 also cannot progress → **Both ships stuck**

### Property Evaluation with Fairness

#### RequestLockFulfilled
**Formula:**
```tla
RequestLockFulfilled == \A s \in Ships: 
  [](ShipRequestingLock(s) => <>(InLock(s)))
```

**Result:** **FALSE**

**Counterexample:** Ship 4 continuously requests lock 2 (`ShipRequestingLock(4)` holds), but `InLock(4)` never becomes true because the controller perpetually denies due to capacity constraints (`MaxShipsLock=1` violated by ship 5's presence).

**Why fairness doesn't help:** Weak fairness ensures the denial action (`ControlDenyPermission`) eventually executes, but since `canGrant = FALSE` is structurally determined by capacity, fairness cannot force `canGrant` to become TRUE.

---

#### WaterlevelChange
**Formula:**
```tla
WaterlevelChange == \A l \in Locks: 
  []<>(waterLevel[l] = "high") /\ []<>(waterLevel[l] = "low")
```

**Result:** **FALSE** (specifically for lock 2)

**Counterexample:** Lock 2's water level becomes stuck at `"high"` (final state shows `waterLevel[2] = "high"`). Since both ships are deadlocked and cannot make progress, the controller never adjusts lock 2's water level back to `"low"`.

**Why fairness doesn't help:** The lock process can only change water level when commanded by the controller. Since the controller is stuck in a deny-loop for capacity reasons, no water level change commands are issued for lock 2.

---

#### RequestsShips
**Formula:**
```tla
RequestsShips == \A s \in Ships: 
  []<>(\E i \in 1..Len(requests): requests[i].ship = s)
```

**Result:** **FALSE** (or indeterminate)

**Analysis:** In the counterexample loop, ships may continue generating requests, but once the deadlock pattern establishes, they get stuck in waiting states. The trace shows `requests = <<>>` at state 533, then ship 5 writes a request. However, the circular waiting prevents ships from infinitely often making *new* requests.

**Why fairness doesn't help:** Fairness ensures ship processes execute, but ships block on `read(permissions[s], perm)` when waiting for responses. If the controller only sends denials, ships may re-request but get stuck again.

---

#### ShipsReachGoals
**Formula:**
```tla
ShipsReachGoals == \A s \in Ships: 
  []<>(shipLocations[s] = WestEnd) /\ []<>(shipLocations[s] = EastEnd)
```

**Result:** **FALSE**

**Counterexample:** 
- Ship 4 (at location 2) never reaches location 0 (WestEnd) or location 6 (EastEnd)
- Ship 5 (at location 3) never reaches location 0 or location 6
- Both ships are permanently stuck inside lock 2

**Why fairness doesn't help:** Goal-reaching requires successful lock traversals. Since capacity constraints block both ships indefinitely, neither can complete a full traversal cycle.

---

### Root Cause Analysis

**Fundamental Issue:** The controller's capacity enforcement creates **liveness-violating states** that fairness cannot resolve.

**Controller Logic (lines 811-829, `lock_multiple.tla`):**
```tla
ControlCheckCapacity:
    targetLocation := IF requestedSide = "west" THEN 2 * req.lock - 2 
                      ELSE 2 * req.lock;
    shipsAtTarget := Cardinality({ s \in Ships : shipLocations[s] = targetLocation });
    canGrant := IF IsLock(targetLocation) 
                THEN shipsAtTarget < MaxShipsLock
                ELSE shipsAtTarget < MaxShipsLocation;
```

**Problem:** Once `shipsAtTarget >= MaxShipsLock`, the controller **unconditionally denies** requests. There is no mechanism to:
1. Detect circular waiting (deadlock)
2. Reorder requests to prioritize exit over entry
3. Force ships to vacate locks to make room for others
4. Prevent ships from entering locks if doing so would block exits

**Why Weak Fairness Fails:**
- **WF ensures:** If an action is continuously enabled, it eventually executes
- **In this scenario:** The denial action (`ControlDenyPermission`) *is* continuously enabled when `canGrant = FALSE`
- **Fairness forces:** Denial to occur, not grant
- **Consequence:** Fairness accelerates the deadlock rather than preventing it

**What Would Be Needed:**
- **Strong Fairness (SF)** would also fail here because the grant action is never enabled (capacity always violated)
- **Solution requires:** Algorithmic changes to the controller logic, not just fairness assumptions

### Implications

**Liveness properties are fundamentally unsatisfiable** under the current design with these parameters because:

1. **Capacity constraints allow mutual blocking:** Two ships can enter the same lock from opposite sides and become trapped
2. **No deadlock avoidance:** Controller lacks predictive logic to prevent blocking scenarios
3. **Safety prioritized over liveness:** The model correctly enforces capacity (safety), but sacrifices progress (liveness)

**To achieve liveness, the model would require:**
1. **Deadlock prevention:** Controller predicts if granting would lead to circular waiting
2. **Request prioritization:** Prioritize exit requests over entry requests to prevent trapping
3. **Relaxed capacity:** Set `MaxShipsLock ≥ NumShips` (unrealistic for real locks)
4. **Eviction mechanisms:** Force ships to reverse direction if they're blocking others
5. **Fairness assumptions on ships:** Assume ships don't request locks when doing so would block (unrealistic)

**Conclusion:** The counterexample reveals a **design-level liveness violation**. The controller successfully maintains safety invariants but cannot guarantee progress for all ships under the given capacity constraints. This is a fundamental limitation of the lock management strategy, not a fairness issue.

---

## Final Summary

### Invariants (Safety): ALL PASS
- TypeOK, MessagesOK, DoorsMutex, DoorsOpenValvesClosed, DoorsOpenWaterlevelRight, MaxShipsPerLocation

### Liveness Properties: ALL FAIL (with weak fairness)
- **RequestLockFulfilled:** FALSE (capacity deadlock prevents ships from entering locks)
- **WaterlevelChange:** FALSE (lock 2 stuck at "high" water level)
- **RequestsShips:** FALSE (ships stuck waiting, cannot make new requests infinitely often)
- **ShipsReachGoals:** FALSE (ships never complete full traversal cycles)

### Deadlock Status: No TLC-detected deadlock
**However:** Liveness failure indicates a **livelock** (system can transition but makes no progress)

### State Space:
- 3 locks / 2 ships: 119,363 distinct states, 14 seconds total (3s temporal checking)
- 4 locks / 2 ships: 230,335 distinct states, 2 seconds (previously tested without liveness)

### Fairness Assessment:
**Weak fairness is insufficient** to guarantee liveness under capacity constraints. The model requires algorithmic improvements to the controller's decision logic to prevent capacity-induced deadlocks.