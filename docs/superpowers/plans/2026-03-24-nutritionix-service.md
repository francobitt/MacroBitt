# Nutritionix Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a type-safe async/await Nutritionix v2 API client with natural language search, barcode lookup, item ID lookup, and keyword autocomplete — with MacroValidator integration and 16 unit tests covering parsing, validation, and error mapping.

**Architecture:** `NutritionixModels.swift` holds all public domain types and internal Codable types. `NutritionixService.swift` holds the `NutritionixServiceProtocol: Sendable` protocol and the `NutritionixService` concrete class. Tests use `StubURLProtocol` (real parsing path) and `MockNutritionixService` (protocol-level) — no real network calls.

**Tech Stack:** Swift 6, URLSession async/await, Swift Testing (`import Testing`, `#expect`, `#require`)

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create (gitignored) | `MacroBitt/Config.swift` | API credentials |
| Create | `MacroBitt/Config.example.swift.txt` | Setup instructions (`.txt` = never compiled) |
| Create | `MacroBitt/Services/NutritionixModels.swift` | All domain + internal Codable types |
| Create | `MacroBitt/Services/NutritionixService.swift` | Protocol + concrete service |
| Create | `MacroBittTests/NutritionixServiceTests.swift` | 16 unit tests |
| Modify | `.gitignore` | Add `**/Config.swift` |

---

### Task 1: Credentials + .gitignore

**Files:**
- Create: `MacroBitt/Config.swift`
- Create: `MacroBitt/Config.example.swift.txt`
- Modify: `.gitignore`

- [ ] **Step 1: Create Config.swift**

```swift
// MacroBitt/Config.swift
// DO NOT COMMIT — fill in your real Nutritionix keys from developer.nutritionix.com
enum Config {
    static let nutritionixAppID  = "YOUR_APP_ID"
    static let nutritionixAppKey = "YOUR_APP_KEY"
}
```

- [ ] **Step 2: Create Config.example.swift.txt**

File: `MacroBitt/Config.example.swift.txt`
(`.txt` extension — Xcode never compiles this file, so it can coexist with `Config.swift` without a duplicate-type error)

```
// Copy this file to Config.swift and fill in your Nutritionix credentials.
// Get keys at: https://developer.nutritionix.com

enum Config {
    static let nutritionixAppID  = "<your-nutritionix-app-id>"
    static let nutritionixAppKey = "<your-nutritionix-app-key>"
}
```

- [ ] **Step 3: Add to .gitignore**

Append to `.gitignore`:
```
# API credentials — never commit real keys
**/Config.swift
```

`**/Config.swift` matches only files named exactly `Config.swift`. `Config.example.swift.txt` does NOT match.

- [ ] **Step 4: Build to verify**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MacroBitt.xcodeproj \
    -scheme MacroBitt \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MacroBitt/Config.example.swift.txt .gitignore
# Do NOT git add MacroBitt/Config.swift — it is gitignored
git commit -m "feat: add Config credentials setup with gitignore"
```

---

### Task 2: NutritionixModels.swift

**Files:**
- Create: `MacroBitt/Services/NutritionixModels.swift`

- [ ] **Step 1: Create NutritionixModels.swift**

```swift
//
//  NutritionixModels.swift
//  MacroBitt
//

import Foundation

// MARK: - Public Domain Types

struct NutritionixFoodItem {
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let servingQuantity: Double       // e.g. 1.0
    let servingUnit: String           // e.g. "cup"
    let servingWeightGrams: Double    // gram weight of one serving, e.g. 240.0
    let photoURL: URL?
    let brandName: String?            // nil for unbranded (common) foods
    let validation: MacroValidator.Result
}

struct NutritionixSuggestion {
    // Equatable so tests can use #expect(kind == .common)
    enum Kind: Equatable { case common, branded }
    let name: String
    let brandName: String?
    let photoURL: URL?
    let kind: Kind
    let nixItemId: String?   // use with nixItemIdSearch for branded items
}

