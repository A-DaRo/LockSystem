Proceed to implement in full the structured plan for completing Task 2. The plan focuses on ensuring validity of the liveness properties. But you should also consider and make sure to keep track of the overall algorithm correctness and completeness in accordance with the other verifying properies.

---

Here is a structured plan for completing Task 2: implementing and verifying the multiple locks/ships model, with a focus on the `controlProcess` structure to ensure liveness properties hold.

### 1. Analysis of Provided TLA+ Modules

*   **`lock_data.tla`**: Defines the foundational data types (`Locks`, `Ships`, `Locations`), constants (`NumLocks`, `NumShips`, `MaxShipsLocation`, `MaxShipsLock`), and helper functions (`LowSide`, `HighSide`, `GetLock`, `IsLock`). These are the building blocks for the model.
*   **`lock_multiple.tla`**: This module extends `lock_data` and defines the system's state and behavior.
    *   **Global Variables**: All state variables from the single model are now arrays indexed by lock `l` or ship `s` (e.g., `doorsOpen[l]`, `shipLocations[s]`). This is the key change for generalization.
    *   **Communication**:
        *   `requests`: A single, global FIFO queue for all ship requests.
        *   `permissions[s]`: A per-ship queue for responses from the controller.
        *   `moved[s]`: A new boolean flag per ship, set to `TRUE` by a ship process after it completes a move. This serves as a synchronization signal for the controller.
    *   **Processes**:
        *   `lockProcess \in Locks`: Each lock runs its own process, waiting for commands in `lockCommand[self]` and updating its state (`doorsOpen[self]`, `waterLevel[self]`, etc.).
        *   `shipProcess \in Ships`: Each ship runs its own process, sending requests to the central `requests` queue and waiting for a response in its own `permissions[self]` queue. After a successful move, it sets `moved[self] := TRUE`.
    *   **`controlProcess`**: The core of the task is to implement this process. It is currently a `skip` statement.

### 2. Structured Plan for `controlProcess` Implementation

The controller must be **non-blocking** and **fair**. It should process requests from the queue, but if a request cannot be immediately fulfilled (e.g., due to capacity limits), it must not get stuck. It should deny the request, allowing the ship to retry, and proceed to handle other requests. This ensures progress for the overall system.

The `controlProcess` will be structured as a single, infinite loop that reads and processes one request at a time. The logic within the loop will be broken down into atomic steps using PlusCal labels.

---

#### **Algorithm for `controlProcess`**

```pluscal
process controlProcess = 0
variables
  req = [ship |-> 1, lock |-> 1, side |-> "west"],
  s = 1, l = 1, side = "west",
  target_loc = 0,
  grant = FALSE
begin
  ControlNextRequest:
  while TRUE do
    (* Step 1: Read the next request from the central FIFO queue. This is a blocking step. *)
    read(requests, req);
    s := req.ship;
    l := req.lock;
    side := req.side;

  ControlCheckConditions:
    (* Step 2: Check if the request can be granted. This involves checking capacity. *)
    \* Determine target location for the ship
    target_loc := IF shipStates[s] = "go_to_east"
                  THEN shipLocations[s] + 1
                  ELSE shipLocations[s] - 1;

    \* Check capacity at target location
    with
      ships_at_target = {sh \in Ships : shipLocations[sh] = target_loc},
      capacity = IF IsLock(target_loc) THEN MaxShipsLock ELSE MaxShipsLocation
    do
      grant := Cardinality(ships_at_target) < capacity;
    end with;

    if ~grant then
      (* Step 3a: Deny the request if conditions are not met. *)
      ControlDeny:
        write(permissions[s], [lock |-> l, granted |-> FALSE]);
        goto ControlNextRequest;
    else
      (* Step 3b: If conditions are met, begin the safe lock operation sequence. *)
      ControlPrepareLock:
        \* Ensure both doors are closed before changing water level.
        \* This is a critical safety step.
        await lockCommand[l].command = "finished";
        lockCommand[l] := [command |-> "change_door", open |-> FALSE, side |-> LowSide(lockOrientations[l])];
        await lockCommand[l].command = "finished";
        lockCommand[l] := [command |-> "change_door", open |-> FALSE, side |-> HighSide(lockOrientations[l])];
        await lockCommand[l].command = "finished";

      ControlSetWaterLevel:
        \* Adjust water level to match the side the ship is on.
        with
          target_level = IF side = LowSide(lockOrientations[l]) THEN "low" ELSE "high",
          valve_side = IF side = LowSide(lockOrientations[l]) THEN "low" ELSE "high"
        do
          if waterLevel[l] /= target_level then
            \* Open valve, wait for level to change, then close valve.
            lockCommand[l] := [command |-> "change_valve", open |-> TRUE, side |-> valve_side];
            await lockCommand[l].command = "finished";
            await waterLevel[l] = target_level;
            lockCommand[l] := [command |-> "change_valve", open |-> FALSE, side |-> valve_side];
            await lockCommand[l].command = "finished";
          end if;
        end with;

      ControlOpenDoor:
        \* Open the requested door.
        lockCommand[l] := [command |-> "change_door", open |-> TRUE, side |-> side];
        await lockCommand[l].command = "finished";

      ControlSendPermission:
        \* Finally, grant permission to the ship.
        write(permissions[s], [lock |-> l, granted |-> TRUE]);
        (* The controller immediately loops back to `ControlNextRequest` to handle the next ship,
           achieving the required interleaving. It does not wait for the ship to move. *)
    end if;
  end while;
end process
```

---

### 3. Plan for Liveness and Fairness

