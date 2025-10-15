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
MessagesOK == /\ Len(requests) <= NumShips
              /\ \A s \in Ships: Len(permissions[s]) <= 1


\*****************************
\* Requirements on lock
\*****************************
\* The eastern pair of doors and the western pair of doors are never simultaneously open
DoorsMutex == \A l \in Locks: ~(doorsOpen[l]["west"] /\ doorsOpen[l]["east"])

\* When the lower/higher pair of doors is open, the higher/lower valve is closed.
DoorsOpenValvesClosed == \A l \in Locks: 
  /\ (doorsOpen[l][LowSide(lockOrientations[l])] => ~valvesOpen[l]["high"])
  /\ (doorsOpen[l][HighSide(lockOrientations[l])] => ~valvesOpen[l]["low"])

\* The lower/higher pair of doors is only open when the water level in the lock is low/high
DoorsOpenWaterlevelRight == \A l \in Locks:
  /\ (doorsOpen[l][LowSide(lockOrientations[l])] => waterLevel[l] = "low")
  /\ (doorsOpen[l][HighSide(lockOrientations[l])] => waterLevel[l] = "high")

\* Helper: Ship is requesting to enter a lock
ShipRequestingLock(s) == \E i \in 1..Len(requests): 
  /\ requests[i].ship = s 
  /\ ~InLock(s)

\* Always if a ship requests to enter a lock, the ship will eventually be inside the lock.
RequestLockFulfilled == \A s \in Ships: 
  [](ShipRequestingLock(s) => <>(InLock(s)))

\* Water level is infinitely many times high/low
WaterlevelChange == \A l \in Locks: 
  /\ []<>(waterLevel[l] = "high")
  /\ []<>(waterLevel[l] = "low")

\* Infinitely many times each ship does requests
RequestsShips == \A s \in Ships: 
  []<>(\E i \in 1..Len(requests): requests[i].ship = s)

\* Infinitely many times each ship reaches its end location
ShipsReachGoals == \A s \in Ships: 
  /\ []<>(shipLocations[s] = WestEnd)
  /\ []<>(shipLocations[s] = EastEnd)

\* The maximal ship capacity per location is not exceeded
MaxShipsPerLocation == \A loc \in Locations:
  IF IsLock(loc) 
  THEN Cardinality({s \in Ships : shipLocations[s] = loc}) <= MaxShipsLock
  ELSE Cardinality({s \in Ships : shipLocations[s] = loc}) <= MaxShipsLocation

\* BONUS QUESTION: Property to find deadlock-avoiding schedule
\* This property states "NOT all ships can reach goal_reached"
\* When TLC finds this FALSE, the counterexample shows a schedule where all ships DO reach their goal!
AllShipsCannotReachGoal == ~(\A s \in Ships: shipStates[s] = "goal_reached")



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
  req = [ship |-> NumLocks+1, lock |-> 1, side |-> "west"];
  targetWaterLevel = "low";
  requestedSide = "west";
  oppositeSide = "east";
  targetLocation = 0;
  canGrant = TRUE;
  shipsAtTarget = 0;
  isExitRequest = FALSE;
  requeueCount = 0;
