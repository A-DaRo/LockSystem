# Bonus Question - Current Status Assessment
**Date:** October 20, 2025  
**Evaluated by:** GitHub Copilot

---

## 📋 Summary: What is the Bonus Question?

The bonus question asks you to:

1. **Identify** the minimal configuration (NumLocks, NumShips) that leads to deadlock
2. **Provide** a counterexample (trace) explaining why deadlock occurs
3. **Formalize** a property: "NOT all ships can reach `goal_reached`"
4. **Verify** this property with TLC (without fairness)
5. **Analyze** what TLC reports (should find property FALSE = counterexample exists)
6. **Explain** how the counterexample demonstrates a deadlock-avoiding schedule
7. **Report** the length of the counterexample in steps

---

## ✅ Current Progress: ANALYSIS COMPLETE

### What Has Been Done:

#### 1. ✅ Minimal Deadlock Configuration Identified
**Configuration:**
- NumLocks = 3
- NumShips = 2
- MaxShipsLocation = 2
- MaxShipsLock = 1

**Source:** `reports/BONUS_QUESTION_ANALYSIS.md` and `reports/fairness_results.md`

#### 2. ✅ Deadlock Counterexample Provided
**Documented in:** `reports/fairness_results.md` and `reports/BONUS_QUESTION_ANALYSIS.md`

**Problem Scenario:**
```
Ship 4 at location 2 (inside Lock 2, low side)
Ship 5 at location 3 (inside Lock 2, high side)
→ Both ships stuck in Lock 2 (violates MaxShipsLock=1)
→ Controller perpetually denies all requests
```

#### 3. ✅ Property Formalized
**Property:**
```tla
AllShipsCannotReachGoal == ~(\A s \in Ships: shipStates[s] = "goal_reached")
```

**Semantics:** "It is NOT the case that all ships reach goal_reached status"

**Documented in:** `reports/BONUS_QUESTION_ANALYSIS.md` lines 15-20

#### 4. ✅ Property Verified
**Result:** Property VIOLATED (TLC found it FALSE) ✅

**Verification Statistics:**
- Total states generated: 66,341
- Distinct states: 35,018
- Counterexample length: **358 states**
- Verification time: 1 second

**Documented in:** `reports/BONUS_QUESTION_ANALYSIS.md` lines 60-83

#### 5. ✅ Counterexample Analysis Completed
**Final State (State 358):**
```tla
shipStates = (4 :> "goal_reached" @@ 5 :> "goal_reached")
shipLocations = (4 :> 6 @@ 5 :> 0)
```

**Interpretation:** Both ships successfully reached their goals!

**Documented in:** `reports/BONUS_QUESTION_ANALYSIS.md` lines 87-275 and `reports/bonus_question_summary.md`

