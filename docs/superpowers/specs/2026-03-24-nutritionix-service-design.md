# NutritionixService Design

**Date:** 2026-03-24
**Feature:** Nutritionix API v2 service layer
**Status:** Approved

## Overview

Add a `NutritionixService` to `MacroBitt/Services/` that wraps the Nutritionix v2 API. It supports three search modes (natural language, barcode, keyword autocomplete), parses all responses into a common `NutritionixFoodItem` struct, and runs every result through `MacroValidator` before returning it to callers. Credentials are stored in a gitignored `Config.swift` file.

---

## 1. File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create (gitignored) | `MacroBitt/Config.swift` | Real API credentials — never committed |
| Create (checked in, outside build target) | `Config.example.swift` (repo root) | Placeholder showing required keys |
| Create | `MacroBitt/Services/NutritionixModels.swift` | Domain types, error enum, internal Codable response structs |
| Create | `MacroBitt/Services/NutritionixService.swift` | Protocol + concrete service implementation |
| Create | `MacroBittTests/NutritionixServiceTests.swift` | Unit tests via URLProtocol stub + MockNutritionixService |
| Modify | `.gitignore` | Add `MacroBitt/Config.swift` |

---

## 2. Credentials — Config.swift

`Config.swift` is gitignored and never committed. `Config.example.swift` lives at the **repo root** (not inside `MacroBitt/`) so it is never included in the Xcode build target and cannot clash with the real `Config.swift`.

**`MacroBitt/Config.swift`** (gitignored, inside build target):
```swift
// DO NOT COMMIT — fill in real credentials
enum Config {
    static let nutritionixAppID  = "your-app-id-here"
    static let nutritionixAppKey = "your-app-key-here"
}
```

**`Config.example.swift`** (checked in, at repo root — outside Xcode target):
```swift
// Copy to MacroBitt/Config.swift and fill in real credentials.
// Never commit MacroBitt/Config.swift.
enum Config {
    static let nutritionixAppID  = "REPLACE_ME"
    static let nutritionixAppKey = "REPLACE_ME"
}
```

`.gitignore` addition:
```
MacroBitt/Config.swift
```

**First-time setup:** Clone the repo, copy `Config.example.swift` → `MacroBitt/Config.swift`, fill in credentials, then build. Without this step the build fails with "use of unresolved identifier 'Config'". An optional Run Script build phase can surface a clear error:
```bash
if fgrep -q 'REPLACE_ME' "$SRCROOT/MacroBitt/Config.swift" 2>/dev/null; then
  echo "error: MacroBitt/Config.swift still contains placeholder credentials. Fill in real values."
  exit 1
fi
if [ ! -f "$SRCROOT/MacroBitt/Config.swift" ]; then
  echo "error: MacroBitt/Config.swift is missing. Copy Config.example.swift and fill in credentials."
  exit 1
fi
```

---

## 3. Data Models — NutritionixModels.swift

### 3a. NutritionixFoodItem

Fully parsed, macro-validated domain type returned from `naturalLanguageSearch` and `barcodeSearch`.

```swift
struct NutritionixFoodItem: Sendable {
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let servingQuantity: Double    // e.g. 1.0
    let servingUnit: String        // e.g. "cup"
    let servingSize: Double        // weight in grams, e.g. 240.0
    let photoURL: URL?
    let brandName: String?         // nil for common (unbranded) foods
    let validation: MacroValidator.Result
}
```

`validation` is always present — every item is passed through `MacroValidator.validate()` at parse time. Callers read `item.validation.isValid` to decide whether to show a mismatch warning before the user saves to SwiftData.

`MacroValidator.Result.difference` is `provided − calculated` (positive = user entered more than macros imply, negative = user entered less). This matches `FoodEntry.calorieDiscrepancy`, which is set to `validation.difference * servingCount` at save time.

### 3b. NutritionixSuggestion

Lightweight autocomplete result from `keywordSearch`. Contains no nutrition data — the caller passes `suggestion.name` to `naturalLanguageSearch` to retrieve full macros when the user taps an item.

```swift
struct NutritionixSuggestion: Sendable {
    enum Kind: Sendable { case common, branded }
    let name: String
    let brandName: String?
    let photoURL: URL?
    let kind: Kind
}
```

### 3c. NutritionixError

Typed error enum covering all failure modes:

```swift
enum NutritionixError: Error, LocalizedError, Sendable {
    case invalidCredentials          // HTTP 401
    case rateLimitExceeded           // HTTP 429
    case httpError(statusCode: Int)  // other 4xx / 5xx
    case networkFailure(URLError)
    case decodingFailure(DecodingError)
    case noResults
}
```

`rateLimitExceeded` is a first-class case so UIs can show a specific message ("Too many searches — wait a moment") rather than a generic error. The enum is `Sendable` (both `URLError` and `DecodingError` are `Sendable`), satisfying Swift 6 strict concurrency requirements when thrown across `async` boundaries.

### 3d. Internal Codable types

Internal structs decode raw Nutritionix JSON. They are not `public` and are never exposed through the protocol. Field names use Nutritionix's snake_case directly to avoid custom `CodingKeys`.

**`NXPhoto`:**
```swift
struct NXPhoto: Codable {
    let thumb: String?
}
```

**`NXFood`** (shared shape used by both `/v2/natural/nutrients` and `/v2/search/item`):
```swift
struct NXFood: Codable {
    let food_name: String?                  // nil on malformed responses → defaults to ""
    let brand_name: String?
    let serving_qty: Double?
    let serving_unit: String?
    let serving_weight_grams: Double?
    let nf_calories: Double?
    let nf_protein: Double?
    let nf_total_carbohydrate: Double?
    let nf_total_fat: Double?
    let photo: NXPhoto?
}
```

All string fields are `String?`. Missing `food_name` defaults to `""` in `parse()`, consistent with the numeric-field defaulting policy.

**`NXNaturalResponse`** (for `/v2/natural/nutrients` POST):
```swift
struct NXNaturalResponse: Codable {
    let foods: [NXFood]
}
```

**`NXSearchItemResponse`** (for `/v2/search/item?upc=`):
```swift
struct NXSearchItemResponse: Codable {
    let foods: [NXFood]   // same NXFood shape as NXNaturalResponse
}
```
`barcodeSearch` decodes into `NXSearchItemResponse`, takes `foods.first`, and throws `.noResults` if the array is empty.

**`NXInstantResponse`** (for `/v2/search/instant?query=`):
```swift
struct NXInstantResponse: Codable {
    let common: [NXInstantItem]?   // nil when no common matches
    let branded: [NXInstantItem]?  // nil when no branded matches
}

struct NXInstantItem: Codable {
    let food_name: String
    let brand_name: String?
    let photo: NXPhoto?
}
```

Both `common` and `branded` arrays are combined into a single flat `[NutritionixSuggestion]` in the order: common items first, branded items second. If either array is absent, treat it as empty. No cap is applied beyond what the Nutritionix API returns.

Key field mapping from `NXFood` to `NutritionixFoodItem`:

| Nutritionix field | Maps to | Default when nil |
|---|---|---|
| `food_name` | `name` | `""` |
| `nf_calories` | `calories` | `0` |
| `nf_protein` | `protein` | `0` |
| `nf_total_carbohydrate` | `carbs` | `0` |
| `nf_total_fat` | `fat` | `0` |
| `serving_qty` | `servingQuantity` | `1` |
| `serving_unit` | `servingUnit` | `"serving"` |
| `serving_weight_grams` | `servingSize` | `0` |
| `photo?.thumb` | `photoURL` | `nil` |
| `brand_name` | `brandName` | `nil` |

---

## 4. Service — NutritionixService.swift

### 4a. Protocol

```swift
protocol NutritionixServiceProtocol: Sendable {
    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem]
    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem
    func keywordSearch(query: String) async throws -> [NutritionixSuggestion]
}
```

`barcodeSearch` returns a single item (one UPC → one product) or throws `noResults`. The protocol is `Sendable` so conforming types can be stored in `@Observable` view models without Swift 6 warnings.

### 4b. Concrete NutritionixService

```swift
final class NutritionixService: NutritionixServiceProtocol, @unchecked Sendable {
    private let session: URLSession
    private let appID: String
    private let appKey: String

    init(session: URLSession = .shared,
         appID: String = Config.nutritionixAppID,
         appKey: String = Config.nutritionixAppKey)
}
```

`@unchecked Sendable` is safe here because `URLSession` is already `Sendable`, and `appID`/`appKey` are immutable `let` constants set at init. `session` is injectable for tests.

### 4c. Request construction

A private helper attaches auth headers to every request:

```swift
private func authorizedRequest(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest
```

Headers added to every request:
- `x-app-id: <appID>`
- `x-app-key: <appKey>`
- `Content-Type: application/json` (when body is present)