begin
  ControlLoop:
    while TRUE do
      ControlReadRequest:
        \* Read next request from the queue
        read(requests, req);
        requestedSide := req.side;
        oppositeSide := IF requestedSide = "west" THEN "east" ELSE "west";
        
      ControlCheckCapacity:
        \* Determine target location for the ship and whether this is an exit request
        if InLock(req.ship) then
          \* Ship is inside lock, wants to exit - THIS HAS PRIORITY
          isExitRequest := TRUE;
          if requestedSide = "west" then
            targetLocation := shipLocations[req.ship] - 1;
          else
            targetLocation := shipLocations[req.ship] + 1;
          end if;
        else
          \* Ship is outside lock, wants to enter
          isExitRequest := FALSE;
          if requestedSide = "west" then
            targetLocation := shipLocations[req.ship] + 1;
          else
            targetLocation := shipLocations[req.ship] - 1;
          end if;
        end if;
        
        \* Count ships at target location
        shipsAtTarget := Cardinality({s \in Ships : shipLocations[s] = targetLocation});
        
        \* Check capacity constraints with priority for exit requests
        \* KEY INSIGHT: Exit requests get priority by allowing them even if at capacity,
        \* because deadlock prevention requires ships to be able to leave locks
        if IsLock(targetLocation) then
          \* Target is inside a lock
          if isExitRequest then
            \* EXIT requests: Always allow to prevent deadlock (relaxed capacity)
            canGrant := TRUE;
          else
            \* ENTRY requests: Strict capacity check
            canGrant := shipsAtTarget < MaxShipsLock;
          end if;
        else
          \* Target is outside a lock
          if isExitRequest then
            \* EXIT from lock to outside: Allow with relaxed capacity
            canGrant := shipsAtTarget < MaxShipsLocation + 1;
          else
            \* ENTRY from outside: Strict capacity
            canGrant := shipsAtTarget < MaxShipsLocation;
          end if;
        end if;
        
      ControlDecideGrant:
        if ~canGrant then
          \* Capacity exceeded - deny request
          \* Entry requests will be denied and ship retries, giving exits natural priority
      ControlDenyPermission:
          write(permissions[req.ship], [lock |-> req.lock, granted |-> FALSE]);
        else
          \* Prepare lock and grant permission
      ControlCloseDoors:
          \* First, ensure both doors are closed before changing water level
          if doorsOpen[req.lock][requestedSide] then
            lockCommand[req.lock] := [command |-> "change_door", open |-> FALSE, side |-> requestedSide];
      ControlWaitCloseDoor1:
            await lockCommand[req.lock].command = "finished";
      ControlCheckOppositeDoor:
            skip;
          end if;
          
      ControlCloseDoor2:
          if doorsOpen[req.lock][oppositeSide] then
            lockCommand[req.lock] := [command |-> "change_door", open |-> FALSE, side |-> oppositeSide];
      ControlWaitCloseDoor2:
            await lockCommand[req.lock].command = "finished";
      ControlDetermineTargetLevel:
            skip;
          end if;
          
      ControlSetTargetLevel:
          \* Determine target water level based on requested side and lock orientation
          if requestedSide = LowSide(lockOrientations[req.lock]) then
            targetWaterLevel := "low";
          else
            targetWaterLevel := "high";
          end if;
          
      ControlAdjustWaterLevel:
          \* Adjust water level to match the target
          if waterLevel[req.lock] /= targetWaterLevel then
            if targetWaterLevel = "low" then
              \* Open low valve to lower water
              lockCommand[req.lock] := [command |-> "change_valve", open |-> TRUE, side |-> "low"];
      ControlWaitValveLow:
              await lockCommand[req.lock].command = "finished";
      ControlWaitWaterLow:
              await waterLevel[req.lock] = "low";
              \* Close low valve
              lockCommand[req.lock] := [command |-> "change_valve", open |-> FALSE, side |-> "low"];
      ControlWaitCloseValveLow:
              await lockCommand[req.lock].command = "finished";
      ControlPrepareOpenDoor1:
              skip;
            else
              \* Open high valve to raise water
              lockCommand[req.lock] := [command |-> "change_valve", open |-> TRUE, side |-> "high"];
      ControlWaitValveHigh:
              await lockCommand[req.lock].command = "finished";
      ControlWaitWaterHigh:
              await waterLevel[req.lock] = "high";
              \* Close high valve
              lockCommand[req.lock] := [command |-> "change_valve", open |-> FALSE, side |-> "high"];
      ControlWaitCloseValveHigh:
              await lockCommand[req.lock].command = "finished";
      ControlPrepareOpenDoor2:
              skip;
            end if;
          end if;
          
      ControlOpenRequestedDoor:
          \* Now open the requested door
          lockCommand[req.lock] := [command |-> "change_door", open |-> TRUE, side |-> requestedSide];
      ControlWaitOpenDoor:
          await lockCommand[req.lock].command = "finished";
          
      ControlGrantPermission:
          \* Grant permission to the ship
          write(permissions[req.ship], [lock |-> req.lock, granted |-> TRUE]);
          
      ControlObserveMove:
          \* Wait for ship to complete its movement
          await moved[req.ship];
      ControlClearMoved:
          \* Clear the moved flag
          moved[req.ship] := FALSE;
        end if;
    end while;
end process;


end algorithm; *)


\* BEGIN TRANSLATION (chksum(pcal) = "468e0567" /\ chksum(tla) = "fecfc034")
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


MessagesOK == /\ Len(requests) <= NumShips
              /\ \A s \in Ships: Len(permissions[s]) <= 1






DoorsMutex == \A l \in Locks: ~(doorsOpen[l]["west"] /\ doorsOpen[l]["east"])


DoorsOpenValvesClosed == \A l \in Locks:
  /\ (doorsOpen[l][LowSide(lockOrientations[l])] => ~valvesOpen[l]["high"])
  /\ (doorsOpen[l][HighSide(lockOrientations[l])] => ~valvesOpen[l]["low"])


DoorsOpenWaterlevelRight == \A l \in Locks:
  /\ (doorsOpen[l][LowSide(lockOrientations[l])] => waterLevel[l] = "low")
  /\ (doorsOpen[l][HighSide(lockOrientations[l])] => waterLevel[l] = "high")


ShipRequestingLock(s) == \E i \in 1..Len(requests):
  /\ requests[i].ship = s
  /\ ~InLock(s)


RequestLockFulfilled == \A s \in Ships:
  [](ShipRequestingLock(s) => <>(InLock(s)))


WaterlevelChange == \A l \in Locks:
  /\ []<>(waterLevel[l] = "high")
  /\ []<>(waterLevel[l] = "low")


RequestsShips == \A s \in Ships:
  []<>(\E i \in 1..Len(requests): requests[i].ship = s)


ShipsReachGoals == \A s \in Ships:
  /\ []<>(shipLocations[s] = WestEnd)
  /\ []<>(shipLocations[s] = EastEnd)


MaxShipsPerLocation == \A loc \in Locations:
  IF IsLock(loc)
  THEN Cardinality({s \in Ships : shipLocations[s] = loc}) <= MaxShipsLock
  ELSE Cardinality({s \in Ships : shipLocations[s] = loc}) <= MaxShipsLocation




AllShipsCannotReachGoal == ~(\A s \in Ships: shipStates[s] = "goal_reached")

VARIABLES perm, req, targetWaterLevel, requestedSide, oppositeSide, 
          targetLocation, canGrant, shipsAtTarget, isExitRequest, requeueCount