#### 6. ✅ Explanation Provided
**Why Deadlock is Avoided:**
1. Sequential lock usage (ships don't enter same lock simultaneously)
2. Optimal request ordering by controller
3. Strategic timing of requests (no fairness constraints)
4. Movement synchronization via `moved[s]` variable

**Documented in:** `reports/BONUS_QUESTION_ANALYSIS.md` lines 119-195

#### 7. ✅ Schedule Length Reported
**Answer:** **358 states**

**Explanation:** Very long because:
- Fine-grained interleaving (each action = 1 state)
- Multiple lock traversals (3 locks per ship = ~150 states each)
- Safe coordination (many synchronization points)

**Documented in:** `reports/BONUS_QUESTION_ANALYSIS.md` lines 106-118 and `reports/bonus_question_summary.md` lines 55-80

---

## ⚠️ What Needs to Be Done: IMPLEMENTATION

### Missing: Property in lock_multiple.tla

**Current Status:** 
- ❌ Property `AllShipsCannotReachGoal` is NOT in `lock_multiple.tla`
- ❌ Cannot currently run the bonus question verification
- ✅ Analysis documents exist (from previous work)

**What to Add:**

```tla
\* In lock_multiple.tla, in the "define" section after other properties:

\* BONUS QUESTION: Property to find deadlock-avoiding schedule
\* This property states "NOT all ships can reach goal_reached"
\* When TLC finds this FALSE, the counterexample shows a schedule where all ships DO reach their goal!
AllShipsCannotReachGoal == ~(\A s \in Ships: shipStates[s] = "goal_reached")
```

### Missing: Configuration File for Bonus Question

**What to Create:**

A new `.cfg` file (e.g., `lock_bonus.cfg`) with:
```properties
SPECIFICATION Spec  \* Important: WITHOUT fairness!

CONSTANTS
    NumLocks = 3
    NumShips = 2
    MaxShipsLocation = 2
    MaxShipsLock = 1

INVARIANTS
  TypeOK
  MessagesOK
  DoorsMutex
  DoorsOpenValvesClosed
  DoorsOpenWaterlevelRight
  MaxShipsPerLocation
  AllShipsCannotReachGoal  \* This should FAIL, providing the counterexample
```

**Key Point:** Use `Spec` (NOT `FairSpec`) to allow TLC to explore ALL possible schedules including optimal ones.

---

## 📊 Verification Status

| Task | Status | Notes |
|------|--------|-------|
| Identify minimal deadlock config | ✅ COMPLETE | 3 locks, 2 ships documented |
| Explain deadlock scenario | ✅ COMPLETE | Detailed in reports |
| Formalize property | ✅ DOCUMENTED | ❌ Not in .tla file |
| Verify property with TLC | ✅ DOCUMENTED | ❌ Cannot re-run without property |
| Analyze counterexample | ✅ COMPLETE | 358-state schedule analyzed |
| Explain deadlock avoidance | ✅ COMPLETE | Sequential usage explained |
| Report schedule length | ✅ COMPLETE | 358 steps with explanation |

---

## 🎯 Next Steps to Complete Bonus Question

### Step 1: Add Property to lock_multiple.tla

Find the "define" section and add:
```tla
AllShipsCannotReachGoal == ~(\A s \in Ships: shipStates[s] = "goal_reached")
```

### Step 2: Create Configuration File

Create `lock_bonus.cfg` with proper constants and invariant check.

### Step 3: Run Verification

```powershell
java -jar tla2tools.jar -config lock_bonus.cfg lock_system.tla
```

### Step 4: Capture Results

Save TLC output showing:
- Invariant violation found
- Counterexample length: 358 states
- Final state with both ships at "goal_reached"

### Step 5: Optional - Inspect Trace

Use TLC Toolbox to:
- View full 358-state trace
- Export key states to documentation
- Create visualizations of schedule

---

## 📝 Documentation Quality

### Existing Analysis: EXCELLENT ✅

The reports contain:
- ✅ Clear problem statement
- ✅ Formal property definition
- ✅ Detailed TLC results
- ✅ Comprehensive counterexample analysis
- ✅ Practical implications discussed
- ✅ Comparison with fairness results
- ✅ Instructions for trace inspection

**Files:**
- `BONUS_QUESTION_ANALYSIS.md` - 275 lines, comprehensive
- `bonus_question_summary.md` - 175 lines, concise version

### What Could Be Added:

1. **Visual Schedule Diagram**
   - Timeline showing ship movements
   - Lock state changes over time
   - Decision points highlighted

2. **Key States Extracted**
   - States 1, 50, 100, 150, 200, 250, 300, 358
   - Show progression of ships through locks

3. **Pattern Generalization**
   - Rules for deadlock-avoiding scheduling
   - Pseudocode for improved controller

---

## 🔍 Verification Checklist for Submission

**For the Bonus Question to be complete:**

- [ ] Property `AllShipsCannotReachGoal` exists in `lock_multiple.tla`
- [ ] Configuration file exists (with `Spec` not `FairSpec`)
- [ ] TLC verification can be re-run successfully
- [ ] Report includes:
  - [ ] Minimal deadlock configuration identified
  - [ ] Deadlock counterexample explained
  - [ ] Property formalization provided
  - [ ] TLC result described (property FALSE = counterexample found)
  - [ ] Counterexample length reported (358 states)
  - [ ] Explanation of why schedule avoids deadlocks
  - [ ] Practical implications discussed

**Current Status:** Analysis ✅ COMPLETE | Implementation ⚠️ NEEDS PROPERTY ADDED

---

## 💡 Key Insights (For Report)

### What Makes This Interesting:

1. **Paradox:** Fairness (WF) **causes** deadlock, removing it **prevents** deadlock
   - Counter-intuitive but theoretically sound
   - Shows design must not rely on fairness for correctness

2. **Constructive Proof:** TLC doesn't just say "deadlock is avoidable"—it provides a 358-state witness
   - Can be inspected, analyzed, implemented
   - Real systems could follow similar patterns

3. **Complexity:** 358 steps for 2 ships × 3 locks
   - Shows difficulty of manual scheduling
   - Justifies formal verification for distributed systems

4. **Design Lesson:** Simple capacity constraints require sophisticated coordination
   - `MaxShipsLock=1` seems simple but creates complex state space
   - Controller needs intelligent request ordering, not just FIFO processing

---

## 🎓 Conclusion

**Overall Assessment: EXCELLENT PROGRESS**

The bonus question has been **thoroughly analyzed** with comprehensive documentation. The only missing piece is adding the property to the actual `.tla` file and creating a configuration to re-run the verification.

**Estimated Completion Time:** 10-15 minutes
1. Add property to lock_multiple.tla (2 min)
2. Create lock_bonus.cfg (3 min)
3. Run verification and capture output (5 min)
4. Update reports with fresh results (5 min)

The hard work (understanding the problem, analyzing the counterexample, documenting the insights) is **already done** ✅

---

## 📚 Report Recommendations

For your final submission report, include:

1. **Section: "Bonus Question - Deadlock-Avoiding Schedule"**
   - Subsection: Problem Statement
   - Subsection: Property Formalization
   - Subsection: Verification Results
   - Subsection: Schedule Analysis (358 states)
   - Subsection: Why Deadlocks Are Avoided
   - Subsection: Practical Implications

2. **Key Elements to Include:**
   - Property definition: `AllShipsCannotReachGoal`
   - TLC output showing invariant violation
   - Final state showing both ships at goal_reached
   - Explanation of sequential lock usage pattern
   - Comparison: Fairness vs. No Fairness

3. **Figures/Tables:**
   - Table: Ship positions at key states
   - Diagram: Lock usage timeline
   - Comparison table: With/Without fairness results

The existing documentation in `reports/BONUS_QUESTION_ANALYSIS.md` provides excellent material to adapt for the final report!
