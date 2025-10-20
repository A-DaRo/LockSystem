--------------------------- MODULE lock_multiple ---------------------------

EXTENDS lock_data


(* --algorithm lock_system

\*****************************
\* Define global variables
\*****************************
variables
  \* Variables for locks
  lockOrientations = [l \in Locks |-> IF l%2=0 THEN "west_low" ELSE "east_low"],
  doorsOpen = [l \in Locks |-> [ls \in LockSide |-> FALSE]],
  valvesOpen = [l \in Locks |-> [vs \in ValveSide |-> FALSE]],
  waterLevel = [l \in Locks |-> "low"],
  
  \* Variables for single ship
  shipLocations = [s \in Ships |-> IF s%2=0 THEN 0 ELSE EastEnd],
  shipStates = [s \in Ships |-> IF s%2=0 THEN "go_to_east" ELSE "go_to_west"],
  
  \* Command for lock
  \* for command "change_door" the side should be "west" or "east"
  \* for command "change_valve" the side should be "high" or "low"
  lockCommand = [l \in Locks |-> [command |-> "finished", open |-> FALSE, side |-> "west"]],
  \* Central requests of all ships
  requests = << >>,
  \* Permissions per ship
  permissions = [s \in Ships |-> << >>],
  moved = [s \in Ships |-> FALSE];


define

\*****************************
\* Helper functions
\*****************************
\* Check if given ship is within a lock
InLock(ship) == IsLock(shipLocations[ship])


\*****************************
\* Type checks
\*****************************
\* Check that variables use the correct type
TypeOK == /\ \A l \in Locks: /\ lockOrientations[l] \in LockOrientation
                             /\ \A ls \in LockSide : doorsOpen[l][ls] \in BOOLEAN
                             /\ \A vs \in ValveSide : valvesOpen[l][vs] \in BOOLEAN
                             /\ waterLevel[l] \in WaterLevel
                             /\ lockCommand[l].command \in LockCommand
                             /\ lockCommand[l].open \in BOOLEAN
                             /\ lockCommand[l].side \in LockSide \union ValveSide
          /\ \A s \in Ships: /\ shipLocations[s] \in Locations
                             /\ shipStates[s] \in ShipStatus
                             /\ \A i \in 1..Len(permissions[s]):
                                  /\ permissions[s][i].lock \in Locks
                                  /\ permissions[s][i].granted \in BOOLEAN
                             /\ moved[s] \in BOOLEAN
          /\ \A i \in 1..Len(requests):
               /\ requests[i].ship \in Ships
               /\ requests[i].lock \in Locks
               /\ requests[i].side \in LockSide

\* Check that message queues are not overflowing
\* Note: requests can now contain denied requests that are retrying,
\* so we allow up to NumShips * 2 to account for potential temporary growth
MessagesOK == /\ Len(requests) <= NumShips * 2
              /\ \A s \in Ships: Len(permissions[s]) <= 1


\*****************************
\* Requirements on lock
\*****************************
\* The eastern pair of doors and the western pair of doors are never simultaneously open
DoorsMutex == \A lock \in Locks: ~(doorsOpen[lock]["west"] /\ doorsOpen[lock]["east"])

\* When the lower/higher pair of doors is open, the higher/lower valve is closed.
DoorsOpenValvesClosed == 
  \A lock \in Locks:
    LET lo == lockOrientations[lock] IN
    /\ (doorsOpen[lock][LowSide(lo)] => ~valvesOpen[lock]["high"])
    /\ (doorsOpen[lock][HighSide(lo)] => ~valvesOpen[lock]["low"])

\* The lower/higher pair of doors is only open when the water level in the lock is low/high
DoorsOpenWaterlevelRight  == 
  \A lock \in Locks:
    LET lo == lockOrientations[lock] IN
    /\ (doorsOpen[lock][LowSide(lo)] => waterLevel[lock] = "low")
    /\ (doorsOpen[lock][HighSide(lo)] => waterLevel[lock] = "high")

\* Always if a ship requests to enter a lock, the ship will eventually be inside the lock.
RequestLockFulfilled == 
  \A ship \in Ships:
    (pc[ship] \in {"ShipRequestWest", "ShipRequestEast"}) ~> InLock(ship)

\* Water level is infinitely many times high/low
WaterlevelChange == 
  \A lock \in Locks:
    /\ ([]<> (waterLevel[lock] = "high"))
    /\ ([]<> (waterLevel[lock] = "low"))

\* Infinitely many times each ship does requests
RequestsShips == 
  \A ship \in Ships:
    []<> (pc[ship] \in {"ShipRequestWest", "ShipRequestEast", "ShipRequestWestInLock", "ShipRequestEastInLock"})

\* Infinitely many times each ship reaches its end location
ShipsReachGoals == 
  \A ship \in Ships:
    []<> (shipStates[ship] = "goal_reached")

\* The maximal ship capacity per location is not exceeded
MaxShipsPerLocation == 
  \A loc \in Locations:
    LET ships_at_loc == {ship \in Ships : shipLocations[ship] = loc} IN
    Cardinality(ships_at_loc) <= (IF IsLock(loc) THEN MaxShipsLock ELSE MaxShipsLocation)



end define;


\*****************************
\* Helper macros
\*****************************

\* Update the water level according to the state of doors and valves
macro updateWaterLevel(lock_orientation, doors, valves, waterlevel) begin
  if valves["low"] then
      \* Water can flow out through valve
      waterlevel := "low";
  elsif (lock_orientation = "west_low" /\ doors["west"])
         \/ (lock_orientation = "east_low" /\ doors["east"]) then
      \* Water can flow out through lower door
      waterlevel := "low";
  elsif valves["high"] then
      \* Water can flow in through valve
      waterlevel := "high";
  elsif (lock_orientation = "west_low" /\ doors["east"])
         \/ (lock_orientation = "east_low" /\ doors["west"]) then
      \* Water can flow in through higher door
      waterlevel := "high";
  \* In other case, the water level stays the same
  end if;
end macro

\* Read res from queue.
\* The macro awaits a non-empty queue.
macro read(queue, res) begin
  await queue /= <<>>;
  res := Head(queue);
  queue := Tail(queue);
end macro

\* Write msg to the queue.
macro write(queue, msg) begin
  queue := Append(queue, msg);
end macro


\*****************************
\* Process for a lock
\*****************************
process lockProcess \in Locks
begin
  LockWaitForCommand:
    while TRUE do
      await lockCommand[self].command /= "finished";
      if lockCommand[self].command = "change_door" then
        \* Change status of door
        doorsOpen[self][lockCommand[self].side] := lockCommand[self].open;
      elsif lockCommand[self].command = "change_valve" then
        \* Change status of valve
        valvesOpen[self][lockCommand[self].side] := lockCommand[self].open;
      else
        \* should not happen
        assert FALSE;
      end if;
  LockUpdateWaterLevel:
      updateWaterLevel(lockOrientations[self], doorsOpen[self], valvesOpen[self], waterLevel[self]);
  LockCommandFinished:
      lockCommand[self].command := "finished";    
    end while;
end process;


\*****************************
\* Process for a ship
\*****************************
process shipProcess \in Ships
variables
  perm = [lock |-> 1, granted |-> FALSE]
begin
  ShipNextIteration:
    while TRUE do
      if shipStates[self] = "go_to_east" then
        if shipLocations[self] = EastEnd then
  ShipGoalReachedEast:
          shipStates[self] := "goal_reached";
        else
          if ~InLock(self) then
  ShipRequestWest:
            \* Request west doors of next lock
            write(requests, [ship |-> self, lock |-> GetLock(shipLocations[self]+1), side |-> "west"]);
  ShipWaitForWest:
            \* Wait for permission
            read(permissions[self], perm);
            assert perm.lock = GetLock(shipLocations[self]+1);
          else
  ShipRequestEastInLock:
            \* Request east doors of current lock
            write(requests, [ship |-> self, lock |-> GetLock(shipLocations[self]), side |-> "east"]);
  ShipWaitForEastInLock:
            \* Wait for permission
            read(permissions[self], perm);
            assert perm.lock = GetLock(shipLocations[self]);
          end if;
  ShipMoveEast:
          if perm.granted then
            \* Move ship
            assert doorsOpen[perm.lock][IF InLock(self) THEN "east" ELSE "west"];
            shipLocations[self] := shipLocations[self] + 1;
            \* Signal finished movement
            moved[self] := TRUE;
          end if;
        end if;
      elsif shipStates[self] = "go_to_west" then
        if shipLocations[self] = WestEnd then
  ShipGoalReachedWest:
          shipStates[self] := "goal_reached";
        else
          if ~InLock(self) then
  ShipRequestEast:
            \* Request east doors of next lock
            write(requests, [ship |-> self, lock |-> GetLock(shipLocations[self]-1), side |-> "east"]);
  ShipWaitForEast:
            \* Wait for permission
            read(permissions[self], perm);
            assert perm.lock = GetLock(shipLocations[self]-1);
          else
  ShipRequestWestInLock:
            \* Request west doors of current lock
            write(requests, [ship |-> self, lock |-> GetLock(shipLocations[self]), side |-> "west"]);
  ShipWaitForWestInLock:
            \* Wait for permission
            read(permissions[self], perm);
            assert perm.lock = GetLock(shipLocations[self]);
          end if;
  ShipMoveWest:
          if perm.granted then
            \* Move ship
            assert doorsOpen[perm.lock][IF InLock(self) THEN "west" ELSE "east"];
            shipLocations[self] := shipLocations[self] - 1;
            \* Signal finished movement
            moved[self] := TRUE;
          end if;
        end if;
      else
        assert shipStates[self] = "goal_reached";
  ShipTurnAround:
        \* Turn around
        shipStates[self] := IF shipLocations[self] = WestEnd THEN "go_to_east" ELSE "go_to_west";
      end if;
    end while;
end process;

\*****************************
\* Process for the controller
\*****************************
process controlProcess = 0
variables
  req = [ship |-> NumLocks+1, lock |-> 1, side |-> "west"],
  ship_id = NumLocks+1,
  lock_id = 1,
  side = "west",
  target_loc = 0,
  grant = FALSE
begin
  ControlNextRequest:
  while TRUE do
    \* Option 4: Simple FIFO with immediate retry
    \* No separate retry queue - denied requests go to back of main queue
    \* This allows other requests (especially exits) to proceed
    \* A request may be denied multiple times before succeeding
  ControlReadRequest:
    \* Step 1: Read the next request from main queue
    read(requests, req);
    ship_id := req.ship;
    lock_id := req.lock;
    side := req.side;

  ControlCheckConditions:
    \* Step 2: Determine target location
    target_loc := IF shipStates[ship_id] = "go_to_east"
                  THEN shipLocations[ship_id] + 1
                  ELSE shipLocations[ship_id] - 1;
    
    \* Step 3: Check if capacity allows and no other ship is using this lock
    \* If ship is inside the lock (exiting), always proceed
    \* If capacity is full and ship is trying to enter, deny and retry
  ControlCheckCapacity:
    if ((IsLock(shipLocations[ship_id]) /\ GetLock(shipLocations[ship_id]) = lock_id)  \* Ship is inside this lock, must let it exit
        \/ (Cardinality({sh \in Ships : shipLocations[sh] = target_loc}) < 
            (IF IsLock(target_loc) THEN MaxShipsLock ELSE MaxShipsLocation)))
       /\ (\A s \in Ships: Len(permissions[s]) = 0 \/ 
          (\A i \in 1..Len(permissions[s]): permissions[s][i].lock /= lock_id)) then
      \* Capacity OK, proceed with preparation
      grant := TRUE;
    else
      \* Capacity not available or lock in use - deny and retry later
      grant := FALSE;
    end if;
    
  ControlDecideGrantOrRetry:
    if grant then
      \* Proceed to prepare lock and grant access
      skip;
    else
      \* Denied: put request back at END of main queue
      \* Other requests (especially exits) will be processed first
      \* This request will be tried again when it reaches the front
      write(requests, req);
      goto ControlNextRequest;
    end if;

  ControlCloseBothDoors:
    \* First, ensure both doors are closed before adjusting water level
    await lockCommand[lock_id].command = "finished";
    lockCommand[lock_id] := [command |-> "change_door", open |-> FALSE, side |-> LowSide(lockOrientations[lock_id])];
  ControlWaitLowDoorClosed:
    await lockCommand[lock_id].command = "finished";
    lockCommand[lock_id] := [command |-> "change_door", open |-> FALSE, side |-> HighSide(lockOrientations[lock_id])];
  ControlWaitHighDoorClosed:
    await lockCommand[lock_id].command = "finished";

  ControlAdjustWaterLevel:
    \* Adjust water level to match the side the ship is requesting
    \* Check if water level needs adjustment
    if waterLevel[lock_id] /= (IF side = LowSide(lockOrientations[lock_id]) THEN "low" ELSE "high") then
      \* First ensure opposite valve is closed
      lockCommand[lock_id] := [command |-> "change_valve", open |-> FALSE, 
                        side |-> IF side = LowSide(lockOrientations[lock_id]) THEN "high" ELSE "low"];
  ControlWaitOppositeValveClosed:
      await lockCommand[lock_id].command = "finished";
      \* Open the correct valve to adjust water level
      lockCommand[lock_id] := [command |-> "change_valve", open |-> TRUE, 
                        side |-> IF side = LowSide(lockOrientations[lock_id]) THEN "low" ELSE "high"];
  ControlWaitValveOpen:
      await lockCommand[lock_id].command = "finished";
      \* Wait for water level to reach target
  ControlWaitWaterLevel:
      await waterLevel[lock_id] = (IF side = LowSide(lockOrientations[lock_id]) THEN "low" ELSE "high");
      \* Close the valve after reaching target level
      lockCommand[lock_id] := [command |-> "change_valve", open |-> FALSE, 
                        side |-> IF side = LowSide(lockOrientations[lock_id]) THEN "low" ELSE "high"];
  ControlWaitValveClosed:
      await lockCommand[lock_id].command = "finished";
    end if;

  ControlOpenRequestedDoor:
    \* Now it's safe to open the requested door
    lockCommand[lock_id] := [command |-> "change_door", open |-> TRUE, side |-> side];
  ControlWaitDoorOpen:
    await lockCommand[lock_id].command = "finished";

  ControlGrantPermission:
    \* Send permission to the ship - always grant after preparation
    \* We committed to this ship after waiting for capacity to be available
    write(permissions[ship_id], [lock |-> lock_id, granted |-> TRUE]);
    \* Wait for ship to move before closing door and handling next request
  ControlWaitForShipMovement:
    await moved[ship_id];
    \* Reset the moved flag for this ship
    moved[ship_id] := FALSE;
    \* Close the door that was opened for the ship
    lockCommand[lock_id] := [command |-> "change_door", open |-> FALSE, side |-> side];
  ControlWaitDoorClosed:
    await lockCommand[lock_id].command = "finished";
    \* Now continue to next request
  end while;
end process;


end algorithm; *)


