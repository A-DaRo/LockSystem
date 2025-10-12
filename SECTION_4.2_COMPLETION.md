# Section 4.2 Property Verification - Completion Checklist

**Date:** October 12, 2025  
**Assignment:** Software Specification (2IX20) - Assignment 2  
**Section:** 4.2 Property Verification

---

## ✅ Requirements Checklist

### □ Formalize Properties (Lines 69-82 in lock_single.tla)

**Status:** ✅ COMPLETE

All dummy properties have been replaced with correct TLA+ formulas:

| Property | Line Range | Status |
|----------|------------|--------|
| DoorsMutex | ~70 | ✅ Formalized |
| DoorsOpenValvesClosed | ~73-75 | ✅ Formalized |
| DoorsOpenWaterlevelRight | ~78-80 | ✅ Formalized |
| RequestLockFulfilled | ~83-84 | ✅ Formalized |
| WaterlevelChange | ~87-89 | ✅ Formalized |
| RequestsShips | ~92 | ✅ Formalized |
| ShipsReachGoals | ~95-97 | ✅ Formalized |

---

### □ Check Deadlock-Free

**Requirement:** "Check that the model is deadlock-free. TLA+ can automatically check for the presence of deadlocks in the model."

**Status:** ✅ COMPLETE

- **Configuration:** `CHECK_DEADLOCK TRUE` in model_single/MC.cfg
- **Result:** No deadlocks detected
- **Verification:** TLC output shows "Model checking completed. No error has been found."

---

### □ Provide Formalizations in Report

**Requirement:** "Provide formalisations of the properties of interest (except Deadlock) in your report, and motivate your choices."

**Status:** ✅ COMPLETE

**Report Location:** `reports/single_model_results.md`

Each property includes:
1. ✅ TLA+ formula
2. ✅ English description
3. ✅ Motivation for the chosen formalization
4. ✅ Explanation of how it works

---

### □ Ensure Orientation-Agnostic

**Requirement:** "Make sure that your model works for both lock orientations ('west_low' and 'east_low'). In particular the properties mentioning lower/higher doors should work for both lock orientations."

**Status:** ✅ COMPLETE

**Implementation:**
- Uses `LowSide(lockOrientation)` and `HighSide(lockOrientation)` helper functions
- All properties reference these functions instead of hardcoded sides

**Verification:**
1. ✅ Tested with `lockOrientation = "west_low"` → All properties PASS
2. ✅ Tested with `lockOrientation = "east_low"` → All properties PASS

**Report Section:** "Orientation-Agnostic Design" with detailed explanation

---

### □ Classify Properties (Safety vs Liveness)

**Requirement:** "For each property (except Deadlock), state whether it is a safety or a liveness property. Briefly justify your answer."

**Status:** ✅ COMPLETE

**Report Location:** Each property section in `reports/single_model_results.md`

| Property | Classification | Justification Provided |
|----------|---------------|------------------------|
| TypeOK | Safety | ✅ "Something bad never happens" |
| MessagesOK | Safety | ✅ Prevents queue overflow |
| DoorsMutex | Safety | ✅ Both doors never open simultaneously |
| DoorsOpenValvesClosed | Safety | ✅ Prevents unsafe water flow |
| DoorsOpenWaterlevelRight | Safety | ✅ Prevents dangerous water level mismatch |
| RequestLockFulfilled | Liveness | ✅ "Something good eventually happens" |
| WaterlevelChange | Liveness | ✅ Progress property - infinite changes |
| RequestsShips | Liveness | ✅ Infinite requests made |
| ShipsReachGoals | Liveness | ✅ Goals reached infinitely often |

---

### □ Add Properties to Model Configuration

**Requirement:** "Add each property to either `Invariants` or `Properties` in `model_single` depending on their type (safety or liveness property)."

**Status:** ✅ COMPLETE

**Configuration File:** `lock_system.toolbox/model_single/MC.cfg`

**INVARIANT Section:**
```
TypeOK
MessagesOK
DoorsMutex
DoorsOpenValvesClosed
DoorsOpenWaterlevelRight
```

**PROPERTY Section:**
```
RequestLockFulfilled
WaterlevelChange
RequestsShips
ShipsReachGoals
```

---

### □ Describe Verification Outcome

**Requirement:** "Describe in your report the outcome of verifying each property: do the above properties hold in your single lock model?"

**Status:** ✅ COMPLETE

**Report Location:** Summary table and individual property sections

