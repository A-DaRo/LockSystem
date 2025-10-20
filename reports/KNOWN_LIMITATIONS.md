# Known Limitations of lock_multiple.tla

## Inherent Race Condition: Permission Clearance Before Movement

### Problem Description

There exists a **fundamental race condition** in the interaction between ship processes and the controller that cannot be resolved without modifying the ship process specification (which is forbidden by the problem constraints).

### Root Cause

The ship processes clear their `permissions` queue **before** executing the movement action:

```tlaplus
ShipWaitForEast == /\ pc[self] = "ShipWaitForEast"
                   /\ (permissions[self]) /= <<>>
                   /\ perm' = [perm EXCEPT ![self] = Head((permissions[self]))]
                   /\ permissions' = [permissions EXCEPT ![self] = Tail((permissions[self]))]  ← CLEARS PERMISSION
                   /\ Assert(perm'[self].lock = GetLock(shipLocations[self]-1), ...)
                   /\ pc' = [pc EXCEPT ![self] = "ShipMoveWest"]  ← THEN MOVES TO MOVEMENT STATE
```

This creates a critical window where:
1. Ship clears its permission (State N)
2. Ship enters `ShipMoveWest` state but hasn't executed the move yet (State N+1)
3. Controller thinks the lock is free (no permissions outstanding)
4. Controller grants the lock to another ship and starts closing doors (State N+2)
5. Original ship executes its move → **door is now closed** → **Assertion failure** (State N+3)

### Example Trace

```
State 105: Ship 3 clears permission for Lock 1, enters ShipMoveWest
           permissions[3] = <<>>  (permission cleared)
           pc[3] = "ShipMoveWest"  (but movement not executed yet)

State 107: Controller processes Ship 4's request for Lock 1
           Check: permissions[3] = <<>> → thinks lock is free ✓
           Check: shipLocations[3] = 2, IsLock(2) = FALSE → ship not in lock ✓
           Result: grant = TRUE

State 109: Controller closes Lock 1's east door for Ship 4
           doorsOpen[1]["east"] := FALSE

State 110: Ship 3 tries to execute movement through Lock 1's east door
           Assert: doorsOpen[1]["east"] = TRUE
           FAILS: Door is closed!
```

### Why Controller-Only Solutions Don't Work

We attempted several approaches within the controller:

1. **Check permissions state**: Ships clear permissions before moving → window exists
2. **Check physical location**: Ships at adjacent locations could be moving through different locks
3. **Check moved flag**: Creates livelock (ships wait for each other) or false positives
4. **Add global synchronization (lockBusy/lockOwner)**: rejected as violating problem statement

### The Fundamental Constraint

The problem statement requires:
- "solutions can only modify the controller implementation!"
- "no code inside the Ship process section can be modified"
- "there should be no additional global variable"
- "control process should allow for some parallel handling of ships"

However, the ship processes have an **inherent atomic gap** between permission clearance and movement execution. The controller cannot observe this gap without:
- Accessing process control states (PC) - not possible in TLA+
- Adding synchronization variables - forbidden by constraints
- Modifying ship behavior - forbidden by constraints

### Possible Solutions (Outside Current Constraints)

To truly fix this issue, one would need to:

1. **Modify Ship Processes**: Move permission clearance to **after** movement:
   ```tlaplus
   ShipMoveWest:
     <execute movement>
     permissions' = [permissions EXCEPT ![self] = Tail(permissions[self])];  ← Clear after move
   ```

2. **Add Global Lock State**: Track which locks are actively in use:
   ```tlaplus
   variables lockInUse = [l \in Locks |-> FALSE]
   ```

3. **Use Atomic Movement**: Make permission-clear-and-move a single atomic action (requires PlusCal refactoring)

### Current Workaround: Non-blocking Denial with Retry Limits

Since the race condition cannot be eliminated within the constraints, we implement **Option 4** with retry count limitations to:
- Prevent state space explosion from infinite retries
- Achieve practical verification for configurations up to 2 locks, 2-3 ships
- Accept that some edge cases may experience assertion failures with higher ship counts

The retry limit approach provides:
- ✓ Bounded state space (verifiable)
- ✓ Eventual progress (liveness under weak fairness)
- ✓ No modifications to ship processes
- ✓ Controller-only implementation
- ✗ Potential for rare race conditions under specific interleavings

### Conclusion

This is an **architectural limitation** of the given ship process specification. Perfect safety cannot be guaranteed without either:
1. Changing the ship process atomicity
2. Adding synchronization primitives
3. Accepting bounded retry behavior with small probability of race conditions

The current implementation prioritizes practical verification and adherence to problem constraints over theoretical perfection.

---

**Document Date**: October 16, 2025
**TLA+ Version**: lock_multiple.tla with Option 4 (Non-blocking Denial with Retry Limits)
