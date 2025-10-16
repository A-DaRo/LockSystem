# Single Lock Model - Property Verification Report (Section 4.2)

**Date:** October 12, 2025  
**Model Configuration:** `lock_system.toolbox/model_single/MC.cfg`  
**TLA+ Version:** TLC2 Version 2.19 of 08 August 2024  
**Model Checker:** TLC2 with breadth-first search

---

## Executive Summary

**All properties verified successfully**  
**Model is deadlock-free**  
**Works for both lock orientations** (west_low and east_low)  
**Verification time:** < 1 second  
**State space:** 154 distinct states (west_low), 164 distinct states (east_low)

---

## Model Configuration

### Constants
- **NumLocks:** 1
- **NumShips:** 1  
- **MaxShipsLocation:** 2
- **MaxShipsLock:** 1
- **Lock Orientation:** `"west_low"` (configurable)

### Specification
- **Base Specification:** `Spec == Init /\ [][Next]_vars`
- **Fairness Specification:** `FairSpec` with weak fairness on all processes

## Control Process Implementation

The `controlProcess` was implemented to safely manage lock operations for ship movements. The controller follows this workflow:

1. **Read Request:** Receive ship request from `requests` queue (ship ID, lock ID, requested side)
2. **Close Doors:** Ensure both doors are closed before water level adjustment
3. **Determine Target Level:** Calculate target water level based on requested side and lock orientation using `LowSide()` and `HighSide()` helper functions
4. **Adjust Water Level:** 
   - If level needs lowering: open low valve → wait for water level to reach "low" → close low valve
   - If level needs raising: open high valve → wait for water level to reach "high" → close high valve
5. **Open Requested Door:** Open the door on the requested side
6. **Grant Permission:** Send permission message to ship via `permissions` queue

The implementation ensures safety by:
- Never opening doors while water levels are mismatched
- Never having both doors open simultaneously
- Always closing valves after water level adjustment
- Handling both lock orientations (west_low and east_low) correctly using orientation-agnostic formulas

## Properties Verified

### Safety Properties (Invariants)

#### 1. **TypeOK** PASS
All variables maintain correct types throughout execution.

#### 2. **MessagesOK** PASS
Message queues do not overflow (max 1 message at a time for single ship/lock model).

#### 3. **DoorsMutex** PASS
```tla
DoorsMutex == ~(doorsOpen["west"] /\ doorsOpen["east"])
```
The eastern and western pairs of doors are never simultaneously open.
- **Type:** Safety property (invariant)
- **Justification:** This is a safety property because it specifies "something bad never happens" - specifically, both doors never open at the same time, which would cause water to flow uncontrolled through the lock.

#### 4. **DoorsOpenValvesClosed** PASS
```tla
DoorsOpenValvesClosed == 
  /\ (doorsOpen[LowSide(lockOrientation)] => ~valvesOpen["high"])
  /\ (doorsOpen[HighSide(lockOrientation)] => ~valvesOpen["low"])
```
When the lower pair of doors is open, the higher valve is closed, and vice versa. Uses `LowSide()` and `HighSide()` helper functions to work with both lock orientations.
- **Type:** Safety property (invariant)
- **Justification:** This is a safety property because it prevents an unsafe condition where water could flow uncontrolled if doors and opposite valves are open simultaneously.

#### 5. **DoorsOpenWaterlevelRight** PASS
```tla
DoorsOpenWaterlevelRight == 
  /\ (doorsOpen[LowSide(lockOrientation)] => waterLevel = "low")
  /\ (doorsOpen[HighSide(lockOrientation)] => waterLevel = "high")
```
The lower pair of doors is only open when water level is low; the higher pair only when water level is high. Orientation-agnostic using helper functions.
- **Type:** Safety property (invariant)
- **Justification:** This is a safety property as it ensures doors are never opened when there is a water level mismatch, which would be dangerous for ships and the lock structure.

### Liveness Properties (Temporal Properties)

All liveness properties require **weak fairness (WF)** to hold. Without fairness assumptions, processes could be indefinitely delayed, preventing progress.

#### 6. **RequestLockFulfilled** PASS (WF)
```tla
RequestLockFulfilled == \A s \in Ships : (shipLocation = 0 ~> InLock)
```
Always, if the ship requests to enter the lock (from position 0), it will eventually be inside the lock.
- **Type:** Liveness property
- **Fairness Required:** Weak Fairness (WF)
- **Justification:** This is a liveness property because it specifies "something good eventually happens" - a ship that requests lock entry will eventually get inside. WF is needed to ensure the control process eventually processes the request, the lock process eventually executes commands, and the ship process eventually moves.

#### 7. **WaterlevelChange** PASS (WF)
```tla
WaterlevelChange == 
  /\ []<>(waterLevel = "high")
  /\ []<>(waterLevel = "low")
```
The water level is infinitely many times high and infinitely many times low.
- **Type:** Liveness property  
- **Fairness Required:** Weak Fairness (WF)
- **Justification:** This liveness property ensures the system doesn't get stuck at one water level. Without WF on the lock and control processes, the water level could remain constant forever. WF ensures valves are eventually operated to change the water level.