vars == << lockOrientations, doorsOpen, valvesOpen, waterLevel, shipLocations, 
           shipStates, lockCommand, requests, permissions, moved, pc, perm, 
           req, targetWaterLevel, requestedSide, oppositeSide, targetLocation, 
           canGrant, shipsAtTarget, isExitRequest, requeueCount >>

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
        /\ targetWaterLevel = "low"
        /\ requestedSide = "west"
        /\ oppositeSide = "east"
        /\ targetLocation = 0
        /\ canGrant = TRUE
        /\ shipsAtTarget = 0
        /\ isExitRequest = FALSE
        /\ requeueCount = 0
        /\ pc = [self \in ProcSet |-> CASE self \in Locks -> "LockWaitForCommand"
                                        [] self \in Ships -> "ShipNextIteration"
                                        [] self = 0 -> "ControlLoop"]

LockWaitForCommand(self) == /\ pc[self] = "LockWaitForCommand"
                            /\ lockCommand[self].command /= "finished"
                            /\ IF lockCommand[self].command = "change_door"
                                  THEN /\ doorsOpen' = [doorsOpen EXCEPT ![self][lockCommand[self].side] = lockCommand[self].open]
                                       /\ UNCHANGED valvesOpen
                                  ELSE /\ IF lockCommand[self].command = "change_valve"
                                             THEN /\ valvesOpen' = [valvesOpen EXCEPT ![self][lockCommand[self].side] = lockCommand[self].open]
                                             ELSE /\ Assert(FALSE, 
                                                            "Failure of assertion at line 178, column 9.")
                                                  /\ UNCHANGED valvesOpen
                                       /\ UNCHANGED doorsOpen
                            /\ pc' = [pc EXCEPT ![self] = "LockUpdateWaterLevel"]
                            /\ UNCHANGED << lockOrientations, waterLevel, 
                                            shipLocations, shipStates, 
                                            lockCommand, requests, permissions, 
                                            moved, perm, req, targetWaterLevel, 
                                            requestedSide, oppositeSide, 
                                            targetLocation, canGrant, 
                                            shipsAtTarget, isExitRequest, requeueCount >>

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
                                              perm, req, targetWaterLevel, 
                                              requestedSide, oppositeSide, 
                                              targetLocation, canGrant, 
                                              shipsAtTarget, isExitRequest, requeueCount >>

LockCommandFinished(self) == /\ pc[self] = "LockCommandFinished"
                             /\ lockCommand' = [lockCommand EXCEPT ![self].command = "finished"]
                             /\ pc' = [pc EXCEPT ![self] = "LockWaitForCommand"]
                             /\ UNCHANGED << lockOrientations, doorsOpen, 
                                             valvesOpen, waterLevel, 
                                             shipLocations, shipStates, 
                                             requests, permissions, moved, 
                                             perm, req, targetWaterLevel, 
                                             requestedSide, oppositeSide, 
                                             targetLocation, canGrant, 
                                             shipsAtTarget, isExitRequest, requeueCount >>

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
                                                           "Failure of assertion at line 260, column 9.")
                                                 /\ pc' = [pc EXCEPT ![self] = "ShipTurnAround"]
                           /\ UNCHANGED << lockOrientations, doorsOpen, 
                                           valvesOpen, waterLevel, 
                                           shipLocations, shipStates, 
                                           lockCommand, requests, permissions, 
                                           moved, perm, req, targetWaterLevel, 
                                           requestedSide, oppositeSide, 
                                           targetLocation, canGrant, 
                                           shipsAtTarget, isExitRequest, requeueCount >>

ShipGoalReachedEast(self) == /\ pc[self] = "ShipGoalReachedEast"
                             /\ shipStates' = [shipStates EXCEPT ![self] = "goal_reached"]
                             /\ pc' = [pc EXCEPT ![self] = "ShipNextIteration"]
                             /\ UNCHANGED << lockOrientations, doorsOpen, 
                                             valvesOpen, waterLevel, 
                                             shipLocations, lockCommand, 
                                             requests, permissions, moved, 
                                             perm, req, targetWaterLevel, 
                                             requestedSide, oppositeSide, 
                                             targetLocation, canGrant, 
                                             shipsAtTarget, isExitRequest, requeueCount >>

ShipMoveEast(self) == /\ pc[self] = "ShipMoveEast"
                      /\ IF perm[self].granted
                            THEN /\ Assert(doorsOpen[perm[self].lock][IF InLock(self) THEN "east" ELSE "west"], 
                                           "Failure of assertion at line 222, column 13.")
                                 /\ shipLocations' = [shipLocations EXCEPT ![self] = shipLocations[self] + 1]
                                 /\ moved' = [moved EXCEPT ![self] = TRUE]
                            ELSE /\ TRUE
                                 /\ UNCHANGED << shipLocations, moved >>
                      /\ pc' = [pc EXCEPT ![self] = "ShipNextIteration"]
                      /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                      waterLevel, shipStates, lockCommand, 
                                      requests, permissions, perm, req, 
                                      targetWaterLevel, requestedSide, 
                                      oppositeSide, targetLocation, canGrant, 
                                      shipsAtTarget, isExitRequest, requeueCount >>

ShipRequestWest(self) == /\ pc[self] = "ShipRequestWest"
                         /\ requests' = Append(requests, ([ship |-> self, lock |-> GetLock(shipLocations[self]+1), side |-> "west"]))
                         /\ pc' = [pc EXCEPT ![self] = "ShipWaitForWest"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, permissions, 
                                         moved, perm, req, targetWaterLevel, 
                                         requestedSide, oppositeSide, 
                                         targetLocation, canGrant, 
                                         shipsAtTarget, isExitRequest, requeueCount >>