\* BEGIN TRANSLATION (chksum(pcal) = "180592f8" /\ chksum(tla) = "70dd900c")
VARIABLES lockOrientations, doorsOpen, valvesOpen, waterLevel, shipLocations, 
          shipStates, lockCommand, requests, permissions, moved, pc

(* define statement *)
InLock(ship) == IsLock(shipLocations[ship])






TypeOK == /\ \A l \in Locks: /\ lockOrientations[l] \in LockOrientation
                             /\ \A ls \in LockSide : doorsOpen[l][ls] \in BOOLEAN
                             /\ \A vs \in ValveSide : valvesOpen[l][vs] \in BOOLEAN
                             /\ waterLevel[l] \in WaterLevel
                             /\ lockCommand[l].command \in LockCommand
                             /\ lockCommand[l].open \in BOOLEAN
                             /\ lockCommand[l].side \in LockSide \union ValveSide
          /\ \A s \in Ships: /\ shipLocations[s] \in Locations
                             /\ shipStates[s] \in ShipStatus
                             /\ \A i \in 1..Len(permissions[s]):
                                  /\ permissions[s][i].lock \in Locks
                                  /\ permissions[s][i].granted \in BOOLEAN
                             /\ moved[s] \in BOOLEAN
          /\ \A i \in 1..Len(requests):
               /\ requests[i].ship \in Ships
               /\ requests[i].lock \in Locks
               /\ requests[i].side \in LockSide




