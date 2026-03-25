# Macro-Calorie Validation System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce `(fat × 9) + (carbs × 4) + (protein × 4) = calories` (±5 kcal) on every FoodEntry, flag mismatches, show a real-time warning banner in the entry form, and display a warning icon in the daily log list.

**Architecture:** Pure `MacroValidator` struct owns the math. `FoodEntry` stores `isFlagged` and `calorieDiscrepancy`. `AddFoodEntryView` computes validation reactively for the banner and applies it in `save()`. `FoodEntryRow` reads `isFlagged` to show the icon. No other files change.

**Tech Stack:** Swift 6, SwiftData, SwiftUI, Swift Testing framework (`import Testing`, `#expect`)

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `MacroBitt/Utilities/MacroValidator.swift` | Pure validation logic |
| Create | `MacroBittTests/MacroValidatorTests.swift` | Unit tests for validator |
| Modify | `MacroBitt/Models/FoodEntry.swift` | Add `isFlagged`, `calorieDiscrepancy` |
| Modify | `MacroBitt/Views/FoodLog/AddFoodEntryView.swift` | Warning banner + save wiring |
| Modify | `MacroBitt/Views/FoodLog/FoodLogView.swift` | Warning icon in `FoodEntryRow` |
| Modify | `CLAUDE.md` | Data Integrity Rules section |

---

### Task 1: MacroValidator utility + unit tests

**Files:**
- Create: `MacroBitt/Utilities/MacroValidator.swift`
- Create: `MacroBittTests/MacroValidatorTests.swift`

- [ ] **Step 1: Create the validator**

```swift
// MacroBitt/Utilities/MacroValidator.swift
struct MacroValidator {
    struct Result {
        let isValid: Bool
        let calculatedCalories: Double
        let difference: Double   // provided − calculated (signed)
    }

    static let tolerance: Double = 5

    static func validate(calories: Double, protein: Double,
                         carbs: Double, fat: Double) -> Result {
        let calc = (fat * 9) + (carbs * 4) + (protein * 4)
        let diff = calories - calc
        return Result(isValid: abs(diff) <= tolerance,
                      calculatedCalories: calc,
                      difference: diff)
    }
}
```

- [ ] **Step 2: Write the tests (they will fail until the file exists in the build)**

```swift
// MacroBittTests/MacroValidatorTests.swift
import Testing
@testable import MacroBitt

struct MacroValidatorTests {

    // P=30 × 4 + C=50 × 4 + F=10 × 9 = 120 + 200 + 90 = 410 kcal
    @Test func validEntry() {
        let r = MacroValidator.validate(calories: 410, protein: 30, carbs: 50, fat: 10)
        #expect(r.isValid)
        #expect(r.calculatedCalories == 410)
        #expect(r.difference == 0)
    }

    @Test func invalidEntry_overBudget() {
        let r = MacroValidator.validate(calories: 600, protein: 30, carbs: 50, fat: 10)
        #expect(!r.isValid)
        #expect(r.calculatedCalories == 410)
        #expect(r.difference == 190)   // 600 - 410
    }

    @Test func withinTolerance() {
        // 413 entered, 410 calculated — 3 kcal difference ≤ 5
        let r = MacroValidator.validate(calories: 413, protein: 30, carbs: 50, fat: 10)
        #expect(r.isValid)
    }

    @Test func atToleranceBoundaryIsValid() {
        // Exactly 5 kcal difference — still valid
        let r = MacroValidator.validate(calories: 415, protein: 30, carbs: 50, fat: 10)
        #expect(r.isValid)
    }

    @Test func justOverToleranceIsInvalid() {
        // 6 kcal difference — invalid
        let r = MacroValidator.validate(calories: 416, protein: 30, carbs: 50, fat: 10)
        #expect(!r.isValid)
    }

    @Test func negativeDifference() {
        // Entered less than calculated
        let r = MacroValidator.validate(calories: 400, protein: 30, carbs: 50, fat: 10)
        #expect(!r.isValid)
        #expect(r.difference == -10)   // 400 - 410
    }
}
```

