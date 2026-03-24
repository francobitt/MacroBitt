# Nutritionix Service Design

**Date:** 2026-03-24
**Feature:** NutritionixService — API client for food search and barcode lookup
**Status:** Approved

## Overview

A typed, async/await Swift service that wraps the Nutritionix v2 API. Exposes four search methods (natural language, barcode, Nutritionix item ID, keyword autocomplete), parses all results into a common domain struct, and runs every result through `MacroValidator` before returning to callers. Backed by a `Sendable` protocol for testability in Swift 6 strict-concurrency environments.

---

## 1. File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create (gitignored) | `MacroBitt/Config.swift` | API credentials — `enum Config` with `nutritionixAppID` and `nutritionixAppKey` |
| Create (committed) | `MacroBitt/Config.example.swift.txt` | Plain-text copy instructions — NOT a `.swift` file so it is never compiled |
| Create | `MacroBitt/Services/NutritionixModels.swift` | `NutritionixFoodItem`, `NutritionixSuggestion`, `NutritionixError`, internal Codable response types |
| Create | `MacroBitt/Services/NutritionixService.swift` | `NutritionixServiceProtocol: Sendable` + `NutritionixService: NutritionixServiceProtocol, @unchecked Sendable` |
| Create | `MacroBittTests/NutritionixServiceTests.swift` | Unit tests: mock-based protocol tests + URLProtocol-stubbed parsing tests |
| Modify | `.gitignore` | Add `**/Config.swift` entry |

---

## 2. Credentials — Config.swift

`Config.swift` is a gitignored Swift file containing a plain `enum` with two static string properties. The build fails at compile time if the file is absent, preventing silent misconfiguration. `Config.example.swift.txt` is a plain-text file (`.txt` extension — never compiled, so no duplicate-type error), giving new developers copy-paste setup instructions.

**`Config.swift`** (gitignored, never committed):
```swift
// MacroBitt/Config.swift
// DO NOT COMMIT — add your real keys here
enum Config {
    static let nutritionixAppID  = "YOUR_APP_ID"
    static let nutritionixAppKey = "YOUR_APP_KEY"
}
```

**`Config.example.swift.txt`** (committed — `.txt` so it is not compiled):
```
// Copy this file to Config.swift and fill in your Nutritionix credentials.
// Get keys at: https://developer.nutritionix.com

enum Config {
    static let nutritionixAppID  = "<your-nutritionix-app-id>"
    static let nutritionixAppKey = "<your-nutritionix-app-key>"
}
```

**`.gitignore` addition** (repo-root-relative glob, robust to directory moves):
```
**/Config.swift
```

The `**/Config.swift` glob matches only files named exactly `Config.swift`. `Config.example.swift.txt` does not match — it is intentionally committed and safe.

---

## 3. Data Models (`NutritionixModels.swift`)

### 3a. NutritionixFoodItem

The fully-parsed domain struct returned by `naturalLanguageSearch` and `barcodeSearch`. `validation` is computed at parse time — every item has `MacroValidator.validate()` applied before it leaves the service layer.

```swift
struct NutritionixFoodItem {
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

**MacroValidator integration:** Inside the private `parse(_:) -> NutritionixFoodItem` method, after extracting macros from the Nutritionix response:

```swift
let validation = MacroValidator.validate(
    calories: calories, protein: protein, carbs: carbs, fat: fat)
```

Store the result on `NutritionixFoodItem.validation`. Callers read `item.validation.isValid` to decide whether to show a warning in the UI. This is a pre-save advisory check — the save-time flagging in `AddFoodEntryView.save()` is a separate, mandatory persistence-layer check and both must remain.

### 3b. NutritionixSuggestion

Lightweight struct returned by `keywordSearch`. Contains no nutrition data.

```swift
struct NutritionixSuggestion {
    enum Kind { case common, branded }
    let name: String
    let brandName: String?
    let photoURL: URL?
    let kind: Kind
    let nixItemId: String?   // populated for branded items from nix_item_id field
}
```

**Two-step resolution:**
- For `kind == .common`: pass `suggestion.name` to `naturalLanguageSearch(_:)` to fetch full nutrition.
- For `kind == .branded`: pass `suggestion.nixItemId` (if non-nil) to `nixItemIdSearch(id:)`. Passing a branded name to `naturalLanguageSearch` is unreliable — the NLP endpoint may resolve to a different product. `barcodeSearch` is semantically wrong here (it takes a UPC, not a Nutritionix item ID); use `nixItemIdSearch` instead.

### 3c. NutritionixError

```swift
enum NutritionixError: LocalizedError {
    case invalidCredentials          // HTTP 401
    case rateLimitExceeded           // HTTP 429
    case httpError(statusCode: Int)  // other 4xx / 5xx
    case networkFailure(URLError)
    case decodingFailure(DecodingError)
    case noResults
}
```

`rateLimitExceeded` is a first-class case so callers can show a targeted message ("Too many searches — wait a moment") rather than a generic error alert.

### 3d. Internal Codable Types

Internal structs prefixed `NX` decode the raw Nutritionix JSON and are not exposed outside `NutritionixModels.swift`.

```swift
// Shared food struct — used by both /natural/nutrients and /search/item responses
struct NXFood: Decodable {
    let food_name: String
    let brand_name: String?
    let serving_qty: Double
    let serving_unit: String
    let serving_weight_grams: Double?
    let nf_calories: Double?
    let nf_protein: Double?
    let nf_total_carbohydrate: Double?
    let nf_total_fat: Double?
    let photo: NXPhoto?
    let nix_item_id: String?
}