#### 8. **RequestsShips** PASS (WF)
```tla
RequestsShips == []<>(Len(requests) > 0)
```
Infinitely many times the ship makes requests.
- **Type:** Liveness property
- **Fairness Required:** Weak Fairness (WF)
- **Justification:** This liveness property ensures the ship continues to operate infinitely. Without WF on the ship process, it could stop making requests. WF ensures the ship process is always eventually scheduled.

#### 9. **ShipsReachGoals** PASS (WF)
```tla
ShipsReachGoals == 
  /\ []<>(shipLocation = EastEnd)
  /\ []<>(shipLocation = WestEnd)
```
Infinitely many times the ship reaches both the east end and west end.
- **Type:** Liveness property
- **Fairness Required:** Weak Fairness (WF)
- **Justification:** This liveness property ensures the ship makes progress through the system repeatedly. Without WF on all processes (ship, control, lock), the ship could get stuck and never reach its destination. WF ensures all processes make progress, allowing the ship to traverse the lock repeatedly.

### Deadlock
**No deadlocks detected**

The model is completely deadlock-free. All processes can always make progress under the fairness assumptions.

## Summary Table - Verification Results

| Property | Type | Result | Fairness | Configuration Section |
|----------|------|--------|----------|----------------------|
| **Deadlock Check** | System | PASS | - | CHECK_DEADLOCK |
| **TypeOK** | Safety (Invariant) | PASS | None | INVARIANT |
| **MessagesOK** | Safety (Invariant) | PASS | None | INVARIANT |
| **DoorsMutex** | Safety (Invariant) | PASS | None | INVARIANT |
| **DoorsOpenValvesClosed** | Safety (Invariant) | PASS | None | INVARIANT |
| **DoorsOpenWaterlevelRight** | Safety (Invariant) | PASS | None | INVARIANT |
| **RequestLockFulfilled** | Liveness (Temporal) | PASS | WF | PROPERTY |
| **WaterlevelChange** | Liveness (Temporal) | PASS | WF | PROPERTY |
| **RequestsShips** | Liveness (Temporal) | PASS | WF | PROPERTY |
| **ShipsReachGoals** | Liveness (Temporal) | PASS | WF | PROPERTY |

**Legend:**
- WF = Weak Fairness required
- None = No fairness assumptions needed (always holds)

## Fairness Requirements

### Why Weak Fairness is Needed (Detailed Justification)

**Without fairness assumptions**, TLA+ allows behaviors where processes are perpetually ignored even when they can make progress. This would cause liveness properties to fail. Here's why each process requires weak fairness:

#### 1. Control Process - WF_vars(controlProcess)
**Why needed:** Without WF on the control process:
- The controller could indefinitely ignore pending requests in the `requests` queue
- Ships would wait forever for permissions, violating `RequestLockFulfilled`
- Water levels would never change, violating `WaterlevelChange`
- The system would "stutter" without making progress

**Why WF is sufficient:** Once a request is in the queue, the `ControlReadRequest` action is continuously enabled (the queue is non-empty). WF guarantees this continuously enabled action will eventually execute.

**Why SF is not needed:** We don't have actions that are only intermittently enabled. The control loop continuously processes requests when they exist.

#### 2. Lock Process - WF_vars(lockProcess(l))
**Why needed:** Without WF on lock processes:
- Lock commands from the controller could be ignored indefinitely
- Doors and valves would never change state
- Water levels couldn't adjust, blocking all ship movements
- The entire system would deadlock waiting for lock responses

**Why WF is sufficient:** Once `lockCommand.command ≠ "finished"`, the lock's `LockWaitForCommand` action is continuously enabled. The lock will eventually execute the command and respond.

**Why SF is not needed:** Lock commands remain enabled until executed - there's no intermittent enabling pattern.

#### 3. Ship Process - WF_vars(shipProcess(s))
**Why needed:** Without WF on ship processes:
- Ships could wait forever even after receiving permission
- Ships might never send requests, violating `RequestsShips`
- Ships might never reach their destinations, violating `ShipsReachGoals`
- The system would appear "stuck" despite being safe

**Why WF is sufficient:** Ship actions (sending requests, moving after permission) are continuously enabled when their conditions are met. WF ensures they eventually execute.

**Why SF is not needed:** Ship actions don't become disabled and re-enabled repeatedly - they stay enabled until taken.

### Weak Fairness vs Strong Fairness

**Weak Fairness (WF):** An action that is *continuously enabled* will *eventually* be taken.

**Strong Fairness (SF):** An action that is *infinitely often enabled* will *eventually* be taken (even if sometimes disabled).

**Our system uses WF because:**
- All critical actions remain enabled once their preconditions are met
- No action becomes temporarily disabled and then re-enabled repeatedly
- WF provides the necessary progress guarantees without overconstraining the system