MessagesOK == /\ Len(requests) <= NumShips * 2
              /\ \A s \in Ships: Len(permissions[s]) <= 1






DoorsMutex == \A lock \in Locks: ~(doorsOpen[lock]["west"] /\ doorsOpen[lock]["east"])


DoorsOpenValvesClosed ==
  \A lock \in Locks:
    LET lo == lockOrientations[lock] IN
    /\ (doorsOpen[lock][LowSide(lo)] => ~valvesOpen[lock]["high"])
    /\ (doorsOpen[lock][HighSide(lo)] => ~valvesOpen[lock]["low"])


DoorsOpenWaterlevelRight  ==
  \A lock \in Locks:
    LET lo == lockOrientations[lock] IN
    /\ (doorsOpen[lock][LowSide(lo)] => waterLevel[lock] = "low")
    /\ (doorsOpen[lock][HighSide(lo)] => waterLevel[lock] = "high")


RequestLockFulfilled ==
  \A ship \in Ships:
    (pc[ship] \in {"ShipRequestWest", "ShipRequestEast"}) ~> InLock(ship)


WaterlevelChange ==
  \A lock \in Locks:
    /\ ([]<> (waterLevel[lock] = "high"))
    /\ ([]<> (waterLevel[lock] = "low"))


RequestsShips ==
  \A ship \in Ships:
    []<> (pc[ship] \in {"ShipRequestWest", "ShipRequestEast", "ShipRequestWestInLock", "ShipRequestEastInLock"})