struct NXPhoto: Decodable {
    let thumb: String?
}

// POST /v2/natural/nutrients  →  { "foods": [NXFood] }
struct NXNutrientsResponse: Decodable {
    let foods: [NXFood]
}

// GET /v2/search/item  →  { "foods": [NXFood] }
typealias NXSearchItemResponse = NXNutrientsResponse

// GET /v2/search/instant  →  { "branded": [NXInstantItem], "common": [NXInstantItem] }
struct NXSearchInstantResponse: Decodable {
    let branded: [NXInstantItem]
    let common: [NXInstantItem]
}

struct NXInstantItem: Decodable {
    let food_name: String
    let brand_name: String?
    let photo: NXPhoto?
    let nix_item_id: String?
}
```

Fields that are not present in all contexts (e.g. `nf_calories` missing from instant results) are typed as `Optional`. The `parse(_:)` method uses nil-coalescing for missing values:
- Macro fields (`nf_calories`, `nf_protein`, `nf_total_carbohydrate`, `nf_total_fat`) → default `0.0`
- `serving_weight_grams` → default `0.0` (a defensive fallback; Nutritionix `/v2/search/item` and `/v2/natural/nutrients` always populate this field for real foods)

Nutritionix `/v2/search/item` always populates macro fields for branded items; `0.0` fallbacks are defensive only.

---

## 4. Protocol & Service (`NutritionixService.swift`)

### 4a. Protocol

```swift
protocol NutritionixServiceProtocol: Sendable {
    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem]
    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem
    func nixItemIdSearch(id: String) async throws -> NutritionixFoodItem
    func keywordSearch(query: String) async throws -> [NutritionixSuggestion]
}
```

- `naturalLanguageSearch` — POSTs `{ "query": query }` to `/v2/natural/nutrients`. Returns one `NutritionixFoodItem` per food detected in the query string.
- `barcodeSearch` — GETs `/v2/search/item?upc=<upc>`. Returns the first item from the `foods` array (if `foods.count > 1`, additional results are silently dropped — Nutritionix only returns multiple items for ambiguous UPCs, and the first is the best match). Throws `noResults` if `foods` is empty.
- `nixItemIdSearch` — GETs `/v2/search/item?nix_item_id=<id>`. Same response shape and parsing logic as `barcodeSearch`. Used for resolving branded `NutritionixSuggestion` items from keyword search results. Returns first item or throws `noResults`.
- `keywordSearch` — GETs `/v2/search/instant?query=<query>`. Returns `[NutritionixSuggestion]` by concatenating `common` results first, then `branded` results (common items are typically more relevant for general food queries).

### 4b. Concrete Implementation

```swift
final class NutritionixService: NutritionixServiceProtocol, @unchecked Sendable {
    private let session: URLSession
    private let appID: String
    private let appKey: String