**Default behavior (no fairness) is insufficient because:**
- TLA+ semantics allow infinite stuttering (taking no actions)
- Processes could be scheduled unfairly, causing starvation
- Liveness properties inherently require some fairness assumption
- Without fairness, the model checker finds "lazy" behaviors that never make progress

### Fairness Specification (in lock_single.tla)
```tla
\* Base specification without fairness
Spec == Init /\ [][Next]_vars

\* Fairness specification - ensures liveness properties hold
FairSpec == Spec 
            /\ WF_vars(controlProcess)
            /\ \A l \in Locks : WF_vars(lockProcess(l))
            /\ \A s \in Ships : WF_vars(shipProcess(s))
```

**Note:** The model configuration uses `FairSpec` as the SPECIFICATION to verify, ensuring all liveness properties are checked under appropriate fairness assumptions.

## Verification Statistics

### Configuration: west_low orientation
- **Total States Generated:** 182
- **Distinct States Found:** 154
- **States on Queue:** 0 (complete state space exploration)
- **Total Distinct States (with temporal checking):** 308
- **State Space Depth:** 128
- **Average Outdegree:** 1 (min: 0, max: 2, 95th percentile: 2)
- **Verification Time:** 1 second
- **Workers Used:** 20 (auto-detected from CPU cores)
- **Memory:** 3561MB heap, 64MB offheap
- **Fingerprint Collision Probability:** 2.3E-16 (negligible)

### Configuration: east_low orientation (verified for completeness)
- **Total States Generated:** 192
- **Distinct States Found:** 164
- **State Space Depth:** 138
- **Verification Time:** < 1 second
- **Result:** All properties PASS

### Performance Characteristics
- **Search Algorithm:** Breadth-first search (BFS)
- **Fingerprint Method:** MSBDiskFPSet with fp=59
- **State Queue:** DiskStateQueue
- **Platform:** Windows 11 10.0 amd64, Eclipse Adoptium JDK 21.0.7
- **Garbage Collector:** Parallel GC (-XX:+UseParallelGC)

## Orientation-Agnostic Design (Requirement: Both Orientations)

As required in Section 4.2, the model must work for **both lock orientations**. This has been verified through:

### Lock Orientations Tested

1. **`"west_low"`** (default configuration)
   - West side has low water level, connected to low-altitude water body
   - East side has high water level, connected to high-altitude water body
   - All 10 properties PASS
   - 154 distinct states explored

2. **`"east_low"`** (alternate configuration tested)
   - East side has low water level, connected to low-altitude water body
   - West side has high water level, connected to high-altitude water body
   - All 10 properties PASS
   - 164 distinct states explored

### Implementation Approach: Helper Functions

The orientation-agnostic design is achieved using helper functions defined in `lock_data.tla`:

```tla
\* Get the low/high side from a lock with a given orientation
LowSide(lock_orientation) == 
  IF lock_orientation = "west_low" THEN "west" ELSE "east"

HighSide(lock_orientation) == 
  IF lock_orientation = "west_low" THEN "east" ELSE "west"
```

### Properties Using Orientation-Agnostic Formulas

**Example 1: DoorsOpenValvesClosed**
```tla
\* Instead of hardcoding: doorsOpen["west"] => ~valvesOpen["high"]
\* We use:
DoorsOpenValvesClosed == 
  /\ (doorsOpen[LowSide(lockOrientation)] => ~valvesOpen["high"])
  /\ (doorsOpen[HighSide(lockOrientation)] => ~valvesOpen["low"])
```
This works for both orientations:
- If `west_low`: checks `doorsOpen["west"] => ~valvesOpen["high"]`
- If `east_low`: checks `doorsOpen["east"] => ~valvesOpen["high"]`

**Example 2: DoorsOpenWaterlevelRight**
```tla
DoorsOpenWaterlevelRight == 
  /\ (doorsOpen[LowSide(lockOrientation)] => waterLevel = "low")
  /\ (doorsOpen[HighSide(lockOrientation)] => waterLevel = "high")
```
This ensures the correct door is checked based on actual water levels, not fixed geographic sides.

### Control Process Orientation Handling

The control process also uses these helper functions:
```tla
ControlSetTargetLevel:
  if requestedSide = LowSide(lockOrientation) then
    targetWaterLevel := "low";
  else
    targetWaterLevel := "high";
  end if;
```

This allows the controller to correctly determine target water levels regardless of which physical side is requested.

### Verification Confirmation

Both orientations were explicitly tested:
- Changed `lockOrientation = "west_low"` to `"east_low"` in lock_single.tla
- Re-translated PlusCal to TLA+
- Re-ran TLC model checker
- **Result:** All properties still PASS

This confirms the model is truly orientation-agnostic and satisfies the requirement stated in Section 4.2.

## Conclusion

The single lock model with the implemented control process successfully satisfies all specified properties:
- All safety invariants hold
- All liveness properties hold under weak fairness
- No deadlocks exist
- System works for both lock orientations
- Verification completes in under 1 second

The control process correctly and safely manages lock operations, ensuring ships can traverse the lock while maintaining all safety constraints.