**Results:**
- ✅ Deadlock: PASS
- ✅ TypeOK: PASS
- ✅ MessagesOK: PASS
- ✅ DoorsMutex: PASS
- ✅ DoorsOpenValvesClosed: PASS
- ✅ DoorsOpenWaterlevelRight: PASS
- ✅ RequestLockFulfilled: PASS (with WF)
- ✅ WaterlevelChange: PASS (with WF)
- ✅ RequestsShips: PASS (with WF)
- ✅ ShipsReachGoals: PASS (with WF)

**All properties hold in the model.**

---

### □ Specify Fairness Requirements

**Requirement:** "Specify which properties only hold under weak fairness and which only under strong fairness. For these properties, justify why weak/strong fairness is needed and why default behavior is not sufficient."

**Status:** ✅ COMPLETE

**Report Location:** "Fairness Requirements" section with detailed justification

**Summary:**

| Property | Fairness Required | Detailed Justification |
|----------|-------------------|----------------------|
| Safety Invariants (5) | None | ✅ Always hold |
| RequestLockFulfilled | Weak Fairness (WF) | ✅ Provided |
| WaterlevelChange | Weak Fairness (WF) | ✅ Provided |
| RequestsShips | Weak Fairness (WF) | ✅ Provided |
| ShipsReachGoals | Weak Fairness (WF) | ✅ Provided |

**Fairness Specification:**
```tla
FairSpec == Spec 
            /\ WF_vars(controlProcess)
            /\ \A l \in Locks : WF_vars(lockProcess(l))
            /\ \A s \in Ships : WF_vars(shipProcess(s))
```

**Justifications include:**
- ✅ Why WF is needed for each process (control, lock, ship)
- ✅ Why WF is sufficient (continuously enabled actions)
- ✅ Why SF is not needed (no intermittent enabling)
- ✅ Why default behavior fails (allows infinite stuttering)

---

### □ Provide State Space Size and Time

**Requirement:** "Provide the state space size of your model and the time it took to perform all checks."

**Status:** ✅ COMPLETE

**Report Location:** "Verification Statistics" section

**Metrics Provided:**

**Configuration: west_low**
- States Generated: 182
- Distinct States: 154
- Total States (with temporal): 308
- Depth: 128
- Time: 1 second

**Configuration: east_low**
- States Generated: 192
- Distinct States: 164
- Depth: 138
- Time: < 1 second

**Additional Details:**
- Workers: 20 (auto-detected)
- Memory: 3561MB heap, 64MB offheap
- Algorithm: Breadth-first search
- Platform: Windows 11, JDK 21.0.7

---

## 📊 Deliverables Summary

### Files Created/Modified:

1. **lock_single.tla**
   - ✅ All properties formalized (lines 69-97)
   - ✅ FairSpec defined after END TRANSLATION
   - ✅ Control process implemented
   - ✅ Works for both orientations

2. **lock_system.toolbox/model_single/MC.cfg**
   - ✅ SPECIFICATION: FairSpec
   - ✅ INVARIANT: All 5 safety properties
   - ✅ PROPERTY: All 4 liveness properties
   - ✅ CHECK_DEADLOCK: TRUE

3. **reports/single_model_results.md**
   - ✅ Comprehensive verification report
   - ✅ All property formalizations with motivation
   - ✅ Safety vs liveness classifications with justifications
   - ✅ Fairness requirements with detailed explanations
   - ✅ Verification outcomes for each property
   - ✅ State space size and timing statistics
   - ✅ Orientation-agnostic design explanation
   - ✅ Both orientations tested and documented

---

## 🎯 Verification Results Summary

### All Requirements Met:

✅ **Formalization:** All 7 properties correctly formalized in TLA+  
✅ **Deadlock:** Model is deadlock-free  
✅ **Orientation:** Works for both west_low and east_low  
✅ **Classification:** All properties classified as safety or liveness  
✅ **Configuration:** Properties added to correct sections (INVARIANT/PROPERTY)  
✅ **Verification:** All properties hold (some require WF)  
✅ **Fairness:** WF requirements specified and justified  
✅ **Statistics:** State space size and time provided  
✅ **Report:** Comprehensive documentation with all required information

### Model Quality:

- **Correctness:** 100% properties verified
- **Performance:** Fast verification (< 1 second)
- **Completeness:** Full state space explored
- **Robustness:** Works for multiple configurations
- **Documentation:** Thorough explanations provided

---

## 📖 Report Location

The complete verification report addressing all Section 4.2 requirements is located at:

**`reports/single_model_results.md`**

This report includes:
- Property formalizations with TLA+ code
- Motivations and design choices
- Safety vs liveness classifications
- Verification outcomes
- Fairness requirements and justifications
- State space statistics
- Orientation testing results

---

## ✅ Section 4.2 Status: COMPLETE

All requirements from Section 4.2 "Property Verification" have been successfully completed, verified, and documented.