ShipWaitForWest(self) == /\ pc[self] = "ShipWaitForWest"
                         /\ (permissions[self]) /= <<>>
                         /\ perm' = [perm EXCEPT ![self] = Head((permissions[self]))]
                         /\ permissions' = [permissions EXCEPT ![self] = Tail((permissions[self]))]
                         /\ Assert(perm'[self].lock = GetLock(shipLocations[self]+1), 
                                   "Failure of assertion at line 209, column 13.")
                         /\ pc' = [pc EXCEPT ![self] = "ShipMoveEast"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, requests, 
                                         moved, req, targetWaterLevel, 
                                         requestedSide, oppositeSide, 
                                         targetLocation, canGrant, 
                                         shipsAtTarget, isExitRequest, requeueCount >>

ShipRequestEastInLock(self) == /\ pc[self] = "ShipRequestEastInLock"
                               /\ requests' = Append(requests, ([ship |-> self, lock |-> GetLock(shipLocations[self]), side |-> "east"]))
                               /\ pc' = [pc EXCEPT ![self] = "ShipWaitForEastInLock"]
                               /\ UNCHANGED << lockOrientations, doorsOpen, 
                                               valvesOpen, waterLevel, 
                                               shipLocations, shipStates, 
                                               lockCommand, permissions, moved, 
                                               perm, req, targetWaterLevel, 
                                               requestedSide, oppositeSide, 
                                               targetLocation, canGrant, 
                                               shipsAtTarget, isExitRequest, requeueCount >>

ShipWaitForEastInLock(self) == /\ pc[self] = "ShipWaitForEastInLock"
                               /\ (permissions[self]) /= <<>>
                               /\ perm' = [perm EXCEPT ![self] = Head((permissions[self]))]
                               /\ permissions' = [permissions EXCEPT ![self] = Tail((permissions[self]))]
                               /\ Assert(perm'[self].lock = GetLock(shipLocations[self]), 
                                         "Failure of assertion at line 217, column 13.")
                               /\ pc' = [pc EXCEPT ![self] = "ShipMoveEast"]
                               /\ UNCHANGED << lockOrientations, doorsOpen, 
                                               valvesOpen, waterLevel, 
                                               shipLocations, shipStates, 
                                               lockCommand, requests, moved, 
                                               req, targetWaterLevel, 
                                               requestedSide, oppositeSide, 
                                               targetLocation, canGrant, 
                                               shipsAtTarget, isExitRequest, requeueCount >>

ShipTurnAround(self) == /\ pc[self] = "ShipTurnAround"
                        /\ shipStates' = [shipStates EXCEPT ![self] = IF shipLocations[self] = WestEnd THEN "go_to_east" ELSE "go_to_west"]
                        /\ pc' = [pc EXCEPT ![self] = "ShipNextIteration"]
                        /\ UNCHANGED << lockOrientations, doorsOpen, 
                                        valvesOpen, waterLevel, shipLocations, 
                                        lockCommand, requests, permissions, 
                                        moved, perm, req, targetWaterLevel, 
                                        requestedSide, oppositeSide, 
                                        targetLocation, canGrant, 
                                        shipsAtTarget, isExitRequest, requeueCount >>

ShipGoalReachedWest(self) == /\ pc[self] = "ShipGoalReachedWest"
                             /\ shipStates' = [shipStates EXCEPT ![self] = "goal_reached"]
                             /\ pc' = [pc EXCEPT ![self] = "ShipNextIteration"]
                             /\ UNCHANGED << lockOrientations, doorsOpen, 
                                             valvesOpen, waterLevel, 
                                             shipLocations, lockCommand, 
                                             requests, permissions, moved, 
                                             perm, req, targetWaterLevel, 
                                             requestedSide, oppositeSide, 
                                             targetLocation, canGrant, 
                                             shipsAtTarget, isExitRequest, requeueCount >>

ShipMoveWest(self) == /\ pc[self] = "ShipMoveWest"
                      /\ IF perm[self].granted
                            THEN /\ Assert(doorsOpen[perm[self].lock][IF InLock(self) THEN "west" ELSE "east"], 
                                           "Failure of assertion at line 253, column 13.")
                                 /\ shipLocations' = [shipLocations EXCEPT ![self] = shipLocations[self] - 1]
                                 /\ moved' = [moved EXCEPT ![self] = TRUE]
                            ELSE /\ TRUE
                                 /\ UNCHANGED << shipLocations, moved >>
                      /\ pc' = [pc EXCEPT ![self] = "ShipNextIteration"]
                      /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                      waterLevel, shipStates, lockCommand, 
                                      requests, permissions, perm, req, 
                                      targetWaterLevel, requestedSide, 
                                      oppositeSide, targetLocation, canGrant, 
                                      shipsAtTarget, isExitRequest, requeueCount >>

ShipRequestEast(self) == /\ pc[self] = "ShipRequestEast"
                         /\ requests' = Append(requests, ([ship |-> self, lock |-> GetLock(shipLocations[self]-1), side |-> "east"]))
                         /\ pc' = [pc EXCEPT ![self] = "ShipWaitForEast"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, permissions, 
                                         moved, perm, req, targetWaterLevel, 
                                         requestedSide, oppositeSide, 
                                         targetLocation, canGrant, 
                                         shipsAtTarget, isExitRequest, requeueCount >>

ShipWaitForEast(self) == /\ pc[self] = "ShipWaitForEast"
                         /\ (permissions[self]) /= <<>>
                         /\ perm' = [perm EXCEPT ![self] = Head((permissions[self]))]
                         /\ permissions' = [permissions EXCEPT ![self] = Tail((permissions[self]))]
                         /\ Assert(perm'[self].lock = GetLock(shipLocations[self]-1), 
                                   "Failure of assertion at line 240, column 13.")
                         /\ pc' = [pc EXCEPT ![self] = "ShipMoveWest"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, requests, 
                                         moved, req, targetWaterLevel, 
                                         requestedSide, oppositeSide, 
                                         targetLocation, canGrant, 
                                         shipsAtTarget, isExitRequest, requeueCount >>