enum NutritionixError: LocalizedError {
    case invalidCredentials          // HTTP 401
    case rateLimitExceeded           // HTTP 429
    case httpError(statusCode: Int)  // other 4xx / 5xx
    case networkFailure(URLError)
    case decodingFailure(DecodingError)
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:    return "Invalid API credentials."
        case .rateLimitExceeded:     return "Too many requests — please wait a moment."
        case .httpError(let code):   return "Server error (HTTP \(code))."
        case .networkFailure(let e): return e.localizedDescription
        case .decodingFailure:       return "Unexpected response from server."
        case .noResults:             return "No results found."
        }
    }
}

// MARK: - Internal Codable Types
// Decode raw Nutritionix JSON. Not exposed outside this module.

struct NXFood: Decodable {
    let food_name: String           // non-optional — required field; absence throws DecodingError
    let brand_name: String?
    let serving_qty: Double?        // optional defensive; always present for real API responses
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

// POST /v2/natural/nutrients  →  { "foods": [...] }
struct NXNutrientsResponse: Decodable {
    let foods: [NXFood]
}

// GET /v2/search/item  →  { "foods": [...] }
typealias NXSearchItemResponse = NXNutrientsResponse

// GET /v2/search/instant  →  { "common": [...], "branded": [...] }
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
git add MacroBitt/Services/NutritionixModels.swift
git commit -m "feat: add NutritionixModels — domain types, NutritionixError, internal NX Codable types"
```

---

### Task 3: NutritionixService.swift skeleton + write all tests

**Files:**
- Create: `MacroBitt/Services/NutritionixService.swift`
- Create: `MacroBittTests/NutritionixServiceTests.swift`

Create a skeleton service (stubs all methods so the test file compiles), then write all 16 tests. Group A mock tests will pass immediately. Group B parsing tests will fail (stubs throw `noResults`). That failure is the expected TDD red state.

- [ ] **Step 1: Create NutritionixService.swift skeleton**

```swift
//
//  NutritionixService.swift
//  MacroBitt
//

import Foundation

// MARK: - Protocol

protocol NutritionixServiceProtocol: Sendable {
    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem]
    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem
    func nixItemIdSearch(id: String) async throws -> NutritionixFoodItem
    func keywordSearch(query: String) async throws -> [NutritionixSuggestion]
}

// MARK: - Concrete Implementation

final class NutritionixService: NutritionixServiceProtocol, @unchecked Sendable {

    private static let baseURL = "https://trackapi.nutritionix.com"

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

    // MARK: - Public Methods (stubs — implemented in Task 4)

    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem] {
        throw NutritionixError.noResults
    }

    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem {
        throw NutritionixError.noResults
    }

    func nixItemIdSearch(id: String) async throws -> NutritionixFoodItem {
        throw NutritionixError.noResults
    }

    func keywordSearch(query: String) async throws -> [NutritionixSuggestion] {
        throw NutritionixError.noResults
    }

    // MARK: - Private Helpers (stubs — implemented in Task 4)

    private func authorizedRequest(url: URL, method: String, body: Data?) -> URLRequest {
        URLRequest(url: url)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        throw NutritionixError.noResults
    }

    private func mapStatusCode(_ response: HTTPURLResponse) throws {}

    private func parse(_ nxFood: NXFood) -> NutritionixFoodItem {
        NutritionixFoodItem(
            name: "", calories: 0, protein: 0, carbs: 0, fat: 0,
            servingQuantity: 0, servingUnit: "", servingWeightGrams: 0,
            photoURL: nil, brandName: nil,
            validation: MacroValidator.validate(calories: 0, protein: 0, carbs: 0, fat: 0)
        )
    }
}
```

- [ ] **Step 2: Create NutritionixServiceTests.swift with all 16 tests**

```swift
//
//  NutritionixServiceTests.swift
//  MacroBittTests
//

import Testing
import Foundation
@testable import MacroBitt

