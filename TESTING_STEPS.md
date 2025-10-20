# Steps to Test Retry Limit Implementation

## Prerequisites
- TLA+ Toolbox version 1.7.4 installed
- Modified files: `lock_data.tla`, `lock_multiple.tla`, `lock_multiple.cfg`

## Step 1: Translate PlusCal to TLA+

1. Open TLA+ Toolbox
2. Open the LockSystem project
3. Open `lock_multiple.tla` in the Toolbox
4. Go to **File → Translate PlusCal Algorithm** (or press Ctrl+T / Cmd+T)
5. The Toolbox will update the `\* BEGIN TRANSLATION` section
6. Save the file

**Important**: The PlusCal algorithm block `(* --algorithm lock_system ... end algorithm; *)` contains our modifications. The Toolbox will regenerate the TLA+ translation below the `BEGIN TRANSLATION` comment.

## Step 2: Create/Update Model Configuration

### For 2 locks, 2 ships (current config):

File: `lock_multiple.cfg`

```tla
SPECIFICATION FairSpec

CONSTANTS
    NumLocks = 2
    NumShips = 2
    MaxShipsLocation = 2
    MaxShipsLock = 1
    MaxRetries = 3

INVARIANTS
  TypeOK
  MessagesOK
  DoorsMutex
  DoorsOpenValvesClosed
  DoorsOpenWaterlevelRight
  MaxShipsPerLocation

PROPERTIES
  RequestLockFulfilled
  WaterlevelChange
  RequestsShips
  ShipsReachGoals
```

**Check**: Deadlock detection should be enabled in Toolbox

## Step 3: Run Model Checking

### Test 1: 2 Locks, 2 Ships
1. In Toolbox, select the model configuration (or create new model from `lock_multiple.cfg`)
2. Set constants as above
3. Enable "Deadlock" checking under "What to check?"
4. Click "Run TLC" button
5. Wait for verification to complete
6. Note: States explored, time taken, any violations

**Expected**: All invariants pass, all properties satisfied, no deadlock

### Test 2: 3 Locks, 2 Ships
1. Update constants:
   ```
   NumLocks = 3
   NumShips = 2
   MaxShipsLocation = 2
   MaxShipsLock = 1
   MaxRetries = 3
   ```
2. Run TLC
3. Document results

### Test 3: 4 Locks, 2 Ships
1. Update constants:
   ```
   NumLocks = 4
   NumShips = 2
   MaxShipsLocation = 2
   MaxShipsLock = 1
   MaxRetries = 3
   ```
2. Run TLC
3. Document results

## Step 4: Analyze Results

For each test configuration, record:
- **States explored**: Total number of distinct states
- **Distinct states**: Unique states found
- **Time taken**: Duration of verification
- **Invariants**: PASS/FAIL for each
  - TypeOK
  - MessagesOK
  - DoorsMutex
  - DoorsOpenValvesClosed
  - DoorsOpenWaterlevelRight
  - MaxShipsPerLocation
- **Properties**: PASS/FAIL for each
  - RequestLockFulfilled
  - WaterlevelChange
  - RequestsShips
  - ShipsReachGoals
- **Deadlock**: Detected? (should be NO)
- **Counterexamples**: If any violations found, document the trace

## Step 5: Document Results

Update `reports/multiple_model_results.md` with:

```markdown
# Multiple Lock Model Verification Results
Date: October 16, 2025
Configuration: lock_multiple.cfg with Retry Limit Implementation

## Implementation Details
- **MaxRetries**: 3 consecutive retries before blocking
- **Retry behavior**: Denied requests are re-queued up to MaxRetries times
- **Blocking behavior**: After MaxRetries, controller awaits capacity availability

## Test Configuration 1: 2 Locks, 2 Ships
### Constants
- NumLocks = 2
- NumShips = 2
- MaxShipsLocation = 2
- MaxShipsLock = 1
- MaxRetries = 3

### Invariants
- TypeOK: [PASS/FAIL]
- MessagesOK: [PASS/FAIL]
- DoorsMutex: [PASS/FAIL]
- DoorsOpenValvesClosed: [PASS/FAIL]
- DoorsOpenWaterlevelRight: [PASS/FAIL]
- MaxShipsPerLocation: [PASS/FAIL]

### Liveness Properties
- RequestLockFulfilled: [PASS/FAIL]
- WaterlevelChange: [PASS/FAIL]
- RequestsShips: [PASS/FAIL]
- ShipsReachGoals: [PASS/FAIL]

### Results
- States explored: [NUMBER]
- Distinct states: [NUMBER]
- Time taken: [DURATION]
- Deadlock: [YES/NO]

[... similar sections for 3 locks and 4 locks ...]
```

## Step 6: Compare with Previous Results

Compare the new results with previous verification runs (if any) to see:
- Reduction in state space due to bounded retries
- Impact on verification time
- Any new issues introduced

## Troubleshooting

### If deadlock is detected:
- Examine the error trace in Toolbox
- Check if ships are blocking unnecessarily
- Consider adjusting MaxRetries value
- Verify that exit requests are properly prioritized

### If liveness properties fail:
- Check fairness assumptions in FairSpec
- Ensure WF (weak fairness) on controlProcess
- May need SF (strong fairness) on specific actions
- Verify that blocking doesn't prevent eventual progress

### If invariants fail:
- Check TypeOK: Ensure retryCount type is correct in translation
- Check MessagesOK: Verify requests queue bound is appropriate
- Review the error trace to understand the violation

## Notes

1. **State Space**: With MaxRetries=3, the state space should be bounded more tightly than unlimited retries
2. **Fairness**: The FairSpec should include weak fairness for all processes to ensure liveness
3. **Blocking**: The await in ControlDecideGrantOrRetry introduces blocking, which is acceptable after MaxRetries attempts
4. **Reset Logic**: retryCount is reset to 0 upon successful grant OR after blocking completes