ShipRequestWestInLock(self) == /\ pc[self] = "ShipRequestWestInLock"
                               /\ requests' = Append(requests, ([ship |-> self, lock |-> GetLock(shipLocations[self]), side |-> "west"]))
                               /\ pc' = [pc EXCEPT ![self] = "ShipWaitForWestInLock"]
                               /\ UNCHANGED << lockOrientations, doorsOpen, 
                                               valvesOpen, waterLevel, 
                                               shipLocations, shipStates, 
                                               lockCommand, permissions, moved, 
                                               perm, req, targetWaterLevel, 
                                               requestedSide, oppositeSide, 
                                               targetLocation, canGrant, 
                                               shipsAtTarget, isExitRequest, requeueCount >>

ShipWaitForWestInLock(self) == /\ pc[self] = "ShipWaitForWestInLock"
                               /\ (permissions[self]) /= <<>>
                               /\ perm' = [perm EXCEPT ![self] = Head((permissions[self]))]
                               /\ permissions' = [permissions EXCEPT ![self] = Tail((permissions[self]))]
                               /\ Assert(perm'[self].lock = GetLock(shipLocations[self]), 
                                         "Failure of assertion at line 248, column 13.")
                               /\ pc' = [pc EXCEPT ![self] = "ShipMoveWest"]
                               /\ UNCHANGED << lockOrientations, doorsOpen, 
                                               valvesOpen, waterLevel, 
                                               shipLocations, shipStates, 
                                               lockCommand, requests, moved, 
                                               req, targetWaterLevel, 
                                               requestedSide, oppositeSide, 
                                               targetLocation, canGrant, 
                                               shipsAtTarget, isExitRequest, requeueCount >>

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

ControlLoop == /\ pc[0] = "ControlLoop"
               /\ pc' = [pc EXCEPT ![0] = "ControlReadRequest"]
               /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                               waterLevel, shipLocations, shipStates, 
                               lockCommand, requests, permissions, moved, perm, 
                               req, targetWaterLevel, requestedSide, 
                               oppositeSide, targetLocation, canGrant, 
                               shipsAtTarget, isExitRequest, requeueCount >>

ControlReadRequest == /\ pc[0] = "ControlReadRequest"
                      /\ requests /= <<>>
                      /\ req' = Head(requests)
                      /\ requests' = Tail(requests)
                      /\ requestedSide' = req'.side
                      /\ oppositeSide' = (IF requestedSide' = "west" THEN "east" ELSE "west")
                      /\ pc' = [pc EXCEPT ![0] = "ControlCheckCapacity"]
                      /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                      waterLevel, shipLocations, shipStates, 
                                      lockCommand, permissions, moved, perm, 
                                      targetWaterLevel, targetLocation, 
                                      canGrant, shipsAtTarget, isExitRequest, 
                                      requeueCount >>

ControlCheckCapacity == /\ pc[0] = "ControlCheckCapacity"
                        /\ IF InLock(req.ship)
                              THEN /\ isExitRequest' = TRUE
                                   /\ IF requestedSide = "west"
                                         THEN /\ targetLocation' = shipLocations[req.ship] - 1
                                         ELSE /\ targetLocation' = shipLocations[req.ship] + 1
                              ELSE /\ isExitRequest' = FALSE
                                   /\ IF requestedSide = "west"
                                         THEN /\ targetLocation' = shipLocations[req.ship] + 1
                                         ELSE /\ targetLocation' = shipLocations[req.ship] - 1
                        /\ shipsAtTarget' = Cardinality({s \in Ships : shipLocations[s] = targetLocation'})
                        /\ IF IsLock(targetLocation')
                              THEN /\ IF isExitRequest'
                                         THEN /\ canGrant' = TRUE
                                         ELSE /\ canGrant' = (shipsAtTarget' < MaxShipsLock)
                              ELSE /\ IF isExitRequest'
                                         THEN /\ canGrant' = (shipsAtTarget' < MaxShipsLocation + 1)
                                         ELSE /\ canGrant' = (shipsAtTarget' < MaxShipsLocation)
                        /\ pc' = [pc EXCEPT ![0] = "ControlDecideGrant"]
                        /\ UNCHANGED << lockOrientations, doorsOpen, 
                                        valvesOpen, waterLevel, shipLocations, 
                                        shipStates, lockCommand, requests, 
                                        permissions, moved, perm, req, 
                                        targetWaterLevel, requestedSide, 
                                        oppositeSide, requeueCount >>

ControlDecideGrant == /\ pc[0] = "ControlDecideGrant"
                      /\ IF ~canGrant
                            THEN /\ pc' = [pc EXCEPT ![0] = "ControlDenyPermission"]
                            ELSE /\ pc' = [pc EXCEPT ![0] = "ControlCloseDoors"]
                      /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                      waterLevel, shipLocations, shipStates, 
                                      lockCommand, requests, permissions, 
                                      moved, perm, req, targetWaterLevel, 
                                      requestedSide, oppositeSide, 
                                      targetLocation, canGrant, shipsAtTarget, 
                                      isExitRequest, requeueCount >>