// MARK: - StubURLProtocol
// Intercepts URLSession requests. Set stubbedResponse before the service call,
// clear it in a defer block. One test → one request → one stub.

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var stubbedResponse: (Data, URLResponse)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let (data, response) = StubURLProtocol.stubbedResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func stub(json: String, statusCode: Int = 200) {
        let data = Data(json.utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://stub.test")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        stubbedResponse = (data, response)
    }
}

// MARK: - Service factory for stub tests

private func makeStubService() -> NutritionixService {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return NutritionixService(session: URLSession(configuration: config),
                              appID: "test", appKey: "test")
}

// MARK: - Fixture JSON

// (fat=5)×9 + (carbs=0.4)×4 + (protein=6)×4 = 45+1.6+24 = 70.6 kcal
// calories=72 → diff=1.4 ≤ 5 → isValid = true
private let validNutrientsJSON = """
{
  "foods": [{
    "food_name": "egg",
    "brand_name": null,
    "serving_qty": 1.0,
    "serving_unit": "large",
    "serving_weight_grams": 50.0,
    "nf_calories": 72.0,
    "nf_protein": 6.0,
    "nf_total_carbohydrate": 0.4,
    "nf_total_fat": 5.0,
    "photo": {"thumb": "https://example.com/egg.jpg"},
    "nix_item_id": null
  }]
}
"""

// (fat=2)×9 + (carbs=0.4)×4 + (protein=6)×4 = 18+1.6+24 = 43.6 kcal
// calories=200 → diff=156.4 > 5 → isValid = false
private let mismatchedMacrosJSON = """
{
  "foods": [{
    "food_name": "test_food",
    "brand_name": null,
    "serving_qty": 1.0,
    "serving_unit": "serving",
    "serving_weight_grams": 50.0,
    "nf_calories": 200.0,
    "nf_protein": 6.0,
    "nf_total_carbohydrate": 0.4,
    "nf_total_fat": 2.0,
    "photo": null,
    "nix_item_id": null
  }]
}
"""

private let barcodeItemJSON = """
{
  "foods": [{
    "food_name": "Coca-Cola",
    "brand_name": "Coca-Cola",
    "serving_qty": 1.0,
    "serving_unit": "can",
    "serving_weight_grams": 355.0,
    "nf_calories": 140.0,
    "nf_protein": 0.0,
    "nf_total_carbohydrate": 39.0,
    "nf_total_fat": 0.0,
    "photo": null,
    "nix_item_id": "coke_nix_123"
  }]
}
"""

private let emptyFoodsJSON = """
{"foods": []}
"""

private let instantSearchJSON = """
{
  "common": [
    {"food_name": "chicken breast", "brand_name": null, "photo": null, "nix_item_id": null}
  ],
  "branded": [
    {"food_name": "Chicken McNuggets", "brand_name": "McDonald's", "photo": null, "nix_item_id": "nix_mcnuggets_123"}
  ]
}
"""

// food_name is non-optional in NXFood — absence triggers DecodingError.keyNotFound
private let missingFoodNameJSON = """
{
  "foods": [{
    "serving_qty": 1.0,
    "serving_unit": "serving",
    "serving_weight_grams": 50.0,
    "nf_calories": 72.0
  }]
}
"""

// MARK: - MockNutritionixService
// final class (not struct) — a struct cannot mutate stored properties
// through a Sendable protocol reference in Swift 6.

final class MockNutritionixService: NutritionixServiceProtocol, @unchecked Sendable {
    var stubbedItems: [NutritionixFoodItem] = []
    var stubbedSuggestions: [NutritionixSuggestion] = []
    var errorToThrow: (any Error)?

    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem] {
        if let error = errorToThrow { throw error }
        return stubbedItems
    }
    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem {
        if let error = errorToThrow { throw error }
        guard let first = stubbedItems.first else { throw NutritionixError.noResults }
        return first
    }
    func nixItemIdSearch(id: String) async throws -> NutritionixFoodItem {
        if let error = errorToThrow { throw error }
        guard let first = stubbedItems.first else { throw NutritionixError.noResults }
        return first
    }
    func keywordSearch(query: String) async throws -> [NutritionixSuggestion] {
        if let error = errorToThrow { throw error }
        return stubbedSuggestions
    }
}