ShipsReachGoals ==
  \A ship \in Ships:
    []<> (shipStates[ship] = "goal_reached")


MaxShipsPerLocation ==
  \A loc \in Locations:
    LET ships_at_loc == {ship \in Ships : shipLocations[ship] = loc} IN
    Cardinality(ships_at_loc) <= (IF IsLock(loc) THEN MaxShipsLock ELSE MaxShipsLocation)

VARIABLES perm, req, ship_id, lock_id, side, target_loc, grant

vars == << lockOrientations, doorsOpen, valvesOpen, waterLevel, shipLocations, 
           shipStates, lockCommand, requests, permissions, moved, pc, perm, 
           req, ship_id, lock_id, side, target_loc, grant >>

ProcSet == (Locks) \cup (Ships) \cup {0}

Init == (* Global variables *)
        /\ lockOrientations = [l \in Locks |-> IF l%2=0 THEN "west_low" ELSE "east_low"]
        /\ doorsOpen = [l \in Locks |-> [ls \in LockSide |-> FALSE]]
        /\ valvesOpen = [l \in Locks |-> [vs \in ValveSide |-> FALSE]]
        /\ waterLevel = [l \in Locks |-> "low"]
        /\ shipLocations = [s \in Ships |-> IF s%2=0 THEN 0 ELSE EastEnd]
        /\ shipStates = [s \in Ships |-> IF s%2=0 THEN "go_to_east" ELSE "go_to_west"]
        /\ lockCommand = [l \in Locks |-> [command |-> "finished", open |-> FALSE, side |-> "west"]]
        /\ requests = << >>
        /\ permissions = [s \in Ships |-> << >>]
        /\ moved = [s \in Ships |-> FALSE]
        (* Process shipProcess *)
        /\ perm = [self \in Ships |-> [lock |-> 1, granted |-> FALSE]]
        (* Process controlProcess *)
        /\ req = [ship |-> NumLocks+1, lock |-> 1, side |-> "west"]
        /\ ship_id = NumLocks+1
        /\ lock_id = 1
        /\ side = "west"
        /\ target_loc = 0
        /\ grant = FALSE
        /\ pc = [self \in ProcSet |-> CASE self \in Locks -> "LockWaitForCommand"
                                        [] self \in Ships -> "ShipNextIteration"
                                        [] self = 0 -> "ControlNextRequest"]

LockWaitForCommand(self) == /\ pc[self] = "LockWaitForCommand"
                            /\ lockCommand[self].command /= "finished"
                            /\ IF lockCommand[self].command = "change_door"
                                  THEN /\ doorsOpen' = [doorsOpen EXCEPT ![self][lockCommand[self].side] = lockCommand[self].open]
                                       /\ UNCHANGED valvesOpen
                                  ELSE /\ IF lockCommand[self].command = "change_valve"
                                             THEN /\ valvesOpen' = [valvesOpen EXCEPT ![self][lockCommand[self].side] = lockCommand[self].open]
                                             ELSE /\ Assert(FALSE, 
                                                            "Failure of assertion at line 177, column 9.")
                                                  /\ UNCHANGED valvesOpen
                                       /\ UNCHANGED doorsOpen
                            /\ pc' = [pc EXCEPT ![self] = "LockUpdateWaterLevel"]
                            /\ UNCHANGED << lockOrientations, waterLevel, 
                                            shipLocations, shipStates, 
                                            lockCommand, requests, permissions, 
                                            moved, perm, req, ship_id, lock_id, 
                                            side, target_loc, grant >>

LockUpdateWaterLevel(self) == /\ pc[self] = "LockUpdateWaterLevel"
                              /\ IF (valvesOpen[self])["low"]
                                    THEN /\ waterLevel' = [waterLevel EXCEPT ![self] = "low"]
                                    ELSE /\ IF ((lockOrientations[self]) = "west_low" /\ (doorsOpen[self])["west"])
                                                \/ ((lockOrientations[self]) = "east_low" /\ (doorsOpen[self])["east"])
                                               THEN /\ waterLevel' = [waterLevel EXCEPT ![self] = "low"]
                                               ELSE /\ IF (valvesOpen[self])["high"]
                                                          THEN /\ waterLevel' = [waterLevel EXCEPT ![self] = "high"]
                                                          ELSE /\ IF ((lockOrientations[self]) = "west_low" /\ (doorsOpen[self])["east"])
                                                                      \/ ((lockOrientations[self]) = "east_low" /\ (doorsOpen[self])["west"])
                                                                     THEN /\ waterLevel' = [waterLevel EXCEPT ![self] = "high"]
                                                                     ELSE /\ TRUE
                                                                          /\ UNCHANGED waterLevel
                              /\ pc' = [pc EXCEPT ![self] = "LockCommandFinished"]
                              /\ UNCHANGED << lockOrientations, doorsOpen, 
                                              valvesOpen, shipLocations, 
                                              shipStates, lockCommand, 
                                              requests, permissions, moved, 
                                              perm, req, ship_id, lock_id, 
                                              side, target_loc, grant >>

LockCommandFinished(self) == /\ pc[self] = "LockCommandFinished"
                             /\ lockCommand' = [lockCommand EXCEPT ![self].command = "finished"]
                             /\ pc' = [pc EXCEPT ![self] = "LockWaitForCommand"]
                             /\ UNCHANGED << lockOrientations, doorsOpen, 
                                             valvesOpen, waterLevel, 
                                             shipLocations, shipStates, 
                                             requests, permissions, moved, 
                                             perm, req, ship_id, lock_id, side, 
                                             target_loc, grant >>

lockProcess(self) == LockWaitForCommand(self) \/ LockUpdateWaterLevel(self)
                        \/ LockCommandFinished(self)