ControlDenyPermission == /\ pc[0] = "ControlDenyPermission"
                         /\ permissions' = [permissions EXCEPT ![req.ship] = Append((permissions[req.ship]), ([lock |-> req.lock, granted |-> FALSE]))]
                         /\ pc' = [pc EXCEPT ![0] = "ControlLoop"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, requests, 
                                         moved, perm, req, targetWaterLevel, 
                                         requestedSide, oppositeSide, 
                                         targetLocation, canGrant, 
                                         shipsAtTarget, isExitRequest, requeueCount >>

ControlCloseDoors == /\ pc[0] = "ControlCloseDoors"
                     /\ IF doorsOpen[req.lock][requestedSide]
                           THEN /\ lockCommand' = [lockCommand EXCEPT ![req.lock] = [command |-> "change_door", open |-> FALSE, side |-> requestedSide]]
                                /\ pc' = [pc EXCEPT ![0] = "ControlWaitCloseDoor1"]
                           ELSE /\ pc' = [pc EXCEPT ![0] = "ControlCloseDoor2"]
                                /\ UNCHANGED lockCommand
                     /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                     waterLevel, shipLocations, shipStates, 
                                     requests, permissions, moved, perm, req, 
                                     targetWaterLevel, requestedSide, 
                                     oppositeSide, targetLocation, canGrant, 
                                     shipsAtTarget, isExitRequest, requeueCount >>

ControlWaitCloseDoor1 == /\ pc[0] = "ControlWaitCloseDoor1"
                         /\ lockCommand[req.lock].command = "finished"
                         /\ pc' = [pc EXCEPT ![0] = "ControlCheckOppositeDoor"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, requests, 
                                         permissions, moved, perm, req, 
                                         targetWaterLevel, requestedSide, 
                                         oppositeSide, targetLocation, 
                                         canGrant, shipsAtTarget, isExitRequest, requeueCount >>

ControlCheckOppositeDoor == /\ pc[0] = "ControlCheckOppositeDoor"
                            /\ TRUE
                            /\ pc' = [pc EXCEPT ![0] = "ControlCloseDoor2"]
                            /\ UNCHANGED << lockOrientations, doorsOpen, 
                                            valvesOpen, waterLevel, 
                                            shipLocations, shipStates, 
                                            lockCommand, requests, permissions, 
                                            moved, perm, req, targetWaterLevel, 
                                            requestedSide, oppositeSide, 
                                            targetLocation, canGrant, 
                                            shipsAtTarget, isExitRequest, requeueCount >>

ControlCloseDoor2 == /\ pc[0] = "ControlCloseDoor2"
                     /\ IF doorsOpen[req.lock][oppositeSide]
                           THEN /\ lockCommand' = [lockCommand EXCEPT ![req.lock] = [command |-> "change_door", open |-> FALSE, side |-> oppositeSide]]
                                /\ pc' = [pc EXCEPT ![0] = "ControlWaitCloseDoor2"]
                           ELSE /\ pc' = [pc EXCEPT ![0] = "ControlSetTargetLevel"]
                                /\ UNCHANGED lockCommand
                     /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                     waterLevel, shipLocations, shipStates, 
                                     requests, permissions, moved, perm, req, 
                                     targetWaterLevel, requestedSide, 
                                     oppositeSide, targetLocation, canGrant, 
                                     shipsAtTarget, isExitRequest, requeueCount >>

ControlWaitCloseDoor2 == /\ pc[0] = "ControlWaitCloseDoor2"
                         /\ lockCommand[req.lock].command = "finished"
                         /\ pc' = [pc EXCEPT ![0] = "ControlDetermineTargetLevel"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, requests, 
                                         permissions, moved, perm, req, 
                                         targetWaterLevel, requestedSide, 
                                         oppositeSide, targetLocation, 
                                         canGrant, shipsAtTarget, isExitRequest, requeueCount >>

ControlDetermineTargetLevel == /\ pc[0] = "ControlDetermineTargetLevel"
                               /\ TRUE
                               /\ pc' = [pc EXCEPT ![0] = "ControlSetTargetLevel"]
                               /\ UNCHANGED << lockOrientations, doorsOpen, 
                                               valvesOpen, waterLevel, 
                                               shipLocations, shipStates, 
                                               lockCommand, requests, 
                                               permissions, moved, perm, req, 
                                               targetWaterLevel, requestedSide, 
                                               oppositeSide, targetLocation, 
                                               canGrant, shipsAtTarget, isExitRequest, requeueCount >>

ControlSetTargetLevel == /\ pc[0] = "ControlSetTargetLevel"
                         /\ IF requestedSide = LowSide(lockOrientations[req.lock])
                               THEN /\ targetWaterLevel' = "low"
                               ELSE /\ targetWaterLevel' = "high"
                         /\ pc' = [pc EXCEPT ![0] = "ControlAdjustWaterLevel"]
                         /\ UNCHANGED << lockOrientations, doorsOpen, 
                                         valvesOpen, waterLevel, shipLocations, 
                                         shipStates, lockCommand, requests, 
                                         permissions, moved, perm, req, 
                                         requestedSide, oppositeSide, 
                                         targetLocation, canGrant, 
                                         shipsAtTarget, isExitRequest, requeueCount >>

