# Liveness Property Verification Summary - Multiple Lock System

**Date:** October 12, 2025  
**Configuration:** 3 locks, 2 ships, MaxShipsLocation=2, MaxShipsLock=1  
**Specification:** FairSpec (Spec with weak fairness on all processes)

---

## Quick Results

| Property | Result | Reason |
|----------|---------|---------|
| **RequestLockFulfilled** | ❌ **FALSE** | Capacity deadlock - ships denied access perpetually |
| **WaterlevelChange** | ❌ **FALSE** | Lock 2 stuck at "high" due to ship deadlock |
| **RequestsShips** | ❌ **FALSE** | Ships stuck waiting, cannot make new requests |
| **ShipsReachGoals** | ❌ **FALSE** | Ships never complete full traversal cycles |

**All 4 liveness properties FAIL even with weak fairness.**

---

## Verification Statistics

- **States generated:** 231,136
- **Distinct states:** 119,363
- **Verification time:** 14 seconds (3s temporal checking)
- **TLC Error:** "Temporal properties were violated"
- **Counterexample:** 537-state trace looping back to state 161

---

## Root Cause: Capacity-Induced Deadlock

### The Deadlock Scenario

**Final state (537):**
- Ship 4 at location 2 (inside lock 2, low side)
- Ship 5 at location 3 (inside lock 2, high side)
- Both ships stuck in same lock chamber
- `MaxShipsLock=1` violated → controller perpetually denies requests
- Neither ship can progress → **livelock**

### Why Fairness Doesn't Help

**Weak fairness ensures:** Continuously enabled actions eventually execute

**Problem:** When `canGrant = FALSE` due to capacity, the *denial* action is enabled, not the *grant* action. Fairness forces the controller to deny, not grant.

**Fairness cannot:** Change the structural capacity constraint that makes `canGrant = FALSE`

---

## Detailed Property Analysis

### 1. RequestLockFulfilled
```tla
RequestLockFulfilled == \A s \in Ships: 
  [](ShipRequestingLock(s) => <>(InLock(s)))
```
**Fails:** Ship 4 requests lock 2 infinitely often, but `InLock(4)` never becomes true because controller denies due to ship 5's presence.

### 2. WaterlevelChange
```tla
WaterlevelChange == \A l \in Locks: 
  []<>(waterLevel[l] = "high") /\ []<>(waterLevel[l] = "low")
```
**Fails:** Lock 2 water level stuck at `"high"` because no ships can progress → no water level adjustments needed → no cycling.

### 3. RequestsShips
```tla
RequestsShips == \A s \in Ships: 
  []<>(\E i \in 1..Len(requests): requests[i].ship = s)
```
**Fails:** Ships get stuck in waiting states after receiving denials → cannot make new requests infinitely often.

### 4. ShipsReachGoals
```tla
ShipsReachGoals == \A s \in Ships: 
  []<>(shipLocations[s] = WestEnd) /\ []<>(shipLocations[s] = EastEnd)
```
**Fails:** Ship 4 never reaches location 0 or 6; ship 5 also blocked → no ship completes traversal.

---

## Controller Logic Issue

**Current implementation (lines 811-829):**
```tla
ControlCheckCapacity:
    shipsAtTarget := Cardinality({ s \in Ships : shipLocations[s] = targetLocation });
    canGrant := IF IsLock(targetLocation) 
                THEN shipsAtTarget < MaxShipsLock
                ELSE shipsAtTarget < MaxShipsLocation;
```

**Problem:** No mechanism to:
1. Detect circular waiting
2. Prioritize exit requests over entry requests
3. Prevent ships from entering locks if it would cause deadlock
4. Force ships to vacate when blocking others

**Result:** Safety (capacity constraints) is preserved, but liveness (progress) is violated.

---

## Implications

### What This Means

**The model is fundamentally liveness-unsafe** with `MaxShipsLock=1` and `NumShips=2`:
- Two ships can enter the same lock from opposite sides
- Once both are inside, neither can exit (capacity violated)
- Controller correctly enforces safety but creates livelock
- **This is a design limitation, not a fairness issue**

### What Would Fix It

**Option 1: Algorithmic improvements**
- Add deadlock avoidance (predictive blocking)
- Prioritize exit over entry requests
- Implement request reordering

**Option 2: Relax constraints**
- Set `MaxShipsLock ≥ NumShips` (unrealistic for real locks)
- Increase capacity beyond realistic values

**Option 3: Add eviction mechanisms**
- Force ships to reverse direction if blocking
- Timeout-based forced movements

**Option 4: Restrict ship behavior**
- Assume ships don't request locks when it would block (unrealistic)

---

## Fairness Specification Used

```tla
FairSpec == Spec 
            /\ WF_vars(controlProcess)
            /\ \A l \in Locks: WF_vars(lockProcess(l))
            /\ \A s \in Ships: WF_vars(shipProcess(s))
```

**Applied to:**
- Controller process (ID 0)
- All lock processes (IDs 1-3)
- All ship processes (IDs 4-5)

**TLC Configuration:**
- MC.cfg: SPECIFICATION FairSpec
- PROPERTY: RequestLockFulfilled, WaterlevelChange, RequestsShips, ShipsReachGoals
- INVARIANT: (all 6 safety invariants - all PASS)

---

## Comparison: With vs. Without Fairness

### Without Fairness (previously tested)
- **Result:** Liveness properties FAIL
- **Reason:** Stuttering - processes can execute but aren't required to
- **Counterexample:** System enters states where progress is possible but never happens

### With Weak Fairness (current test)
- **Result:** Liveness properties FAIL
- **Reason:** Capacity deadlock - progress is structurally impossible
- **Counterexample:** System enters livelock where transitions occur but no meaningful progress

**Conclusion:** Fairness eliminates stuttering but reveals a deeper design flaw (capacity-induced livelock).

---

## Final Verdict

✅ **Safety Properties:** All 6 invariants PASS  
❌ **Liveness Properties:** All 4 properties FAIL (with weak fairness)  
✅ **Deadlock (TLC):** No deadlock detected  
⚠️ **Livelock:** Present - system can transition but makes no progress  

**Model Status:** Safety-correct but liveness-incorrect under realistic capacity constraints.

---

## For More Details

See full analysis in: `reports/multiple_model_results.md` (Section: "Liveness Verification WITH Weak Fairness")

**Verification outputs:**
- `verification_output_multiple_3locks_fairness.txt` - Full TLC trace
- `lock_system.toolbox/model_multiple/MC.cfg` - Configuration used
- `lock_multiple.tla` (lines 1119-1127) - FairSpec definition