- [ ] **Step 3: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
    -project MacroBitt.xcodeproj \
    -scheme MacroBittTests \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    2>&1 | grep -E "passed|failed|error:|BUILD"
```

Expected: `Test Suite ... passed` with 6 tests.

- [ ] **Step 4: Commit**

```bash
git add MacroBitt/Utilities/MacroValidator.swift MacroBittTests/MacroValidatorTests.swift
git commit -m "feat: add MacroValidator utility with unit tests"
```

---

### Task 2: FoodEntry model — add isFlagged and calorieDiscrepancy

**Files:**
- Modify: `MacroBitt/Models/FoodEntry.swift`

- [ ] **Step 1: Add the two properties and update init**

Replace the entire file with:

```swift
//
//  FoodEntry.swift
//  MacroBitt
//
//  Created by francobitt on 3/23/26.
//

import SwiftData
import Foundation

@Model
final class FoodEntry {
    var id: UUID
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var servingSize: String?
    var servingCount: Double
    var timestamp: Date
    var mealType: MealType
    var isFlagged: Bool = false
    var calorieDiscrepancy: Double = 0   // signed total kcal: stored calories − calculated

    init(
        id: UUID = UUID(),
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        servingSize: String? = nil,
        servingCount: Double = 1.0,
        timestamp: Date = Date(),
        mealType: MealType,
        isFlagged: Bool = false,
        calorieDiscrepancy: Double = 0.0
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingSize = servingSize
        self.servingCount = servingCount
        self.timestamp = timestamp
        self.mealType = mealType
        self.isFlagged = isFlagged
        self.calorieDiscrepancy = calorieDiscrepancy
    }
}
```

- [ ] **Step 2: Build to verify the model compiles and migration is safe**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MacroBitt.xcodeproj \
    -scheme MacroBitt \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MacroBitt/Models/FoodEntry.swift
git commit -m "feat: add isFlagged and calorieDiscrepancy to FoodEntry"
```

---

### Task 3: AddFoodEntryView — warning banner + save wiring

**Files:**
- Modify: `MacroBitt/Views/FoodLog/AddFoodEntryView.swift`

- [ ] **Step 1: Add the validationResult computed property**

In the `// MARK: - Computed` section, after the existing four `Double` properties (`calories`, `protein`, `carbs`, `fat`), add:

```swift
private var validationResult: MacroValidator.Result? {
    guard let cal  = Double(caloriesText),
          let prot = Double(proteinText),
          let carb = Double(carbsText),
          let fat  = Double(fatText)
    else { return nil }
    return MacroValidator.validate(
        calories: cal, protein: prot, carbs: carb, fat: fat)
}
```

- [ ] **Step 2: Add the warning banner inside the "Macros per serving" Section**

The existing `Section("Macros per serving")` block contains four `MacroField` rows. Add the warning row at the end of that section, after the Fat field:

```swift
Section("Macros per serving") {
    MacroField(label: "Calories", unit: "kcal", text: $caloriesText)
    MacroField(label: "Protein",  unit: "g",    text: $proteinText)
    MacroField(label: "Carbs",    unit: "g",    text: $carbsText)
    MacroField(label: "Fat",      unit: "g",    text: $fatText)

    if let result = validationResult, !result.isValid {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Calculated: \(Int(result.calculatedCalories)) kcal · Entered: \(Int(calories)) kcal · Difference: \(Int(abs(result.difference)))")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .listRowBackground(Color.orange.opacity(0.12))
    }
}
```

- [ ] **Step 3: Wire validation into save() — edit path**

In the `if let entry = editingEntry` block, after all the existing property assignments (`entry.mealType = mealType`), add:

