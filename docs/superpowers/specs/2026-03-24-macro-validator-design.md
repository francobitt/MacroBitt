# Macro-Calorie Validation System Design

**Date:** 2026-03-24
**Feature:** MacroValidator utility + FoodEntry flagging + inline warning UI
**Status:** Approved

## Overview

Enforce the rule `(fat × 9) + (carbs × 4) + (protein × 4) = calories` (±5 kcal tolerance) on every food entry path. Entries that fail are saved with `isFlagged = true` and a non-zero `calorieDiscrepancy`. The manual entry form shows a real-time warning banner; the daily log shows a warning icon next to flagged entries.

---

## 1. MacroValidator Utility

**File:** `MacroBitt/Utilities/MacroValidator.swift`

Pure value-type struct. No SwiftData imports. No side effects.

```swift
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

**Interface contract:** Takes four `Double` values (always per-serving), returns a `Result`. The `difference` field is signed (positive = user entered more than calculated).

---

## 2. FoodEntry Model Changes

**File:** `MacroBitt/Models/FoodEntry.swift`

Add two properties with default values (SwiftData lightweight migration — no `VersionedSchema` needed):

```swift
var isFlagged: Bool = false
var calorieDiscrepancy: Double = 0   // signed total kcal: stored calories − calculated calories
```

**Unit:** `calorieDiscrepancy` stores the **total** discrepancy (i.e. `validation.difference * servingCount`), matching the scale of `entry.calories`. This ensures `entry.calorieDiscrepancy ≈ entry.calories − ((entry.fat × 9) + (entry.carbs × 4) + (entry.protein × 4))` is always true. A small non-zero value when `isFlagged == false` is expected and acceptable — `calorieDiscrepancy == 0` is NOT a synonym for "valid."

Add matching parameters to `init`, defaulting to `false` and `0.0` respectively:
```swift
init(
    ...
    isFlagged: Bool = false,
    calorieDiscrepancy: Double = 0.0
)
```

All existing call sites compile unchanged because both parameters have defaults.

Existing on-device records automatically receive `isFlagged = false` and `calorieDiscrepancy = 0` via SwiftData's lightweight migration.

---

## 3. AddFoodEntryView Changes

**File:** `MacroBitt/Views/FoodLog/AddFoodEntryView.swift`

### 3a. Real-time warning banner

A private computed property on the view. Uses `guard let` optional binding to parse all four strings inline — self-contained, no dependency on the view's `?? 0` computed properties, and no spurious banner for non-numeric or empty input:

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

Shown as a list row appended inside the "Macros per serving" `Section` when `validationResult?.isValid == false`:

```
⚠  Calculated: 485 kcal · Entered: 600 kcal · Difference: 115
```

Row styling: `Color.orange.opacity(0.12)` list row background, **orange** icon and text tint. Saving remains enabled — the banner is advisory only.

*(Note: the banner uses **orange**. The row icon in FoodLogView uses **yellow**. These are intentionally different — orange for the active-input warning, yellow for the subtle at-a-glance list indicator.)*

### 3b. Validation on save

In `save()`, after computing totals (`totalCalories`, `totalProtein`, `totalCarbs`, `totalFat`), validate per-serving values (the relationship `(fat×9)+(carbs×4)+(protein×4) = calories` is scale-invariant, so per-serving is sufficient) and store the **total** discrepancy:

```swift
let validation = MacroValidator.validate(
    calories: calories, protein: protein,
    carbs: carbs, fat: fat)

entry.isFlagged          = !validation.isValid
entry.calorieDiscrepancy = validation.difference * servingCount
```

Apply in **both** the create path (`let entry = FoodEntry(...)` block) and the edit path (`if let entry = editingEntry` block).

---

## 4. FoodLogView Changes

**File:** `MacroBitt/Views/FoodLog/FoodLogView.swift`

In `FoodEntryRow`, the existing body is a `VStack` with two rows. Add the warning icon inside the existing top-row `HStack` (name + calorie), left of the calorie text. The second row (serving size + compact macros) is unchanged:

```swift
// Top row — modified
HStack {
    Text(entry.name)
        .font(.body)
    Spacer()
    if entry.isFlagged {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.yellow)   // yellow (not orange — see note in §3a)
    }
    Text(entry.calories.formatted(.number.precision(.fractionLength(0))) + " kcal")
        .font(.body)
        .fontWeight(.medium)
}

// Second row — unchanged
HStack(spacing: 12) {
    if let size = entry.servingSize {
        Text(size).foregroundStyle(.secondary)
    }
    Spacer()
    CompactMacros(protein: entry.protein, carbs: entry.carbs, fat: entry.fat)
}
.font(.caption)
```

---

## 5. CLAUDE.md Update

Add a `## Data Integrity Rules` section at the bottom of `CLAUDE.md`:

```
## Data Integrity Rules

**MACRO-CALORIE RULE:** All food entries must be validated with the formula
`(fat × 9) + (carbs × 4) + (protein × 4) = total calories`, with a tolerance
of 5 calories. Entries outside this tolerance must be flagged (`isFlagged = true`,
`calorieDiscrepancy` set to the signed total difference). This validation applies
to every code path that creates or modifies a FoodEntry — no exceptions.

Use `MacroValidator.validate(calories:protein:carbs:fat:)` in
`MacroBitt/Utilities/MacroValidator.swift`.
```

---

## Files Modified

| Action | Path |
|--------|------|
| Create | `MacroBitt/Utilities/MacroValidator.swift` |
| Modify | `MacroBitt/Models/FoodEntry.swift` |
| Modify | `MacroBitt/Views/FoodLog/AddFoodEntryView.swift` |
| Modify | `MacroBitt/Views/FoodLog/FoodLogView.swift` |
| Modify | `CLAUDE.md` |

---

## Verification

1. **Banner appears:** Enter Protein=30, Carbs=50, Fat=10, Calories=600 → banner shows "Calculated: 410 kcal · Entered: 600 kcal · Difference: 190"
2. **Banner clears:** Correct Calories to 410 → banner disappears
3. **Non-numeric input:** Type "abc" in Fat field → no banner shown
4. **Flagging on save (1 serving):** Save 600-cal entry (1 serving) → Food Log shows yellow ⚠ icon; `calorieDiscrepancy ≈ 190`
5. **Flagging on save (2 servings):** Save same entry with servingCount=2 → `calorieDiscrepancy ≈ 380` (total scale)
6. **No icon for valid entry:** Add P=30, C=50, F=10, Cal=410 → save → no icon
7. **Edit path clears flag:** Tap flagged entry → fix calories → save → icon disappears, `isFlagged = false`
8. **Schema migration:** Existing entries load without crash; `isFlagged = false`, `calorieDiscrepancy = 0`
