# Settings View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `SettingsView` stub with a working Form that lets users set daily calorie and macro goals, auto-saving to the `UserSettings` SwiftData model with sensible defaults on first launch.

**Architecture:** Outer `SettingsView` handles `@Query` + create-if-missing logic; inner `SettingsFormView` receives a non-optional `UserSettings` and uses `@Bindable` for zero-boilerplate auto-save. A private `GoalField` subview binds `Double` values directly via `TextField(value:format:)`.

**Tech Stack:** SwiftUI, SwiftData (`@Query`, `@Bindable`, `FetchDescriptor`), iOS 26.2+

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Rewrite | `MacroBitt/Views/Settings/SettingsView.swift` | All Settings UI: outer view, inner form view, GoalField subview |

No other files need to change. `UserSettings` model and its `ModelContainer` registration are already complete.

---

### Task 1: Implement SettingsView.swift

**Files:**
- Rewrite: `MacroBitt/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Replace the file contents**

Write the following complete implementation:

```swift
//
//  SettingsView.swift
//  MacroBitt
//

import SwiftUI
import SwiftData

// MARK: - Root Tab View

struct SettingsView: View {
    @Query private var allSettings: [UserSettings]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            if let settings = allSettings.first {
                SettingsFormView(settings: settings)
            }
        }
        .onAppear {
            // Use a synchronous fetch (not the @Query array) to avoid
            // any async-population race and prevent duplicate records.
            guard (try? modelContext.fetch(FetchDescriptor<UserSettings>()))?.isEmpty == true else { return }
            modelContext.insert(UserSettings())
        }
    }
}

// MARK: - Form View

private struct SettingsFormView: View {
    @Bindable var settings: UserSettings

    var body: some View {
        Form {
            Section("Daily Goal") {
                GoalField(label: "Calories", value: $settings.dailyCalorieGoal, unit: "kcal")
            }

            Section(
                header: Text("Macro Goals"),
                footer: Text("All macro goals are in grams per day.")
            ) {
                GoalField(label: "Protein", value: $settings.proteinGoal, unit: "g")
                GoalField(label: "Carbs",   value: $settings.carbsGoal,   unit: "g")
                GoalField(label: "Fat",     value: $settings.fatGoal,     unit: "g")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Goal Field

private struct GoalField: View {
    let label: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MacroBitt.xcodeproj \
             -scheme MacroBitt \
             -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
             build 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `** BUILD SUCCEEDED **` with no errors.

- [ ] **Step 3: Commit**

```bash
git add MacroBitt/Views/Settings/SettingsView.swift
git commit -m "feat: implement Settings tab with calorie and macro goal fields"
```

---

### Task 2: Manual verification

- [ ] **Step 1: Run the app in the simulator**

In Xcode: ⌘R. Confirm the app launches without errors.

- [ ] **Step 2: First launch — defaults are pre-populated**

Navigate to the Settings tab. Confirm:
- Calories shows `2,000`
- Protein shows `150`
- Carbs shows `200`
- Fat shows `65`

- [ ] **Step 3: Auto-save — values persist across tab switches**

Change Calories to `2,500`. Switch to the Log Food tab. Switch back to Settings. Confirm `2,500` is still shown.

- [ ] **Step 4: Auto-save — values persist across app restarts**

Change Protein to `180`. Force-quit the app (swipe up in app switcher). Relaunch. Navigate to Settings. Confirm `180` is shown.

- [ ] **Step 5: No duplicate records**

Values should not reset on subsequent launches. If they reset, the create-if-missing guard is inserting a duplicate — re-check the `FetchDescriptor` guard logic.

- [ ] **Step 6: Xcode Preview works**

Open `SettingsView.swift` in Xcode, open the preview canvas (⌥⌘↩). Confirm the preview renders the form without crashing. The in-memory container pre-populates defaults on first appear.