### 4d. Endpoints

| Method | Endpoint | HTTP | Body |
|--------|----------|------|------|
| `naturalLanguageSearch` | `https://trackapi.nutritionix.com/v2/natural/nutrients` | POST | `{"query": "<text>"}` |
| `barcodeSearch` | `https://trackapi.nutritionix.com/v2/search/item?upc=<upc>` | GET | none |
| `keywordSearch` | `https://trackapi.nutritionix.com/v2/search/instant?query=<text>` | GET | none |

### 4e. Error mapping

A private `mapHTTPError(_ response: HTTPURLResponse) -> NutritionixError` converts status codes:
- 401 → `.invalidCredentials`
- 429 → `.rateLimitExceeded`
- all other non-2xx → `.httpError(statusCode:)`

### 4f. MacroValidator integration

Applied inside the private `parse(_ item: NXFood) -> NutritionixFoodItem` method:

```swift
private func parse(_ item: NXFood) -> NutritionixFoodItem {
    let cal  = item.nf_calories ?? 0
    let prot = item.nf_protein ?? 0
    let carb = item.nf_total_carbohydrate ?? 0
    let fat  = item.nf_total_fat ?? 0

    return NutritionixFoodItem(
        name: item.food_name ?? "",
        calories: cal, protein: prot, carbs: carb, fat: fat,
        servingQuantity: item.serving_qty ?? 1,
        servingUnit: item.serving_unit ?? "serving",
        servingSize: item.serving_weight_grams ?? 0,
        photoURL: item.photo?.thumb.flatMap { URL(string: $0) },
        brandName: item.brand_name,
        validation: MacroValidator.validate(calories: cal, protein: prot,
                                            carbs: carb, fat: fat)
    )
}
```

This is called for every item from every endpoint that returns `NXFood`. No `NutritionixFoodItem` can be constructed without a `validation` result attached.

The existing `AddFoodEntryView.save()` validation is unchanged and complementary: the service warns at search time, `save()` flags at persist time.

---

## 5. Unit Tests — NutritionixServiceTests.swift

Tests use Swift Testing (`import Testing`, `@Test`, `#expect`).

**Two test groups:**

### Group A — `MockNutritionixService` (protocol-level)
A `struct MockNutritionixService: NutritionixServiceProtocol` with configurable return values or thrown errors. Tests:

1. `naturalLanguageSearch` returns a non-empty `[NutritionixFoodItem]`
2. `barcodeSearch` returns a single item
3. `barcodeSearch` throws `noResults` when mock is configured to return empty
4. `keywordSearch` returns `[NutritionixSuggestion]` with correct `.kind` values (`.common` and `.branded`)
5. `rateLimitExceeded` propagates correctly to callers

### Group B — `NutritionixService` with stubbed `URLSession` (concrete class)
A `URLProtocol` subclass (`NutritionixURLStub`) intercepts requests and returns hardcoded JSON fixture strings. Tests:

6. `naturalLanguageSearch` — fixture JSON with known macros → `parse()` produces correct `NutritionixFoodItem` fields
7. Valid macros in fixture (macros sum to stated calories ±5) → `validation.isValid == true`
8. Mismatched macros in fixture (e.g. 30g protein + 50g carbs + 10g fat → 410 kcal, but `nf_calories: 600`) → `validation.isValid == false`, `validation.difference == 190`
9. `barcodeSearch` — fixture with single `NXFood` item → returns that item; empty `foods` array → throws `noResults`
10. `keywordSearch` — fixture with both `common` and `branded` arrays → combined flat array, common items first
11. HTTP 429 response → throws `rateLimitExceeded`
12. HTTP 401 response → throws `invalidCredentials`
13. Malformed JSON → throws `decodingFailure`

Group B tests are what verify that `parse()` actually calls `MacroValidator` and that JSON decoding works end-to-end.

---

## 6. Verification

1. Build succeeds: `** BUILD SUCCEEDED **`
2. All 13 unit tests pass (no real network calls)
3. `MacroBitt/Config.swift` appears in `.gitignore`; `git status` does not list it after creation
4. `Config.example.swift` is at the repo root (not inside `MacroBitt/`), tracked by git, not in the build target
5. Each service method returns the expected type; `NutritionixFoodItem.validation` is always populated
6. `NutritionixService` and `NutritionixServiceProtocol` compile cleanly under Swift 6 strict concurrency