ShipNextIteration(self) == /\ pc[self] = "ShipNextIteration"
                           /\ IF shipStates[self] = "go_to_east"
                                 THEN /\ IF shipLocations[self] = EastEnd
                                            THEN /\ pc' = [pc EXCEPT ![self] = "ShipGoalReachedEast"]
                                            ELSE /\ IF ~InLock(self)
                                                       THEN /\ pc' = [pc EXCEPT ![self] = "ShipRequestWest"]
                                                       ELSE /\ pc' = [pc EXCEPT ![self] = "ShipRequestEastInLock"]
                                 ELSE /\ IF shipStates[self] = "go_to_west"
                                            THEN /\ IF shipLocations[self] = WestEnd
                                                       THEN /\ pc' = [pc EXCEPT ![self] = "ShipGoalReachedWest"]
                                                       ELSE /\ IF ~InLock(self)
                                                                  THEN /\ pc' = [pc EXCEPT ![self] = "ShipRequestEast"]
                                                                  ELSE /\ pc' = [pc EXCEPT ![self] = "ShipRequestWestInLock"]
                                            ELSE /\ Assert(shipStates[self] = "goal_reached", 
                                                           "Failure of assertion at line 259, column 9.")
                                                 /\ pc' = [pc EXCEPT ![self] = "ShipTurnAround"]
                           /\ UNCHANGED << lockOrientations, doorsOpen, 
                                           valvesOpen, waterLevel, 
                                           shipLocations, shipStates, 
                                           lockCommand, requests, permissions, 
                                           moved, perm, req, ship_id, lock_id, 
                                           side, target_loc, grant >>

ShipGoalReachedEast(self) == /\ pc[self] = "ShipGoalReachedEast"
                             /\ shipStates' = [shipStates EXCEPT ![self] = "goal_reached"]
                             /\ pc' = [pc EXCEPT ![self] = "ShipNextIteration"]
                             /\ UNCHANGED << lockOrientations, doorsOpen, 
                                             valvesOpen, waterLevel, 
                                             shipLocations, lockCommand, 
                                             requests, permissions, moved, 
                                             perm, req, ship_id, lock_id, side, 
                                             target_loc, grant >>

ShipMoveEast(self) == /\ pc[self] = "ShipMoveEast"
                      /\ IF perm[self].granted
                            THEN /\ Assert(doorsOpen[perm[self].lock][IF InLock(self) THEN "east" ELSE "west"], 
                                           "Failure of assertion at line 221, column 13.")
                                 /\ shipLocations' = [shipLocations EXCEPT ![self] = shipLocations[self] + 1]
                                 /\ moved' = [moved EXCEPT ![self] = TRUE]
                            ELSE /\ TRUE
                                 /\ UNCHANGED << shipLocations, moved >>
                      /\ pc' = [pc EXCEPT ![self] = "ShipNextIteration"]
                      /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                      waterLevel, shipStates, lockCommand, 
                                      requests, permissions, perm, req, 
                                      ship_id, lock_id, side, target_loc, 
                                      grant >>

ShipRequestWest(self) == /\ pc[self] = "ShipRequestWest"
                         /\ requests' = Append(requests, ([ship |-> self, lock |-> GetLock(shipLocations[self]+1), side |-> "west"]))
                         /\ pc' = [pc EXCEPT ![self] = "ShipWaitForWest"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, permissions, 
                                         moved, perm, req, ship_id, lock_id, 
                                         side, target_loc, grant >>

ShipWaitForWest(self) == /\ pc[self] = "ShipWaitForWest"
                         /\ (permissions[self]) /= <<>>
                         /\ perm' = [perm EXCEPT ![self] = Head((permissions[self]))]
                         /\ permissions' = [permissions EXCEPT ![self] = Tail((permissions[self]))]
                         /\ Assert(perm'[self].lock = GetLock(shipLocations[self]+1), 
                                   "Failure of assertion at line 208, column 13.")
                         /\ pc' = [pc EXCEPT ![self] = "ShipMoveEast"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, requests, 
                                         moved, req, ship_id, lock_id, side, 
                                         target_loc, grant >>

ShipRequestEastInLock(self) == /\ pc[self] = "ShipRequestEastInLock"
                               /\ requests' = Append(requests, ([ship |-> self, lock |-> GetLock(shipLocations[self]), side |-> "east"]))
                               /\ pc' = [pc EXCEPT ![self] = "ShipWaitForEastInLock"]
                               /\ UNCHANGED << lockOrientations, doorsOpen, 
                                               valvesOpen, waterLevel, 
                                               shipLocations, shipStates, 
                                               lockCommand, permissions, moved, 
                                               perm, req, ship_id, lock_id, 
                                               side, target_loc, grant >>

ShipWaitForEastInLock(self) == /\ pc[self] = "ShipWaitForEastInLock"
                               /\ (permissions[self]) /= <<>>
                               /\ perm' = [perm EXCEPT ![self] = Head((permissions[self]))]
                               /\ permissions' = [permissions EXCEPT ![self] = Tail((permissions[self]))]
                               /\ Assert(perm'[self].lock = GetLock(shipLocations[self]), 
                                         "Failure of assertion at line 216, column 13.")
                               /\ pc' = [pc EXCEPT ![self] = "ShipMoveEast"]
                               /\ UNCHANGED << lockOrientations, doorsOpen, 
                                               valvesOpen, waterLevel, 
                                               shipLocations, shipStates, 
                                               lockCommand, requests, moved, 
                                               req, ship_id, lock_id, side, 
                                               target_loc, grant >>

ShipTurnAround(self) == /\ pc[self] = "ShipTurnAround"
                        /\ shipStates' = [shipStates EXCEPT ![self] = IF shipLocations[self] = WestEnd THEN "go_to_east" ELSE "go_to_west"]
                        /\ pc' = [pc EXCEPT ![self] = "ShipNextIteration"]
                        /\ UNCHANGED << lockOrientations, doorsOpen, 
                                        valvesOpen, waterLevel, shipLocations, 
                                        lockCommand, requests, permissions, 
                                        moved, perm, req, ship_id, lock_id, 
                                        side, target_loc, grant >>