```swift
let validation = MacroValidator.validate(
    calories: calories, protein: protein, carbs: carbs, fat: fat)
entry.isFlagged          = !validation.isValid
entry.calorieDiscrepancy = validation.difference * servingCount
```

- [ ] **Step 4: Wire validation into save() — create path**

In the `else` block (new entry creation), after `log.entries.append(entry)`, add:

```swift
let validation = MacroValidator.validate(
    calories: calories, protein: protein, carbs: carbs, fat: fat)
entry.isFlagged          = !validation.isValid
entry.calorieDiscrepancy = validation.difference * servingCount
```

- [ ] **Step 5: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MacroBitt.xcodeproj \
    -scheme MacroBitt \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MacroBitt/Views/FoodLog/AddFoodEntryView.swift
git commit -m "feat: add macro validation banner and save wiring to AddFoodEntryView"
```

---

### Task 4: FoodLogView — warning icon in FoodEntryRow

**Files:**
- Modify: `MacroBitt/Views/FoodLog/FoodLogView.swift`

- [ ] **Step 1: Add the warning icon to FoodEntryRow's top HStack**

Locate the `FoodEntryRow` struct. Its `body` is a `VStack` with two rows. Modify only the top `HStack` (name + calories) to add the icon when `entry.isFlagged`. The second `HStack` (serving size + compact macros) is unchanged:

```swift
private struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.name)
                    .font(.body)
                Spacer()
                if entry.isFlagged {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
                Text(entry.calories.formatted(.number.precision(.fractionLength(0))) + " kcal")
                    .font(.body)
                    .fontWeight(.medium)
            }

            HStack(spacing: 12) {
                if let size = entry.servingSize {
                    Text(size)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CompactMacros(protein: entry.protein, carbs: entry.carbs, fat: entry.fat)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MacroBitt.xcodeproj \
    -scheme MacroBitt \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MacroBitt/Views/FoodLog/FoodLogView.swift
git commit -m "feat: show validation warning icon on flagged entries in FoodLogView"
```

---

### Task 5: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Append the Data Integrity Rules section**

Add the following at the end of `CLAUDE.md`:

```markdown
## Data Integrity Rules

**MACRO-CALORIE RULE:** All food entries must be validated with the formula
`(fat × 9) + (carbs × 4) + (protein × 4) = total calories`, with a tolerance
of 5 calories. Entries outside this tolerance must be flagged (`isFlagged = true`,
`calorieDiscrepancy` set to the signed total difference). This validation applies
to every code path that creates or modifies a FoodEntry — no exceptions.

Use `MacroValidator.validate(calories:protein:carbs:fat:)` in
`MacroBitt/Utilities/MacroValidator.swift`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add Data Integrity Rules to CLAUDE.md"
```

---

### Task 6: End-to-end verification

- [ ] **Step 1: Run all unit tests one final time**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
    -project MacroBitt.xcodeproj \
    -scheme MacroBittTests \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    2>&1 | grep -E "passed|failed|error:|BUILD"
```

Expected: all 6 MacroValidatorTests pass.

- [ ] **Step 2: Manual verification checklist**

Run the app (⌘R in Xcode) and verify:

1. **Banner appears:** Add Food → enter P=30, C=50, F=10, Cal=600 → orange banner shows "Calculated: 410 kcal · Entered: 600 kcal · Difference: 190"
2. **Banner clears:** Change Cal to 410 → banner disappears
3. **Non-numeric suppresses banner:** Type "abc" in Fat → no banner
4. **Flagged entry shows icon:** Save the P=30/C=50/F=10/Cal=600 entry → Food Log shows yellow ⚠ next to "600 kcal"
5. **Valid entry has no icon:** Add P=30/C=50/F=10/Cal=410 → no icon
6. **Edit clears flag:** Tap flagged entry → fix Cal to 410 → save → icon gone
7. **Schema migration:** Existing entries (if any) load without crash; no icon shown