    init(
        session: URLSession = .shared,
        appID: String = Config.nutritionixAppID,
        appKey: String = Config.nutritionixAppKey
    ) {
        self.session = session
        self.appID = appID
        self.appKey = appKey
    }
}
```

`session` is injectable so tests can pass a `URLProtocol`-stubbed session without hitting the network.

### 4c. Private Helpers

**`authorizedRequest(url: URL, method: String, body: Data?) -> URLRequest`**

Constructs a `URLRequest`, sets `httpMethod` to `method`, sets `httpBody` to `body`, and attaches four headers:
- `x-app-id: <appID>`
- `x-app-key: <appKey>`
- `x-remote-user-id: "0"` — required by all Nutritionix v2 endpoints; `"0"` is the conventional anonymous value for development
- `Content-Type: application/json` — added iff `body != nil`

**`perform<T: Decodable>(_ request: URLRequest) async throws -> T`**

Calls `session.data(for:)`, checks the HTTP status code via `mapStatusCode(_:)`, decodes the response body as `T`, and wraps errors:
- `URLError` → `NutritionixError.networkFailure`
- `DecodingError` → `NutritionixError.decodingFailure`

**`mapStatusCode(_ response: HTTPURLResponse) throws`**
- 200–299 → no throw
- 401 → `.invalidCredentials`
- 429 → `.rateLimitExceeded`
- All other codes → `.httpError(statusCode:)`

**`parse(_ nxFood: NXFood) -> NutritionixFoodItem`**

Maps one `NXFood` to a `NutritionixFoodItem`. Missing macro values default to `0.0`. Calls `MacroValidator.validate()` and stores the result.

---

## 5. Tests (`NutritionixServiceTests.swift`)

Two test structs in the same file.

### 5a. MockNutritionixService tests

`MockNutritionixService: NutritionixServiceProtocol` — a `final class` (not a struct; a struct cannot mutate stored injection state through a protocol reference in Swift 6) with stored properties for return values and a thrown error. Verifies that protocol callers handle results and errors correctly:

1. `naturalLanguageSearch` returns caller-supplied items unchanged
2. `barcodeSearch` throws `noResults` when configured to
3. `keywordSearch` returns caller-supplied suggestions with correct `kind`
4. `rateLimitExceeded` propagates to caller
5. `invalidCredentials` propagates to caller
6. Given a stubbed item with `validation.isValid == false` → caller receives an item whose `validation.isValid` is `false` (validates that the `validation` field survives the protocol boundary)

### 5b. NutritionixServiceParsingTests — URLProtocol stub

A custom `URLProtocol` subclass (`StubURLProtocol`) intercepts requests and returns fixture JSON (inline strings defined in the test file). Tests exercise the real `NutritionixService` parsing path:

7. Given valid `/v2/natural/nutrients` fixture JSON → returns `NutritionixFoodItem` with correct `name`, `calories`, `protein`, `carbs`, `fat`
8. Given fixture JSON for an item where macros match calories (within 5 kcal) → `item.validation.isValid == true`
9. Given fixture JSON for an item where calories diverge from macros by >5 kcal → `item.validation.isValid == false`
10. Given valid `/v2/search/item` fixture JSON (UPC lookup) → `barcodeSearch` returns single item with correct fields
11. Given valid `/v2/search/item` fixture JSON (nix_item_id lookup) → `nixItemIdSearch` returns single item
12. Given `/v2/search/item` response with empty `foods` array → throws `noResults`
13. Given valid `/v2/search/instant` fixture JSON → `keywordSearch` returns suggestions with `kind == .branded` for branded entries and `kind == .common` for common entries; branded entries have non-nil `nixItemId`
14. Given HTTP 429 response (any endpoint) → throws `rateLimitExceeded`
15. Given HTTP 401 response (any endpoint) → throws `invalidCredentials`
16. Given a `/v2/natural/nutrients` response body where `food_name` is absent from the `foods[0]` object → throws `decodingFailure` (`food_name` is a required non-optional field; its absence triggers `DecodingError.keyNotFound`, which `perform(_:)` wraps as `.decodingFailure`)

Test cases 7–16 use `StubURLProtocol` injected via:
```swift
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [StubURLProtocol.self]
let session = URLSession(configuration: config)
let service = NutritionixService(session: session, appID: "test", appKey: "test")
```

---

## 6. API Endpoints Reference

Base URL: `https://trackapi.nutritionix.com`

| Method | Endpoint | Auth headers | Notes |
|--------|----------|------|-------|
| POST | `/v2/natural/nutrients` | `x-app-id`, `x-app-key`, `x-remote-user-id` | Body: `{ "query": "2 eggs and toast" }` |
| GET | `/v2/search/item?upc=<code>` | `x-app-id`, `x-app-key`, `x-remote-user-id` | Branded items by UPC |
| GET | `/v2/search/item?nix_item_id=<id>` | `x-app-id`, `x-app-key`, `x-remote-user-id` | Branded item by Nutritionix item ID |
| GET | `/v2/search/instant?query=<term>` | `x-app-id`, `x-app-key`, `x-remote-user-id` | Returns `branded` + `common` arrays |

All requests require `x-app-id`, `x-app-key`, and `x-remote-user-id: "0"` headers.

---

## 7. Verification

1. Build succeeds with `Config.swift` present
2. Build fails with `Config.swift` absent (missing type `Config`)
3. `**/Config.swift` in `.gitignore` keeps the file out of commits even after directory moves
4. `naturalLanguageSearch("2 eggs and toast")` returns 2 items with correct macros and populated `validation`
5. `barcodeSearch("049000028911")` returns a single branded item
6. `nixItemIdSearch("some_nix_id")` returns a single branded item (same parsing path as `barcodeSearch`)
7. `keywordSearch("chicken")` returns suggestions without triggering a nutrition fetch; branded results have non-nil `nixItemId`
8. All 16 unit tests pass with no real network calls
9. HTTP 429 → `rateLimitExceeded`; HTTP 401 → `invalidCredentials`