// MARK: - Group A: MockNutritionixService Tests (tests 1–6)

struct MockNutritionixServiceTests {

    // Helpers for building test items
    private func makeItem(calories: Double = 410, protein: Double = 30,
                          carbs: Double = 50, fat: Double = 10) -> NutritionixFoodItem {
        NutritionixFoodItem(
            name: "Test Food", calories: calories, protein: protein,
            carbs: carbs, fat: fat, servingQuantity: 1.0,
            servingUnit: "serving", servingWeightGrams: 100.0,
            photoURL: nil, brandName: nil,
            validation: MacroValidator.validate(calories: calories,
                                                protein: protein, carbs: carbs, fat: fat)
        )
    }

    // 1. naturalLanguageSearch returns caller-supplied items
    @Test func naturalLanguageSearch_returnsStubbedItems() async throws {
        let mock = MockNutritionixService()
        mock.stubbedItems = [makeItem()]
        let results = try await mock.naturalLanguageSearch(query: "anything")
        #expect(results.count == 1)
        #expect(results[0].name == "Test Food")
    }

    // 2. barcodeSearch throws noResults when configured
    @Test func barcodeSearch_throwsConfiguredNoResults() async throws {
        let mock = MockNutritionixService()
        mock.errorToThrow = NutritionixError.noResults
        var threw = false
        do { _ = try await mock.barcodeSearch(upc: "000000000000") }
        catch NutritionixError.noResults { threw = true }
        #expect(threw)
    }

    // 3. keywordSearch returns suggestions with correct kind values
    @Test func keywordSearch_returnsSuggestionsWithCorrectKind() async throws {
        let mock = MockNutritionixService()
        mock.stubbedSuggestions = [
            NutritionixSuggestion(name: "apple", brandName: nil,
                                  photoURL: nil, kind: .common, nixItemId: nil),
            NutritionixSuggestion(name: "Apple Juice", brandName: "Tropicana",
                                  photoURL: nil, kind: .branded, nixItemId: "nix_123")
        ]
        let results = try await mock.keywordSearch(query: "apple")
        #expect(results.count == 2)
        #expect(results[0].kind == .common)
        #expect(results[1].kind == .branded)
        #expect(results[1].nixItemId == "nix_123")
    }

    // 4. rateLimitExceeded propagates to caller
    @Test func rateLimitExceeded_propagatesToCaller() async throws {
        let mock = MockNutritionixService()
        mock.errorToThrow = NutritionixError.rateLimitExceeded
        var threw = false
        do { _ = try await mock.naturalLanguageSearch(query: "anything") }
        catch NutritionixError.rateLimitExceeded { threw = true }
        #expect(threw)
    }

    // 5. invalidCredentials propagates to caller
    @Test func invalidCredentials_propagatesToCaller() async throws {
        let mock = MockNutritionixService()
        mock.errorToThrow = NutritionixError.invalidCredentials
        var threw = false
        do { _ = try await mock.barcodeSearch(upc: "000000000000") }
        catch NutritionixError.invalidCredentials { threw = true }
        #expect(threw)
    }

    // 6. validation.isValid == false survives the protocol boundary
    @Test func validationField_survivesProtocolBoundary() async throws {
        let mock = MockNutritionixService()
        // calories=600 but macros sum to 410 → diff=190 → isValid=false
        mock.stubbedItems = [makeItem(calories: 600)]
        let results = try await mock.naturalLanguageSearch(query: "anything")
        #expect(results[0].validation.isValid == false)
        #expect(results[0].validation.difference == 190.0)
    }
}

// MARK: - Group B: Real Parsing Tests via StubURLProtocol (tests 7–16)

struct NutritionixServiceParsingTests {