ShipGoalReachedWest(self) == /\ pc[self] = "ShipGoalReachedWest"
                             /\ shipStates' = [shipStates EXCEPT ![self] = "goal_reached"]
                             /\ pc' = [pc EXCEPT ![self] = "ShipNextIteration"]
                             /\ UNCHANGED << lockOrientations, doorsOpen, 
                                             valvesOpen, waterLevel, 
                                             shipLocations, lockCommand, 
                                             requests, permissions, moved, 
                                             perm, req, ship_id, lock_id, side, 
                                             target_loc, grant >>

ShipMoveWest(self) == /\ pc[self] = "ShipMoveWest"
                      /\ IF perm[self].granted
                            THEN /\ Assert(doorsOpen[perm[self].lock][IF InLock(self) THEN "west" ELSE "east"], 
                                           "Failure of assertion at line 252, column 13.")
                                 /\ shipLocations' = [shipLocations EXCEPT ![self] = shipLocations[self] - 1]
                                 /\ moved' = [moved EXCEPT ![self] = TRUE]
                            ELSE /\ TRUE
                                 /\ UNCHANGED << shipLocations, moved >>
                      /\ pc' = [pc EXCEPT ![self] = "ShipNextIteration"]
                      /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                      waterLevel, shipStates, lockCommand, 
                                      requests, permissions, perm, req, 
                                      ship_id, lock_id, side, target_loc, 
                                      grant >>

ShipRequestEast(self) == /\ pc[self] = "ShipRequestEast"
                         /\ requests' = Append(requests, ([ship |-> self, lock |-> GetLock(shipLocations[self]-1), side |-> "east"]))
                         /\ pc' = [pc EXCEPT ![self] = "ShipWaitForEast"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, permissions, 
                                         moved, perm, req, ship_id, lock_id, 
                                         side, target_loc, grant >>

ShipWaitForEast(self) == /\ pc[self] = "ShipWaitForEast"
                         /\ (permissions[self]) /= <<>>
                         /\ perm' = [perm EXCEPT ![self] = Head((permissions[self]))]
                         /\ permissions' = [permissions EXCEPT ![self] = Tail((permissions[self]))]
                         /\ Assert(perm'[self].lock = GetLock(shipLocations[self]-1), 
                                   "Failure of assertion at line 239, column 13.")
                         /\ pc' = [pc EXCEPT ![self] = "ShipMoveWest"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, requests, 
                                         moved, req, ship_id, lock_id, side, 
                                         target_loc, grant >>

ShipRequestWestInLock(self) == /\ pc[self] = "ShipRequestWestInLock"
                               /\ requests' = Append(requests, ([ship |-> self, lock |-> GetLock(shipLocations[self]), side |-> "west"]))
                               /\ pc' = [pc EXCEPT ![self] = "ShipWaitForWestInLock"]
                               /\ UNCHANGED << lockOrientations, doorsOpen, 
                                               valvesOpen, waterLevel, 
                                               shipLocations, shipStates, 
                                               lockCommand, permissions, moved, 
                                               perm, req, ship_id, lock_id, 
                                               side, target_loc, grant >>

ShipWaitForWestInLock(self) == /\ pc[self] = "ShipWaitForWestInLock"
                               /\ (permissions[self]) /= <<>>
                               /\ perm' = [perm EXCEPT ![self] = Head((permissions[self]))]
                               /\ permissions' = [permissions EXCEPT ![self] = Tail((permissions[self]))]
                               /\ Assert(perm'[self].lock = GetLock(shipLocations[self]), 
                                         "Failure of assertion at line 247, column 13.")
                               /\ pc' = [pc EXCEPT ![self] = "ShipMoveWest"]
                               /\ UNCHANGED << lockOrientations, doorsOpen, 
                                               valvesOpen, waterLevel, 
                                               shipLocations, shipStates, 
                                               lockCommand, requests, moved, 
                                               req, ship_id, lock_id, side, 
                                               target_loc, grant >>

shipProcess(self) == ShipNextIteration(self) \/ ShipGoalReachedEast(self)
                        \/ ShipMoveEast(self) \/ ShipRequestWest(self)
                        \/ ShipWaitForWest(self)
                        \/ ShipRequestEastInLock(self)
                        \/ ShipWaitForEastInLock(self)
                        \/ ShipTurnAround(self)
                        \/ ShipGoalReachedWest(self) \/ ShipMoveWest(self)
                        \/ ShipRequestEast(self) \/ ShipWaitForEast(self)
                        \/ ShipRequestWestInLock(self)
                        \/ ShipWaitForWestInLock(self)

ControlNextRequest == /\ pc[0] = "ControlNextRequest"
                      /\ pc' = [pc EXCEPT ![0] = "ControlReadRequest"]
                      /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                      waterLevel, shipLocations, shipStates, 
                                      lockCommand, requests, permissions, 
                                      moved, perm, req, ship_id, lock_id, side, 
                                      target_loc, grant >>

ControlReadRequest == /\ pc[0] = "ControlReadRequest"
                      /\ requests /= <<>>
                      /\ req' = Head(requests)
                      /\ requests' = Tail(requests)
                      /\ ship_id' = req'.ship
                      /\ lock_id' = req'.lock
                      /\ side' = req'.side
                      /\ pc' = [pc EXCEPT ![0] = "ControlCheckConditions"]
                      /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                      waterLevel, shipLocations, shipStates, 
                                      lockCommand, permissions, moved, perm, 
                                      target_loc, grant >>