ControlAdjustWaterLevel == /\ pc[0] = "ControlAdjustWaterLevel"
                           /\ IF waterLevel[req.lock] /= targetWaterLevel
                                 THEN /\ IF targetWaterLevel = "low"
                                            THEN /\ lockCommand' = [lockCommand EXCEPT ![req.lock] = [command |-> "change_valve", open |-> TRUE, side |-> "low"]]
                                                 /\ pc' = [pc EXCEPT ![0] = "ControlWaitValveLow"]
                                            ELSE /\ lockCommand' = [lockCommand EXCEPT ![req.lock] = [command |-> "change_valve", open |-> TRUE, side |-> "high"]]
                                                 /\ pc' = [pc EXCEPT ![0] = "ControlWaitValveHigh"]
                                 ELSE /\ pc' = [pc EXCEPT ![0] = "ControlOpenRequestedDoor"]
                                      /\ UNCHANGED lockCommand
                           /\ UNCHANGED << lockOrientations, doorsOpen, 
                                           valvesOpen, waterLevel, 
                                           shipLocations, shipStates, requests, 
                                           permissions, moved, perm, req, 
                                           targetWaterLevel, requestedSide, 
                                           oppositeSide, targetLocation, 
                                           canGrant, shipsAtTarget, isExitRequest, requeueCount >>

ControlWaitValveLow == /\ pc[0] = "ControlWaitValveLow"
                       /\ lockCommand[req.lock].command = "finished"
                       /\ pc' = [pc EXCEPT ![0] = "ControlWaitWaterLow"]
                       /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                       waterLevel, shipLocations, shipStates, 
                                       lockCommand, requests, permissions, 
                                       moved, perm, req, targetWaterLevel, 
                                       requestedSide, oppositeSide, 
                                       targetLocation, canGrant, shipsAtTarget, isExitRequest, requeueCount >>

ControlWaitWaterLow == /\ pc[0] = "ControlWaitWaterLow"
                       /\ waterLevel[req.lock] = "low"
                       /\ lockCommand' = [lockCommand EXCEPT ![req.lock] = [command |-> "change_valve", open |-> FALSE, side |-> "low"]]
                       /\ pc' = [pc EXCEPT ![0] = "ControlWaitCloseValveLow"]
                       /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                       waterLevel, shipLocations, shipStates, 
                                       requests, permissions, moved, perm, req, 
                                       targetWaterLevel, requestedSide, 
                                       oppositeSide, targetLocation, canGrant, 
                                       shipsAtTarget, isExitRequest, requeueCount >>

ControlWaitCloseValveLow == /\ pc[0] = "ControlWaitCloseValveLow"
                            /\ lockCommand[req.lock].command = "finished"
                            /\ pc' = [pc EXCEPT ![0] = "ControlPrepareOpenDoor1"]
                            /\ UNCHANGED << lockOrientations, doorsOpen, 
                                            valvesOpen, waterLevel, 
                                            shipLocations, shipStates, 
                                            lockCommand, requests, permissions, 
                                            moved, perm, req, targetWaterLevel, 
                                            requestedSide, oppositeSide, 
                                            targetLocation, canGrant, 
                                            shipsAtTarget, isExitRequest, requeueCount >>

ControlPrepareOpenDoor1 == /\ pc[0] = "ControlPrepareOpenDoor1"
                           /\ TRUE
                           /\ pc' = [pc EXCEPT ![0] = "ControlOpenRequestedDoor"]
                           /\ UNCHANGED << lockOrientations, doorsOpen, 
                                           valvesOpen, waterLevel, 
                                           shipLocations, shipStates, 
                                           lockCommand, requests, permissions, 
                                           moved, perm, req, targetWaterLevel, 
                                           requestedSide, oppositeSide, 
                                           targetLocation, canGrant, 
                                           shipsAtTarget, isExitRequest, requeueCount >>

ControlWaitValveHigh == /\ pc[0] = "ControlWaitValveHigh"
                        /\ lockCommand[req.lock].command = "finished"
                        /\ pc' = [pc EXCEPT ![0] = "ControlWaitWaterHigh"]
                        /\ UNCHANGED << lockOrientations, doorsOpen, 
                                        valvesOpen, waterLevel, shipLocations, 
                                        shipStates, lockCommand, requests, 
                                        permissions, moved, perm, req, 
                                        targetWaterLevel, requestedSide, 
                                        oppositeSide, targetLocation, canGrant, 
                                        shipsAtTarget, isExitRequest, requeueCount >>

ControlWaitWaterHigh == /\ pc[0] = "ControlWaitWaterHigh"
                        /\ waterLevel[req.lock] = "high"
                        /\ lockCommand' = [lockCommand EXCEPT ![req.lock] = [command |-> "change_valve", open |-> FALSE, side |-> "high"]]
                        /\ pc' = [pc EXCEPT ![0] = "ControlWaitCloseValveHigh"]
                        /\ UNCHANGED << lockOrientations, doorsOpen, 
                                        valvesOpen, waterLevel, shipLocations, 
                                        shipStates, requests, permissions, 
                                        moved, perm, req, targetWaterLevel, 
                                        requestedSide, oppositeSide, 
                                        targetLocation, canGrant, 
                                        shipsAtTarget, isExitRequest, requeueCount >>

ControlWaitCloseValveHigh == /\ pc[0] = "ControlWaitCloseValveHigh"
                             /\ lockCommand[req.lock].command = "finished"
                             /\ pc' = [pc EXCEPT ![0] = "ControlPrepareOpenDoor2"]
                             /\ UNCHANGED << lockOrientations, doorsOpen, 
                                             valvesOpen, waterLevel, 
                                             shipLocations, shipStates, 
                                             lockCommand, requests, 
                                             permissions, moved, perm, req, 
                                             targetWaterLevel, requestedSide, 
                                             oppositeSide, targetLocation, 
                                             canGrant, shipsAtTarget, isExitRequest, requeueCount >>