The primary liveness property is `RequestLockFulfilled`: a ship that requests a lock will eventually get it. The proposed controller logic, combined with fairness assumptions, ensures this.

1.  **FIFO `requests` Queue**: A ship's request will eventually reach the head of the queue.
2.  **Controller Progress**: The controller is always trying to process the request at the head of the queue.
3.  **No Deadlock/Livelock in Controller**:
    *   If a request can be granted, the controller proceeds.
    *   If a request cannot be granted (due to capacity), the controller **denies** it and immediately moves to the next request. The ship process is designed to re-issue the request.
4.  **System-level Progress**: As other ships move, the capacity constraints that blocked the initial request will eventually change, allowing the denied request to be granted on a subsequent attempt.

**Required Fairness Assumption:**

To guarantee that a continuously-enabled action is eventually taken, we must apply **Weak Fairness** to the `controlProcess`.

*   **`WF_vars(controlProcess)`**: This will be specified in the TLC model configuration (`MC.cfg`). It ensures that if the `requests` queue is persistently non-empty, the controller process will eventually be scheduled to execute its `read(requests, req)` step. Without this, the model checker could generate a counterexample where only ship and lock processes run, starving the controller and violating liveness.

The combination of the FIFO queue, the non-blocking "deny-and-retry" logic, and `WF_vars(controlProcess)` is the core strategy to satisfy the liveness properties.

### 4. Role and Justification of `moved[s]`

**Is `moved[s]` required?** Yes, but not for the controller's core logic as designed above. The `shipLocations[s]` variable, which is updated atomically with the move, is sufficient for the capacity check. The primary role of `moved[s]` is to solve a subtle race condition related to resource management and liveness verification.

**What happens if `moved` is not used?**
Without a `moved` signal, the controller has no direct way of knowing when a ship has *completed* its move. It grants permission and immediately forgets about that ship.
Consider this scenario:
1.  Controller grants ship `s1` permission to enter lock `l`.
2.  Controller immediately processes the next request, which is from `s1` to *exit* lock `l`.
3.  However, `s1` has not even executed its `ShipMoveEast` step yet; its `shipLocations[s1]` variable has not been updated. The controller sees `s1` as still being outside the lock.
4.  The controller would then try to prepare the lock for `s1`'s exit while `s1` is still trying to enter. This can lead to incorrect state calculations and potential deadlock or safety violations if the controller's logic becomes more complex (e.g., reserving locks).

**Justification for `moved[s]`:**
The `moved[s]` flag acts as an acknowledgment. A more robust controller could use it to track which ships are "in transit". For this assignment, its main purpose is to allow the system to correctly model the sequence of events: `grant -> move -> acknowledged`. While the current simple controller doesn't explicitly wait on `moved[s]`, the flag is crucial for the model checker to distinguish between a state where permission has been granted and a state where the move is complete. This fine-grained state distinction can be essential for proving complex properties and avoiding spurious counterexamples. For instance, the controller could be extended with a step to observe and reset `moved[s]` flags, allowing it to maintain a more accurate picture of the system state before processing new requests.

### 5. Plan for Implementing and Verifying Properties

For each property, the placeholder `FALSE` will be replaced with a TLA+ formula quantified over all locks and/or ships.

1.  **`DoorsMutex` (Safety/Invariant):**
    `\A l \in Locks: ~(doorsOpen[l]["west"] /\ doorsOpen[l]["east"])`

2.  **`DoorsOpenValvesClosed` (Safety/Invariant):**
    ```tla
    \A l \in Locks:
      LET lo == lockOrientations[l] IN
      /\ (doorsOpen[l][LowSide(lo)] => ~valvesOpen[l]["high"])
      /\ (doorsOpen[l][HighSide(lo)] => ~valvesOpen[l]["low"])
    ```

3.  **`DoorsOpenWaterlevelRight` (Safety/Invariant):**
    ```tla
    \A l \in Locks:
      LET lo == lockOrientations[l] IN
      /\ (doorsOpen[l][LowSide(lo)] => waterLevel[l] = "low")
      /\ (doorsOpen[l][HighSide(lo)] => waterLevel[l] = "high")
    ```

4.  **`MaxShipsPerLocation` (Safety/Invariant):**
    ```tla
    \A loc \in Locations:
      LET ships_at_loc == {s \in Ships : shipLocations[s] = loc} IN
      Cardinality(ships_at_loc) <= (IF IsLock(loc) THEN MaxShipsLock ELSE MaxShipsLocation)
    ```

5.  **`RequestLockFulfilled` (Liveness/Temporal Property):** This property states that a request eventually leads to being in the lock. This can be tied to the process control location (`pc`).
    ```tla
    \A s \in Ships:
      (pc[s] \in {"ShipRequestWest", "ShipRequestEast"}) ~> InLock(s)
    ```
    This needs `WF_vars(controlProcess)` to hold.

6.  **`WaterlevelChange` (Liveness/Temporal Property):**
    `\A l \in Locks: ([]<> (waterLevel[l] = "high")) /\ ([]<> (waterLevel[l] = "low"))`

7.  **`RequestsShips` (Liveness/Temporal Property):** Each ship infinitely often makes a request. This is inherent to the `shipProcess` design.
    `\A s \in Ships: []<> (pc[s] \in {"ShipRequestWest", "ShipRequestEast", "ShipRequestWestInLock", "ShipRequestEastInLock"})`

8.  **`ShipsReachGoals` (Liveness/Temporal Property):** Each ship infinitely often reaches its goal state.
    `\A s \in Ships: []<> (shipStates[s] = "goal_reached")`