    // 7. naturalLanguageSearch parses all fields correctly
    @Test func naturalLanguageSearch_parsesFieldsCorrectly() async throws {
        defer { StubURLProtocol.stubbedResponse = nil }
        StubURLProtocol.stub(json: validNutrientsJSON)
        let items = try await makeStubService().naturalLanguageSearch(query: "egg")
        #expect(items.count == 1)
        let item = items[0]
        #expect(item.name == "egg")
        #expect(item.calories == 72.0)
        #expect(item.protein == 6.0)
        #expect(item.carbs == 0.4)
        #expect(item.fat == 5.0)
        #expect(item.servingQuantity == 1.0)
        #expect(item.servingUnit == "large")
        #expect(item.servingWeightGrams == 50.0)
        #expect(item.photoURL?.absoluteString == "https://example.com/egg.jpg")
        #expect(item.brandName == nil)
    }

    // 8. matching macros → validation.isValid == true
    @Test func naturalLanguageSearch_matchingMacros_isValidTrue() async throws {
        defer { StubURLProtocol.stubbedResponse = nil }
        StubURLProtocol.stub(json: validNutrientsJSON)  // diff = 1.4 ≤ 5
        let items = try await makeStubService().naturalLanguageSearch(query: "egg")
        #expect(items[0].validation.isValid == true)
    }

    // 9. mismatched macros → validation.isValid == false
    @Test func naturalLanguageSearch_mismatchedMacros_isValidFalse() async throws {
        defer { StubURLProtocol.stubbedResponse = nil }
        StubURLProtocol.stub(json: mismatchedMacrosJSON)  // diff = 156.4 > 5
        let items = try await makeStubService().naturalLanguageSearch(query: "test")
        #expect(items[0].validation.isValid == false)
    }

    // 10. barcodeSearch returns correctly parsed item
    @Test func barcodeSearch_parsesFieldsCorrectly() async throws {
        defer { StubURLProtocol.stubbedResponse = nil }
        StubURLProtocol.stub(json: barcodeItemJSON)
        let item = try await makeStubService().barcodeSearch(upc: "049000028911")
        #expect(item.name == "Coca-Cola")
        #expect(item.brandName == "Coca-Cola")
        #expect(item.calories == 140.0)
        #expect(item.servingUnit == "can")
    }

    // 11. nixItemIdSearch returns correctly parsed item (same response shape as barcodeSearch)
    @Test func nixItemIdSearch_parsesFieldsCorrectly() async throws {
        defer { StubURLProtocol.stubbedResponse = nil }
        StubURLProtocol.stub(json: barcodeItemJSON)
        let item = try await makeStubService().nixItemIdSearch(id: "coke_nix_123")
        #expect(item.name == "Coca-Cola")
        #expect(item.brandName == "Coca-Cola")
    }

    // 12. empty foods array → throws noResults
    @Test func barcodeSearch_emptyFoods_throwsNoResults() async throws {
        defer { StubURLProtocol.stubbedResponse = nil }
        StubURLProtocol.stub(json: emptyFoodsJSON)
        var threw = false
        do { _ = try await makeStubService().barcodeSearch(upc: "000000000000") }
        catch NutritionixError.noResults { threw = true }
        #expect(threw)
    }

    // 13. keywordSearch returns common-first, then branded; branded has nixItemId
    @Test func keywordSearch_returnsSuggestionsInOrder() async throws {
        defer { StubURLProtocol.stubbedResponse = nil }
        StubURLProtocol.stub(json: instantSearchJSON)
        let suggestions = try await makeStubService().keywordSearch(query: "chicken")
        #expect(suggestions.count == 2)
        #expect(suggestions[0].kind == .common)
        #expect(suggestions[0].name == "chicken breast")
        #expect(suggestions[1].kind == .branded)
        #expect(suggestions[1].name == "Chicken McNuggets")
        #expect(suggestions[1].nixItemId == "nix_mcnuggets_123")
        #expect(suggestions[1].brandName == "McDonald's")
    }