ControlCheckConditions == /\ pc[0] = "ControlCheckConditions"
                          /\ target_loc' = (IF shipStates[ship_id] = "go_to_east"
                                            THEN shipLocations[ship_id] + 1
                                            ELSE shipLocations[ship_id] - 1)
                          /\ pc' = [pc EXCEPT ![0] = "ControlCheckCapacity"]
                          /\ UNCHANGED << lockOrientations, doorsOpen, 
                                          valvesOpen, waterLevel, 
                                          shipLocations, shipStates, 
                                          lockCommand, requests, permissions, 
                                          moved, perm, req, ship_id, lock_id, 
                                          side, grant >>

ControlCheckCapacity == /\ pc[0] = "ControlCheckCapacity"
                        /\ IF ((IsLock(shipLocations[ship_id]) /\ GetLock(shipLocations[ship_id]) = lock_id)
                               \/ (Cardinality({sh \in Ships : shipLocations[sh] = target_loc}) <
                                   (IF IsLock(target_loc) THEN MaxShipsLock ELSE MaxShipsLocation)))
                              /\ (\A s \in Ships: Len(permissions[s]) = 0 \/
                                 (\A i \in 1..Len(permissions[s]): permissions[s][i].lock /= lock_id))
                              THEN /\ grant' = TRUE
                              ELSE /\ grant' = FALSE
                        /\ pc' = [pc EXCEPT ![0] = "ControlDecideGrantOrRetry"]
                        /\ UNCHANGED << lockOrientations, doorsOpen, 
                                        valvesOpen, waterLevel, shipLocations, 
                                        shipStates, lockCommand, requests, 
                                        permissions, moved, perm, req, ship_id, 
                                        lock_id, side, target_loc >>

ControlDecideGrantOrRetry == /\ pc[0] = "ControlDecideGrantOrRetry"
                             /\ IF grant
                                   THEN /\ TRUE
                                        /\ pc' = [pc EXCEPT ![0] = "ControlCloseBothDoors"]
                                        /\ UNCHANGED requests
                                   ELSE /\ requests' = Append(requests, req)
                                        /\ pc' = [pc EXCEPT ![0] = "ControlNextRequest"]
                             /\ UNCHANGED << lockOrientations, doorsOpen, 
                                             valvesOpen, waterLevel, 
                                             shipLocations, shipStates, 
                                             lockCommand, permissions, moved, 
                                             perm, req, ship_id, lock_id, side, 
                                             target_loc, grant >>

ControlCloseBothDoors == /\ pc[0] = "ControlCloseBothDoors"
                         /\ lockCommand[lock_id].command = "finished"
                         /\ lockCommand' = [lockCommand EXCEPT ![lock_id] = [command |-> "change_door", open |-> FALSE, side |-> LowSide(lockOrientations[lock_id])]]
                         /\ pc' = [pc EXCEPT ![0] = "ControlWaitLowDoorClosed"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, requests, permissions, 
                                         moved, perm, req, ship_id, lock_id, 
                                         side, target_loc, grant >>

ControlWaitLowDoorClosed == /\ pc[0] = "ControlWaitLowDoorClosed"
                            /\ lockCommand[lock_id].command = "finished"
                            /\ lockCommand' = [lockCommand EXCEPT ![lock_id] = [command |-> "change_door", open |-> FALSE, side |-> HighSide(lockOrientations[lock_id])]]
                            /\ pc' = [pc EXCEPT ![0] = "ControlWaitHighDoorClosed"]
                            /\ UNCHANGED << lockOrientations, doorsOpen, 
                                            valvesOpen, waterLevel, 
                                            shipLocations, shipStates, 
                                            requests, permissions, moved, perm, 
                                            req, ship_id, lock_id, side, 
                                            target_loc, grant >>

ControlWaitHighDoorClosed == /\ pc[0] = "ControlWaitHighDoorClosed"
                             /\ lockCommand[lock_id].command = "finished"
                             /\ pc' = [pc EXCEPT ![0] = "ControlAdjustWaterLevel"]
                             /\ UNCHANGED << lockOrientations, doorsOpen, 
                                             valvesOpen, waterLevel, 
                                             shipLocations, shipStates, 
                                             lockCommand, requests, 
                                             permissions, moved, perm, req, 
                                             ship_id, lock_id, side, 
                                             target_loc, grant >>

ControlAdjustWaterLevel == /\ pc[0] = "ControlAdjustWaterLevel"
                           /\ IF waterLevel[lock_id] /= (IF side = LowSide(lockOrientations[lock_id]) THEN "low" ELSE "high")
                                 THEN /\ lockCommand' = [lockCommand EXCEPT ![lock_id] =       [command |-> "change_valve", open |-> FALSE,
                                                                                         side |-> IF side = LowSide(lockOrientations[lock_id]) THEN "high" ELSE "low"]]
                                      /\ pc' = [pc EXCEPT ![0] = "ControlWaitOppositeValveClosed"]
                                 ELSE /\ pc' = [pc EXCEPT ![0] = "ControlOpenRequestedDoor"]
                                      /\ UNCHANGED lockCommand
                           /\ UNCHANGED << lockOrientations, doorsOpen, 
                                           valvesOpen, waterLevel, 
                                           shipLocations, shipStates, requests, 
                                           permissions, moved, perm, req, 
                                           ship_id, lock_id, side, target_loc, 
                                           grant >>

ControlWaitOppositeValveClosed == /\ pc[0] = "ControlWaitOppositeValveClosed"
                                  /\ lockCommand[lock_id].command = "finished"
                                  /\ lockCommand' = [lockCommand EXCEPT ![lock_id] =       [command |-> "change_valve", open |-> TRUE,
                                                                                     side |-> IF side = LowSide(lockOrientations[lock_id]) THEN "low" ELSE "high"]]
                                  /\ pc' = [pc EXCEPT ![0] = "ControlWaitValveOpen"]
                                  /\ UNCHANGED << lockOrientations, doorsOpen, 
                                                  valvesOpen, waterLevel, 
                                                  shipLocations, shipStates, 
                                                  requests, permissions, moved, 
                                                  perm, req, ship_id, lock_id, 
                                                  side, target_loc, grant >>

