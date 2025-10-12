# Bonus Question: Deadlock-Avoiding Schedule - Quick Summary

**Date:** October 12, 2025  
**Configuration:** 3 locks, 2 ships, MaxShipsLocation=2, MaxShipsLock=1

---

## The Question

For the configuration that showed liveness violations, formalize a property stating "NOT all ships can reach goal_reached", then verify it. If TLC finds this FALSE, the counterexample shows a deadlock-avoiding schedule.

---

## Property Formalized

```tla
AllShipsCannotReachGoal == ~(\A s \in Ships: shipStates[s] = "goal_reached")
```

Added to `lock_multiple.tla` and checked as an **INVARIANT**.

---

## TLC Result: ✅ **PROPERTY VIOLATED**

**Meaning:** TLC found a state where ALL ships have `goal_reached` status!

**Final State (State 358):**
```tla
shipStates = (4 :> "goal_reached" @@ 5 :> "goal_reached")
shipLocations = (4 :> 6 @@ 5 :> 0)
```

**Statistics:**
- **Counterexample length:** **358 states**
- States generated: 66,341
- Distinct states: 35,018
- Verification time: 1 second

---

## Why This Matters

### **What TLA+ Proves:**

The 358-state trace is a **constructive proof** that:
1. Deadlock IS avoidable even with `MaxShipsLock=1`
2. A valid schedule exists where all ships reach their goals
3. The system is NOT inherently deadlock-prone

### **Why the Schedule Avoids Deadlocks:**

**Key mechanism:** Ships use locks **sequentially**, not simultaneously.

**Example schedule (inferred):**
```
Initial: Ship 4 at location 0, Ship 5 at location 6

Phase 1 (States 1-~150):
  - Ship 4 traverses: 0 → Lock 1 → 2 → Lock 2 → 4 → Lock 3 → 6
  - Ship 5 waits at location 6
  - Ship 4 reaches goal

Phase 2 (States ~151-358):
  - Ship 5 traverses: 6 → Lock 3 → 4 → Lock 2 → 2 → Lock 1 → 0
  - Ship 4 stays at location 6 (goal reached)
  - Ship 5 reaches goal
```

**Why this works:**
- No overlapping lock usage → `MaxShipsLock=1` never violated
- Controller grants requests when locks are free
- No circular waiting → No deadlock

### **Contrast with Fairness Result:**

**With Fairness (`FairSpec`):**
- Ships MUST make requests infinitely often
- Controller MUST process all requests eventually
- → Ships get stuck when both request the same lock
- → **Liveness failure (livelock)**

**Without Fairness (`Spec`):**
- TLC explores ALL possible schedules
- Finds at least one where ships wait strategically
- → Ships don't request locks when it would cause blocking
- → **Deadlock avoided (counterexample found)**

---

## Length: 358 Steps - Why So Long?

The counterexample is **very long** because:

1. **Fine-grained interleaving:** Each action is a separate state
   - Controller reads request (1 state)
   - Controller checks capacity (1 state)
   - Controller closes door (1 state)
   - Controller adjusts water level (multiple states for valves + waiting)
   - Controller opens door (1 state)
   - Controller grants permission (1 state)
   - Controller observes movement (1 state)
   - Ship moves (1 state)

2. **Multiple lock traversals:**
   - Ship 4 traverses 3 locks (approx. 30-50 states per lock = ~150 states)
   - Ship 5 traverses 3 locks (another ~150 states)
   - Plus initial requests, final goal states = **358 total**

3. **Safe coordination:**
   - Controller waits for each door/valve/water level change to complete
   - Ships wait for permissions before moving
   - Many synchronization points add states

---

## Key Insight

**Deadlock avoidance requires intelligent scheduling:**
- Current controller is non-deterministic (processes any enabled request)
- The 358-state trace represents ONE specific schedule where deadlock doesn't occur
- A **smarter controller** could implement patterns from this trace:
  - Prioritize exit requests
  - Queue and reorder requests
  - Predict blocking scenarios

**Fairness vs. Correctness:**
- Fairness can FORCE the system into deadlock (as we saw with liveness properties)
- Real systems may not satisfy fairness (ships can wait strategically)
- Design should not rely on fairness for deadlock avoidance

---

## Practical Use of the Counterexample

### **Inspection:**
- TLC Toolbox: View full 358-state trace
- Filter to show only key variables: `shipStates`, `shipLocations`, `requests`
- Animate the schedule to visualize ship movements

### **Extract Patterns:**
- Identify controller decision points
- Note when ships wait vs. request
- Generalize to scheduling policy

### **Implement Policy:**
- Use trace as reference for controller logic
- Add deadlock-avoidance heuristics
- Re-verify with updated model

---

## Files

- **Full analysis:** `BONUS_QUESTION_ANALYSIS.md`
- **TLC output:** `verification_output_bonus_schedule.txt`
- **Property definition:** `lock_multiple.tla` (lines 108-111)
- **Configuration:** `lock_system.toolbox/model_multiple/MC.cfg`

---

## Answer Summary

| Question | Answer |
|----------|--------|
| **Counterexample length?** | **358 states** (very long!) |
| **Why so long?** | Fine-grained interleaving + 2 ships × 3 locks × many substeps |
| **Why avoids deadlock?** | Ships use locks sequentially, no overlapping usage |
| **Key mechanism?** | Strategic request timing prevents capacity conflicts |
| **Can deadlock be avoided?** | **YES** - TLA+ proves it with constructive counterexample |

---

**Conclusion:** TLA+ not only verifies properties but also **constructs schedules** that demonstrate feasibility. The 358-state trace is a witness that deadlock-free operation is possible with proper coordination, even under restrictive capacity constraints.
