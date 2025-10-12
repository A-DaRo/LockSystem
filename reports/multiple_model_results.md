## Multiple model results — YYYY-MM-DD — model_multiple/MC.cfg

- Constants: NumLocks=?, NumShips=?, MaxShipsLocation=?, MaxShipsLock=?
- Deadlock: PASS/FAIL
- Invariants:
  - TypeOK: PASS/FAIL
  - MessagesOK: PASS/FAIL
  - DoorsMutex (∀ l): PASS/FAIL
  - DoorsOpenValvesClosed (∀ l): PASS/FAIL
  - DoorsOpenWaterlevelRight (∀ l): PASS/FAIL
  - MaxShipsPerLocation (∀ locations): PASS/FAIL
- Liveness (fairness: None/WF/SF):
  - RequestLockFulfilled (∀ ships): PASS/FAIL (fairness used: ...)
  - WaterLevelChange (∀ locks): PASS/FAIL (fairness used: ...)
  - RequestsShips (∀ ships): PASS/FAIL (fairness used: ...)
  - ShipsReachGoals (∀ ships): PASS/FAIL (fairness used: ...)
- States explored / time: ... / ...
- Counterexample summary (if any):
  - Property: ...
  - Trace notes: ...