ControlWaitValveOpen == /\ pc[0] = "ControlWaitValveOpen"
                        /\ lockCommand[lock_id].command = "finished"
                        /\ pc' = [pc EXCEPT ![0] = "ControlWaitWaterLevel"]
                        /\ UNCHANGED << lockOrientations, doorsOpen, 
                                        valvesOpen, waterLevel, shipLocations, 
                                        shipStates, lockCommand, requests, 
                                        permissions, moved, perm, req, ship_id, 
                                        lock_id, side, target_loc, grant >>

ControlWaitWaterLevel == /\ pc[0] = "ControlWaitWaterLevel"
                         /\ waterLevel[lock_id] = (IF side = LowSide(lockOrientations[lock_id]) THEN "low" ELSE "high")
                         /\ lockCommand' = [lockCommand EXCEPT ![lock_id] =       [command |-> "change_valve", open |-> FALSE,
                                                                            side |-> IF side = LowSide(lockOrientations[lock_id]) THEN "low" ELSE "high"]]
                         /\ pc' = [pc EXCEPT ![0] = "ControlWaitValveClosed"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, requests, permissions, 
                                         moved, perm, req, ship_id, lock_id, 
                                         side, target_loc, grant >>

ControlWaitValveClosed == /\ pc[0] = "ControlWaitValveClosed"
                          /\ lockCommand[lock_id].command = "finished"
                          /\ pc' = [pc EXCEPT ![0] = "ControlOpenRequestedDoor"]
                          /\ UNCHANGED << lockOrientations, doorsOpen, 
                                          valvesOpen, waterLevel, 
                                          shipLocations, shipStates, 
                                          lockCommand, requests, permissions, 
                                          moved, perm, req, ship_id, lock_id, 
                                          side, target_loc, grant >>

ControlOpenRequestedDoor == /\ pc[0] = "ControlOpenRequestedDoor"
                            /\ lockCommand' = [lockCommand EXCEPT ![lock_id] = [command |-> "change_door", open |-> TRUE, side |-> side]]
                            /\ pc' = [pc EXCEPT ![0] = "ControlWaitDoorOpen"]
                            /\ UNCHANGED << lockOrientations, doorsOpen, 
                                            valvesOpen, waterLevel, 
                                            shipLocations, shipStates, 
                                            requests, permissions, moved, perm, 
                                            req, ship_id, lock_id, side, 
                                            target_loc, grant >>

ControlWaitDoorOpen == /\ pc[0] = "ControlWaitDoorOpen"
                       /\ lockCommand[lock_id].command = "finished"
                       /\ pc' = [pc EXCEPT ![0] = "ControlGrantPermission"]
                       /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                       waterLevel, shipLocations, shipStates, 
                                       lockCommand, requests, permissions, 
                                       moved, perm, req, ship_id, lock_id, 
                                       side, target_loc, grant >>

ControlGrantPermission == /\ pc[0] = "ControlGrantPermission"
                          /\ permissions' = [permissions EXCEPT ![ship_id] = Append((permissions[ship_id]), ([lock |-> lock_id, granted |-> TRUE]))]
                          /\ pc' = [pc EXCEPT ![0] = "ControlWaitForShipMovement"]
                          /\ UNCHANGED << lockOrientations, doorsOpen, 
                                          valvesOpen, waterLevel, 
                                          shipLocations, shipStates, 
                                          lockCommand, requests, moved, perm, 
                                          req, ship_id, lock_id, side, 
                                          target_loc, grant >>

ControlWaitForShipMovement == /\ pc[0] = "ControlWaitForShipMovement"
                              /\ moved[ship_id]
                              /\ moved' = [moved EXCEPT ![ship_id] = FALSE]
                              /\ lockCommand' = [lockCommand EXCEPT ![lock_id] = [command |-> "change_door", open |-> FALSE, side |-> side]]
                              /\ pc' = [pc EXCEPT ![0] = "ControlWaitDoorClosed"]
                              /\ UNCHANGED << lockOrientations, doorsOpen, 
                                              valvesOpen, waterLevel, 
                                              shipLocations, shipStates, 
                                              requests, permissions, perm, req, 
                                              ship_id, lock_id, side, 
                                              target_loc, grant >>

ControlWaitDoorClosed == /\ pc[0] = "ControlWaitDoorClosed"
                         /\ lockCommand[lock_id].command = "finished"
                         /\ pc' = [pc EXCEPT ![0] = "ControlNextRequest"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, requests, 
                                         permissions, moved, perm, req, 
                                         ship_id, lock_id, side, target_loc, 
                                         grant >>

controlProcess == ControlNextRequest \/ ControlReadRequest
                     \/ ControlCheckConditions \/ ControlCheckCapacity
                     \/ ControlDecideGrantOrRetry \/ ControlCloseBothDoors
                     \/ ControlWaitLowDoorClosed
                     \/ ControlWaitHighDoorClosed
                     \/ ControlAdjustWaterLevel
                     \/ ControlWaitOppositeValveClosed
                     \/ ControlWaitValveOpen \/ ControlWaitWaterLevel
                     \/ ControlWaitValveClosed \/ ControlOpenRequestedDoor
                     \/ ControlWaitDoorOpen \/ ControlGrantPermission
                     \/ ControlWaitForShipMovement \/ ControlWaitDoorClosed

Next == controlProcess
           \/ (\E self \in Locks: lockProcess(self))
           \/ (\E self \in Ships: shipProcess(self))

Spec == Init /\ [][Next]_vars

\* END TRANSLATION 

\* Fairness specification: weak fairness for all processes
\* This ensures that continuously enabled actions will eventually be taken
FairSpec == Spec 
            /\ WF_vars(controlProcess)
            /\ \A lock_proc \in Locks : WF_vars(lockProcess(lock_proc))
            /\ \A ship_proc \in Ships : WF_vars(shipProcess(ship_proc))

=============================================================================
\* Modification History
\* Last modified Wed Sep 24 12:00:55 CEST 2025 by mvolk
\* Created Thu Aug 28 11:30:07 CEST 2025 by mvolk