    // 14. HTTP 429 → rateLimitExceeded
    @Test func http429_throwsRateLimitExceeded() async throws {
        defer { StubURLProtocol.stubbedResponse = nil }
        StubURLProtocol.stub(json: "{}", statusCode: 429)
        var threw = false
        do { _ = try await makeStubService().naturalLanguageSearch(query: "anything") }
        catch NutritionixError.rateLimitExceeded { threw = true }
        #expect(threw)
    }

    // 15. HTTP 401 → invalidCredentials
    @Test func http401_throwsInvalidCredentials() async throws {
        defer { StubURLProtocol.stubbedResponse = nil }
        StubURLProtocol.stub(json: "{}", statusCode: 401)
        var threw = false
        do { _ = try await makeStubService().naturalLanguageSearch(query: "anything") }
        catch NutritionixError.invalidCredentials { threw = true }
        #expect(threw)
    }

    // 16. Missing food_name (required field) → decodingFailure
    // food_name is non-optional in NXFood; absence triggers DecodingError.keyNotFound
    // which perform(_:) wraps as NutritionixError.decodingFailure
    @Test func missingFoodName_throwsDecodingFailure() async throws {
        defer { StubURLProtocol.stubbedResponse = nil }
        StubURLProtocol.stub(json: missingFoodNameJSON)
        var threw = false
        do { _ = try await makeStubService().naturalLanguageSearch(query: "anything") }
        catch NutritionixError.decodingFailure { threw = true }
        #expect(threw)
    }
}
```

- [ ] **Step 3: Build and run tests — confirm Group A passes, Group B (parsing) fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
    -project MacroBitt.xcodeproj \
    -scheme MacroBittTests \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    2>&1 | grep -E "passed|failed|error:|BUILD"
```

Expected:
- `MockNutritionixServiceTests` — all 6 pass
- `NutritionixServiceParsingTests` — most fail (stubs throw `noResults`)
- No `error:` lines (the test file itself compiles cleanly)

- [ ] **Step 4: Commit skeleton + tests**

```bash
git add MacroBitt/Services/NutritionixService.swift MacroBittTests/NutritionixServiceTests.swift
git commit -m "feat: add NutritionixService skeleton and all 16 unit tests (Group B red)"
```

---

### Task 4: Implement NutritionixService — make all tests green

**Files:**
- Modify: `MacroBitt/Services/NutritionixService.swift`

Replace the entire file contents (keeping the protocol unchanged, replacing all stubs with real implementations).

- [ ] **Step 1: Replace NutritionixService.swift with full implementation**

