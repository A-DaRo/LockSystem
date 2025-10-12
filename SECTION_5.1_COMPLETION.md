# Section 5.1 Completion: Multiple Lock System Implementation

## Date: October 12, 2025

## Implementation Summary

The `controlProcess` in `lock_multiple.tla` has been successfully implemented to handle multiple locks and ships with arbitrary orientations and capacity constraints.

### Key Features Implemented:

1. **Request Handling**: The controller reads requests from the central FIFO `requests` queue that services all ships.

2. **Capacity Checking**: 
   - Determines the target location for each ship based on whether they're entering or exiting a lock
   - Counts ships at the target location using `Cardinality`
   - Enforces `MaxShipsLocation` for even locations (outside locks)
   - Enforces `MaxShipsLock` for odd locations (inside lock chambers)
   - Denies permission if capacity would be exceeded

3. **Lock Preparation** (orientation-agnostic):
   - Closes both doors before changing water level
   - Uses `LowSide(lockOrientations[req.lock])` and `HighSide(lockOrientations[req.lock])` to handle arbitrary lock orientations
   - Adjusts water level by opening appropriate valves
   - Waits for water level to stabilize using interleaving labels
   - Closes valves after water level adjustment
   - Opens the requested door

4. **Permission Management**:
   - Grants permission via ship-specific `permissions[req.ship]` queue
   - Denies permission (with appropriate message) when capacity constraints are violated

5. **Movement Observation**:
   - Waits for `moved[req.ship]` flag after granting permission
   - Clears the `moved[req.ship]` flag after observing it
   - This allows the controller to continue handling other requests

### Control Flow Labels:

The implementation uses multiple labels to break atomic steps and allow interleaving:

- `ControlLoop`: Main loop entry point
- `ControlReadRequest`: Read next request from queue
- `ControlCheckCapacity`: Calculate and verify capacity constraints
- `ControlDecideGrant`: Branch on whether to grant/deny
- `ControlDenyPermission`: Send denial message (for capacity violations)
- `ControlCloseDoors`: Close requested door (if open)
- `ControlWaitCloseDoor1`: Wait for door close command to complete
- `ControlCloseDoor2`: Close opposite door (if open)
- `ControlWaitCloseDoor2`: Wait for opposite door close
- `ControlSetTargetLevel`: Determine target water level based on orientation
- `ControlAdjustWaterLevel`: Begin water level adjustment
- `ControlWaitValveLow/High`: Wait for valve command
- `ControlWaitWaterLow/High`: Wait for water level to stabilize
- `ControlWaitCloseValveLow/High`: Wait for valve close
- `ControlOpenRequestedDoor`: Open the requested door
- `ControlWaitOpenDoor`: Wait for door open command
- `ControlGrantPermission`: Send grant message to ship
- `ControlObserveMove`: Wait for ship movement completion
- `ControlClearMoved`: Clear the moved flag

## The `moved` Variable: Analysis

### Is the `moved` variable required?

**YES**, the `moved` variable is **essential** for correct operation of the multiple ship model.

### Purpose:

The `moved` variable serves as a **synchronization mechanism** between the control process and ship processes. It allows the controller to:

1. **Know when a ship has completed its movement** after being granted permission
2. **Continue handling other requests** while waiting for a ship to move
3. **Avoid race conditions** in counting ships at locations

### What happens without `moved`?

Without the `moved` variable and the associated `ControlObserveMove` and `ControlClearMoved` steps:

1. **Capacity Violations**: The controller could grant multiple permissions before ships actually move, leading to:
   - Multiple ships being granted access to the same lock chamber (violating `MaxShipsLock`)
   - Too many ships at a location (violating `MaxShipsLocation`)
   
2. **Race Conditions**: The controller's capacity check in `ControlCheckCapacity` counts ships using `shipLocations`. Without waiting for movement to complete:
   - Ship A is at location 0, granted permission to enter lock (location 1)
   - Controller immediately proceeds to handle Ship B's request
   - Ship B at location 2 requests to enter same lock (location 1)
   - Controller checks capacity: Ship A is still at location 0 (hasn't moved yet!)
   - Controller incorrectly grants Ship B permission (thinks lock is empty)
   - Both ships try to enter lock → capacity violation

3. **Loss of Serialization**: The `moved` flag ensures that after granting permission to a ship, the controller waits for that ship to actually complete its movement before processing the next request. This maintains correct state consistency.

### Example Scenario:

Consider 2 ships wanting to enter the same lock with `MaxShipsLock = 1`:

**With `moved` variable:**
1. Ship 1 requests entry → Controller grants, waits for `moved[1]`
2. Ship 1 moves, sets `moved[1] := TRUE`
3. Controller observes `moved[1]`, clears it, processes next request
4. Ship 2 requests entry → Controller counts ships, sees Ship 1 in lock → DENIES

**Without `moved` variable:**
1. Ship 1 requests entry → Controller grants, immediately continues
2. Ship 2 requests entry → Controller checks capacity (Ship 1 still at old location!) → GRANTS
3. Both ships move → **VIOLATION**: 2 ships in lock with capacity 1

### Conclusion:

The `moved` variable is **required** to maintain correctness of capacity constraints and prevent race conditions in the multi-ship, multi-lock system. It provides essential synchronization between the controller's decision-making and the actual ship movements.

## Variables Added:

- `req`: Current request being processed
- `targetWaterLevel`: Desired water level for requested side
- `requestedSide`: Side of doors being requested
- `oppositeSide`: The other side of doors
- `targetLocation`: Calculated destination location for ship
- `canGrant`: Boolean indicating if capacity allows granting
- `shipsAtTarget`: Count of ships at target location

## Orientation Handling:

The implementation correctly handles both lock orientations ("west_low" and "east_low") by using:
- `LowSide(lockOrientations[req.lock])` to get the low-side doors
- `HighSide(lockOrientations[req.lock])` to get the high-side doors

This ensures that water level adjustments work correctly regardless of lock orientation.

## Translation Status:

✅ PlusCal code successfully translated to TLA+ using `pcal.trans`
✅ `lock_system.tla` updated to EXTEND `lock_multiple`
✅ Ready for model checking with TLC

## Next Steps:

1. Update properties in `lock_multiple.tla` to handle multiple locks/ships
2. Configure and run TLC model checker with multiple lock configurations
3. Verify deadlock freedom for 3 locks/2 ships and 4 locks/2 ships
4. Document verification results in reports