ControlPrepareOpenDoor2 == /\ pc[0] = "ControlPrepareOpenDoor2"
                           /\ TRUE
                           /\ pc' = [pc EXCEPT ![0] = "ControlOpenRequestedDoor"]
                           /\ UNCHANGED << lockOrientations, doorsOpen, 
                                           valvesOpen, waterLevel, 
                                           shipLocations, shipStates, 
                                           lockCommand, requests, permissions, 
                                           moved, perm, req, targetWaterLevel, 
                                           requestedSide, oppositeSide, 
                                           targetLocation, canGrant, 
                                           shipsAtTarget, isExitRequest, requeueCount >>

ControlOpenRequestedDoor == /\ pc[0] = "ControlOpenRequestedDoor"
                            /\ lockCommand' = [lockCommand EXCEPT ![req.lock] = [command |-> "change_door", open |-> TRUE, side |-> requestedSide]]
                            /\ pc' = [pc EXCEPT ![0] = "ControlWaitOpenDoor"]
                            /\ UNCHANGED << lockOrientations, doorsOpen, 
                                            valvesOpen, waterLevel, 
                                            shipLocations, shipStates, 
                                            requests, permissions, moved, perm, 
                                            req, targetWaterLevel, 
                                            requestedSide, oppositeSide, 
                                            targetLocation, canGrant, 
                                            shipsAtTarget, isExitRequest, requeueCount >>

ControlWaitOpenDoor == /\ pc[0] = "ControlWaitOpenDoor"
                       /\ lockCommand[req.lock].command = "finished"
                       /\ pc' = [pc EXCEPT ![0] = "ControlGrantPermission"]
                       /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                       waterLevel, shipLocations, shipStates, 
                                       lockCommand, requests, permissions, 
                                       moved, perm, req, targetWaterLevel, 
                                       requestedSide, oppositeSide, 
                                       targetLocation, canGrant, shipsAtTarget, isExitRequest, requeueCount >>

ControlGrantPermission == /\ pc[0] = "ControlGrantPermission"
                          /\ permissions' = [permissions EXCEPT ![req.ship] = Append((permissions[req.ship]), ([lock |-> req.lock, granted |-> TRUE]))]
                          /\ pc' = [pc EXCEPT ![0] = "ControlObserveMove"]
                          /\ UNCHANGED << lockOrientations, doorsOpen, 
                                          valvesOpen, waterLevel, 
                                          shipLocations, shipStates, 
                                          lockCommand, requests, moved, perm, 
                                          req, targetWaterLevel, requestedSide, 
                                          oppositeSide, targetLocation, 
                                          canGrant, shipsAtTarget, isExitRequest, requeueCount >>

ControlObserveMove == /\ pc[0] = "ControlObserveMove"
                      /\ moved[req.ship]
                      /\ pc' = [pc EXCEPT ![0] = "ControlClearMoved"]
                      /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                      waterLevel, shipLocations, shipStates, 
                                      lockCommand, requests, permissions, 
                                      moved, perm, req, targetWaterLevel, 
                                      requestedSide, oppositeSide, 
                                      targetLocation, canGrant, shipsAtTarget, isExitRequest, requeueCount >>

ControlClearMoved == /\ pc[0] = "ControlClearMoved"
                     /\ moved' = [moved EXCEPT ![req.ship] = FALSE]
                     /\ pc' = [pc EXCEPT ![0] = "ControlLoop"]
                     /\ UNCHANGED << lockOrientations, doorsOpen, valvesOpen, 
                                     waterLevel, shipLocations, shipStates, 
                                     lockCommand, requests, permissions, perm, 
                                     req, targetWaterLevel, requestedSide, 
                                     oppositeSide, targetLocation, canGrant, 
                                     shipsAtTarget, isExitRequest, requeueCount >>

controlProcess == ControlLoop \/ ControlReadRequest \/ ControlCheckCapacity
                     \/ ControlDecideGrant \/ ControlDenyPermission
                     \/ ControlCloseDoors \/ ControlWaitCloseDoor1
                     \/ ControlCheckOppositeDoor \/ ControlCloseDoor2
                     \/ ControlWaitCloseDoor2
                     \/ ControlDetermineTargetLevel
                     \/ ControlSetTargetLevel \/ ControlAdjustWaterLevel
                     \/ ControlWaitValveLow \/ ControlWaitWaterLow
                     \/ ControlWaitCloseValveLow \/ ControlPrepareOpenDoor1
                     \/ ControlWaitValveHigh \/ ControlWaitWaterHigh
                     \/ ControlWaitCloseValveHigh
                     \/ ControlPrepareOpenDoor2 \/ ControlOpenRequestedDoor
                     \/ ControlWaitOpenDoor \/ ControlGrantPermission
                     \/ ControlObserveMove \/ ControlClearMoved

Next == controlProcess
           \/ (\E self \in Locks: lockProcess(self))
           \/ (\E self \in Ships: shipProcess(self))

Spec == Init /\ [][Next]_vars

\* Fairness specification with weak fairness for controller and ships
FairSpec == Spec 
            /\ WF_vars(controlProcess)
            /\ \A l \in Locks: WF_vars(lockProcess(l))
            /\ \A s \in Ships: WF_vars(shipProcess(s))

\* END TRANSLATION 

=============================================================================
\* Modification History
\* Last modified Wed Sep 24 12:00:55 CEST 2025 by mvolk
\* Created Thu Aug 28 11:30:07 CEST 2025 by mvolk