```swift
//
//  NutritionixService.swift
//  MacroBitt
//

import Foundation

// MARK: - Protocol

protocol NutritionixServiceProtocol: Sendable {
    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem]
    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem
    func nixItemIdSearch(id: String) async throws -> NutritionixFoodItem
    func keywordSearch(query: String) async throws -> [NutritionixSuggestion]
}

// MARK: - Concrete Implementation

final class NutritionixService: NutritionixServiceProtocol, @unchecked Sendable {

    private static let baseURL = "https://trackapi.nutritionix.com"

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

    // MARK: - Public Methods

    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem] {
        let url = URL(string: "\(Self.baseURL)/v2/natural/nutrients")!
        let body = try JSONEncoder().encode(["query": query])
        let request = authorizedRequest(url: url, method: "POST", body: body)
        let response: NXNutrientsResponse = try await perform(request)
        return response.foods.map(parse)
    }

    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem {
        var comps = URLComponents(string: "\(Self.baseURL)/v2/search/item")!
        comps.queryItems = [URLQueryItem(name: "upc", value: upc)]
        let request = authorizedRequest(url: comps.url!, method: "GET", body: nil)
        let response: NXSearchItemResponse = try await perform(request)
        guard let first = response.foods.first else { throw NutritionixError.noResults }
        return parse(first)
    }

    func nixItemIdSearch(id: String) async throws -> NutritionixFoodItem {
        var comps = URLComponents(string: "\(Self.baseURL)/v2/search/item")!
        comps.queryItems = [URLQueryItem(name: "nix_item_id", value: id)]
        let request = authorizedRequest(url: comps.url!, method: "GET", body: nil)
        let response: NXSearchItemResponse = try await perform(request)
        guard let first = response.foods.first else { throw NutritionixError.noResults }
        return parse(first)
    }

    func keywordSearch(query: String) async throws -> [NutritionixSuggestion] {
        var comps = URLComponents(string: "\(Self.baseURL)/v2/search/instant")!
        comps.queryItems = [URLQueryItem(name: "query", value: query)]
        let request = authorizedRequest(url: comps.url!, method: "GET", body: nil)
        let response: NXSearchInstantResponse = try await perform(request)
        // Common-first, then branded (spec §4a)
        let common = response.common.map {
            NutritionixSuggestion(name: $0.food_name, brandName: $0.brand_name,
                                  photoURL: $0.photo?.thumb.flatMap(URL.init),
                                  kind: .common, nixItemId: $0.nix_item_id)
        }
        let branded = response.branded.map {
            NutritionixSuggestion(name: $0.food_name, brandName: $0.brand_name,
                                  photoURL: $0.photo?.thumb.flatMap(URL.init),
                                  kind: .branded, nixItemId: $0.nix_item_id)
        }
        return common + branded
    }

    // MARK: - Private Helpers

    private func authorizedRequest(url: URL, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(appID,  forHTTPHeaderField: "x-app-id")
        request.setValue(appKey, forHTTPHeaderField: "x-app-key")
        request.setValue("0",    forHTTPHeaderField: "x-remote-user-id")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw NutritionixError.networkFailure(urlError)
        }
        if let http = urlResponse as? HTTPURLResponse {
            try mapStatusCode(http)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let decodeError as DecodingError {
            throw NutritionixError.decodingFailure(decodeError)
        }
    }

    private func mapStatusCode(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299: return
        case 401:       throw NutritionixError.invalidCredentials
        case 429:       throw NutritionixError.rateLimitExceeded
        default:        throw NutritionixError.httpError(statusCode: response.statusCode)
        }
    }

    private func parse(_ nxFood: NXFood) -> NutritionixFoodItem {
        let calories = nxFood.nf_calories ?? 0.0
        let protein  = nxFood.nf_protein ?? 0.0
        let carbs    = nxFood.nf_total_carbohydrate ?? 0.0
        let fat      = nxFood.nf_total_fat ?? 0.0
        return NutritionixFoodItem(
            name:               nxFood.food_name,
            calories:           calories,
            protein:            protein,
            carbs:              carbs,
            fat:                fat,
            servingQuantity:    nxFood.serving_qty ?? 0.0,
            servingUnit:        nxFood.serving_unit,
            servingWeightGrams: nxFood.serving_weight_grams ?? 0.0,
            photoURL:           nxFood.photo?.thumb.flatMap(URL.init),
            brandName:          nxFood.brand_name,
            validation:         MacroValidator.validate(
                                    calories: calories, protein: protein,
                                    carbs: carbs, fat: fat)
        )
    }
}
```

- [ ] **Step 2: Run all tests — expect all 16 to pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
    -project MacroBitt.xcodeproj \
    -scheme MacroBittTests \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    2>&1 | grep -E "passed|failed|error:|BUILD"
```

Expected: All 16 `NutritionixServiceTests` pass. `MacroValidatorTests` (6) still pass. Total: 22 tests.

- [ ] **Step 3: Build the app scheme**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MacroBitt.xcodeproj \
    -scheme MacroBitt \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Verify Config.swift is gitignored**

```bash
git status MacroBitt/Config.swift
```

Expected: file does NOT appear in output (gitignored).

- [ ] **Step 5: Commit**

```bash
git add MacroBitt/Services/NutritionixService.swift
git commit -m "feat: implement NutritionixService — all 16 tests passing"
```

---

### Task 5: Commit plan doc

- [ ] **Step 1: Commit the plan**

```bash
git add docs/superpowers/plans/2026-03-24-nutritionix-service.md
git commit -m "docs: add NutritionixService implementation plan"
```
