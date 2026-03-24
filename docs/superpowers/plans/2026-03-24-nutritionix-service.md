# NutritionixService Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully-tested Nutritionix v2 API service layer with credential management, three search methods, a common parsed result type, and mandatory MacroValidator integration on every result.

**Architecture:** `NutritionixServiceProtocol` (Sendable) + concrete `NutritionixService` (URLSession-injectable, `@unchecked Sendable`) live in `Services/`. All domain types and internal Codable structs live in `NutritionixModels.swift`. Tests use a `URLProtocol` stub for the concrete class and a `MockNutritionixService` for protocol-level tests — no real network calls.

**Tech Stack:** Swift 6, async/await, Foundation (URLSession, JSONDecoder), Swift Testing (`import Testing`, `@Test`, `#expect`)

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create (gitignored) | `MacroBitt/Config.swift` | Real API credentials |
| Create (checked in) | `Config.example.swift` (repo root) | Credential template |
| Modify | `.gitignore` | Add `MacroBitt/Config.swift` |
| Create | `MacroBitt/Services/NutritionixModels.swift` | Domain types + internal Codable structs |
| Create | `MacroBitt/Services/NutritionixService.swift` | Protocol + concrete service |
| Create | `MacroBittTests/NutritionixServiceTests.swift` | 14 unit tests (5 Group A mock + 9 Group B URLStub) |

---

### Task 1: Credentials + .gitignore

**Files:**
- Create: `MacroBitt/Config.swift`
- Create: `Config.example.swift` (repo root)
- Modify: `.gitignore`

- [ ] **Step 1: Create `MacroBitt/Config.swift`**

```swift
//
//  Config.swift
//  MacroBitt
//
//  DO NOT COMMIT — fill in real credentials from your Nutritionix dashboard.
//

enum Config {
    static let nutritionixAppID  = "your-app-id-here"
    static let nutritionixAppKey = "your-app-key-here"
}
```

- [ ] **Step 2: Create `Config.example.swift` at the repo root (NOT inside `MacroBitt/`)**

This file is a template only. It must live at the repo root so it is never picked up by the Xcode build target (which uses `PBXFileSystemSynchronizedRootGroup` on `MacroBitt/`). If it were inside `MacroBitt/`, both files would declare `enum Config` and cause a duplicate-symbol compile error.

```swift
// Config.example.swift — repo root
// Copy to MacroBitt/Config.swift and fill in real credentials.
// NEVER commit MacroBitt/Config.swift.
//
// Get credentials at: https://developer.nutritionix.com
enum Config {
    static let nutritionixAppID  = "REPLACE_ME"
    static let nutritionixAppKey = "REPLACE_ME"
}
```

- [ ] **Step 3: Add `MacroBitt/Config.swift` to `.gitignore`**

Append to the existing `.gitignore`:

```
# API credentials — never commit
MacroBitt/Config.swift
```

- [ ] **Step 4: Build to verify `Config` is found**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MacroBitt.xcodeproj \
    -scheme MacroBitt \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Verify `Config.swift` is gitignored**

```bash
git status
```

Expected: `Config.swift` does NOT appear in the output. `Config.example.swift` DOES appear as an untracked file.

- [ ] **Step 6: Commit**

```bash
git add .gitignore Config.example.swift
git commit -m "chore: add credential scaffolding (Config.example.swift + gitignore rule)"
```

---

### Task 2: NutritionixModels.swift

**Files:**
- Create: `MacroBitt/Services/NutritionixModels.swift`

- [ ] **Step 1: Create the file**

```swift
//
//  NutritionixModels.swift
//  MacroBitt
//

import Foundation

// MARK: - Public domain types

struct NutritionixFoodItem: Sendable {
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let servingQuantity: Double    // e.g. 1.0
    let servingUnit: String        // e.g. "cup"
    let servingSize: Double        // weight in grams
    let photoURL: URL?
    let brandName: String?         // nil for common (unbranded) foods
    let validation: MacroValidator.Result
    // Note: MacroValidator.Result is a struct of Bool + Double, so it is
    // implicitly Sendable. If that struct ever gains a non-Sendable field,
    // this conformance will need to be revisited.
}

struct NutritionixSuggestion: Sendable {
    enum Kind: Sendable { case common, branded }
    let name: String
    let brandName: String?
    let photoURL: URL?
    let kind: Kind
}

enum NutritionixError: Error, LocalizedError, Sendable {
    case invalidCredentials          // HTTP 401
    case rateLimitExceeded           // HTTP 429
    case httpError(statusCode: Int)  // other 4xx / 5xx
    case networkFailure(URLError)
    case decodingFailure(DecodingError)
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:        return "Invalid API credentials."
        case .rateLimitExceeded:         return "Too many requests — please wait a moment."
        case .httpError(let code):       return "Server error (HTTP \(code))."
        case .networkFailure(let err):   return err.localizedDescription
        case .decodingFailure:           return "Unexpected response format."
        case .noResults:                 return "No results found."
        }
    }
}

extension NutritionixError: Equatable {
    static func == (lhs: NutritionixError, rhs: NutritionixError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidCredentials, .invalidCredentials),
             (.rateLimitExceeded, .rateLimitExceeded),
             (.noResults, .noResults),
             (.decodingFailure, .decodingFailure):
            return true
        case (.httpError(let a), .httpError(let b)):
            return a == b
        case (.networkFailure(let a), .networkFailure(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Internal Codable types (Nutritionix wire format)
// These are not exposed through the protocol. Field names mirror Nutritionix's
// snake_case JSON directly to avoid CodingKeys boilerplate.

struct NXPhoto: Codable {
    let thumb: String?
}

/// Shared food shape returned by both /v2/natural/nutrients and /v2/search/item
struct NXFood: Codable {
    let food_name: String?
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

/// Response from POST /v2/natural/nutrients
struct NXNaturalResponse: Codable {
    let foods: [NXFood]
}

/// Response from GET /v2/search/item?upc=
struct NXSearchItemResponse: Codable {
    let foods: [NXFood]
}

/// Single autocomplete suggestion from /v2/search/instant
struct NXInstantItem: Codable {
    let food_name: String
    let brand_name: String?
    let photo: NXPhoto?
}

/// Response from GET /v2/search/instant?query=
/// Both arrays are optional — Nutritionix omits them when there are no matches.
struct NXInstantResponse: Codable {
    let common: [NXInstantItem]?
    let branded: [NXInstantItem]?
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
git commit -m "feat: add NutritionixModels — domain types and Codable wire structs"
```

---

### Task 3: NutritionixService.swift — protocol + skeleton

Create a skeleton that compiles and satisfies the protocol so tests can be written against it in the next task.

**Files:**
- Create: `MacroBitt/Services/NutritionixService.swift`

- [ ] **Step 1: Create the file with a stub implementation**

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
    func keywordSearch(query: String) async throws -> [NutritionixSuggestion]
}

// MARK: - Concrete service

final class NutritionixService: NutritionixServiceProtocol, @unchecked Sendable {

    private let session: URLSession
    private let appID: String
    private let appKey: String

    private static let baseURL = "https://trackapi.nutritionix.com"

    init(session: URLSession = .shared,
         appID: String = Config.nutritionixAppID,
         appKey: String = Config.nutritionixAppKey) {
        self.session = session
        self.appID = appID
        self.appKey = appKey
    }

    // MARK: - Public methods (stubbed — implemented in Task 5)

    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem] {
        throw NutritionixError.noResults
    }

    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem {
        throw NutritionixError.noResults
    }

    func keywordSearch(query: String) async throws -> [NutritionixSuggestion] {
        throw NutritionixError.noResults
    }

    // MARK: - Private helpers

    private func authorizedRequest(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(appID, forHTTPHeaderField: "x-app-id")
        request.setValue(appKey, forHTTPHeaderField: "x-app-key")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw NutritionixError.networkFailure(urlError)
        }
        guard let http = response as? HTTPURLResponse else {
            throw NutritionixError.httpError(statusCode: 0)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw mapHTTPError(http)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let decodingError as DecodingError {
            throw NutritionixError.decodingFailure(decodingError)
        }
    }

    private func mapHTTPError(_ response: HTTPURLResponse) -> NutritionixError {
        switch response.statusCode {
        case 401: return .invalidCredentials
        case 429: return .rateLimitExceeded
        default:  return .httpError(statusCode: response.statusCode)
        }
    }

    private func parse(_ item: NXFood) -> NutritionixFoodItem {
        let cal  = item.nf_calories ?? 0
        let prot = item.nf_protein ?? 0
        let carb = item.nf_total_carbohydrate ?? 0
        let fat  = item.nf_total_fat ?? 0
        return NutritionixFoodItem(
            name:            item.food_name ?? "",
            calories:        cal,
            protein:         prot,
            carbs:           carb,
            fat:             fat,
            servingQuantity: item.serving_qty ?? 1,
            servingUnit:     item.serving_unit ?? "serving",
            servingSize:     item.serving_weight_grams ?? 0,
            photoURL:        item.photo?.thumb.flatMap { URL(string: $0) },
            brandName:       item.brand_name,
            validation:      MacroValidator.validate(calories: cal, protein: prot,
                                                     carbs: carb, fat: fat)
        )
    }

    private func parseSuggestion(_ item: NXInstantItem,
                                  kind: NutritionixSuggestion.Kind) -> NutritionixSuggestion {
        NutritionixSuggestion(
            name:      item.food_name,
            brandName: item.brand_name,
            photoURL:  item.photo?.thumb.flatMap { URL(string: $0) },
            kind:      kind
        )
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
git add MacroBitt/Services/NutritionixService.swift
git commit -m "feat: add NutritionixService skeleton — protocol + stub methods"
```

---

### Task 4: Write tests (Group B — concrete service, failing)

Group B tests exercise the real `NutritionixService` via a `URLProtocol` stub. They will **fail** after this task because the service methods still throw `noResults`. That is expected — this is the TDD failing phase.

> **Note on Group A tests (Task 6):** Group A tests use `MockNutritionixService` — a hand-written struct that trivially satisfies the protocol. Protocol-level mock tests pass immediately by construction and do not go through a failing phase. They verify the protocol contract and error propagation, not the implementation internals. Only Group B tests drive implementation via a failing cycle.

**Files:**
- Create: `MacroBittTests/NutritionixServiceTests.swift`

- [ ] **Step 1: Create the test file with the URLProtocol stub and Group B tests**

```swift
//
//  NutritionixServiceTests.swift
//  MacroBittTests
//

import Testing
import Foundation
@testable import MacroBitt

// MARK: - URLProtocol stub
// Intercepts all requests made through a configured URLSession and returns
// static data + status code. Tests using this stub must run serially
// (see @Suite(.serialized) below) to avoid races on the static properties.

final class NutritionixURLStub: URLProtocol, @unchecked Sendable {
    static var responseData: Data = Data()
    static var responseCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: NutritionixURLStub.responseCode,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: NutritionixURLStub.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [NutritionixURLStub.self]
    return URLSession(configuration: config)
}

private func makeService(json: String, statusCode: Int = 200) -> NutritionixService {
    NutritionixURLStub.responseData = Data(json.utf8)
    NutritionixURLStub.responseCode = statusCode
    return NutritionixService(session: makeStubSession(), appID: "test-id", appKey: "test-key")
}

// MARK: - JSON fixtures

// P=30×4 + C=50×4 + F=10×9 = 120+200+90 = 410 kcal → valid macros
private let naturalValidJSON = """
{
    "foods": [{
        "food_name": "grilled chicken",
        "brand_name": null,
        "serving_qty": 1.0,
        "serving_unit": "breast",
        "serving_weight_grams": 150.0,
        "nf_calories": 410.0,
        "nf_protein": 30.0,
        "nf_total_carbohydrate": 50.0,
        "nf_total_fat": 10.0,
        "photo": { "thumb": "https://example.com/chicken.jpg" }
    }]
}
"""

// Same macros as above but calories=600 → difference = 600-410 = 190 → invalid
private let naturalMismatchedJSON = """
{
    "foods": [{
        "food_name": "mystery food",
        "brand_name": null,
        "serving_qty": 1.0,
        "serving_unit": "serving",
        "serving_weight_grams": 100.0,
        "nf_calories": 600.0,
        "nf_protein": 30.0,
        "nf_total_carbohydrate": 50.0,
        "nf_total_fat": 10.0,
        "photo": null
    }]
}
"""

// P=6×4 + C=17×4 + F=15×9 = 24+68+135 = 227 kcal → calories matches → valid macros
private let barcodeJSON = """
{
    "foods": [{
        "food_name": "Kind Bar",
        "brand_name": "Kind",
        "serving_qty": 1.0,
        "serving_unit": "bar",
        "serving_weight_grams": 40.0,
        "nf_calories": 227.0,
        "nf_protein": 6.0,
        "nf_total_carbohydrate": 17.0,
        "nf_total_fat": 15.0,
        "photo": null
    }]
}
"""

private let emptyFoodsJSON = """
{ "foods": [] }
"""

// common items come first, branded second in the merged result
private let instantJSON = """
{
    "common": [
        { "food_name": "apple", "brand_name": null, "photo": { "thumb": "https://example.com/apple.jpg" } }
    ],
    "branded": [
        { "food_name": "Apple Juice", "brand_name": "Tropicana", "photo": null }
    ]
}
"""

private let malformedJSON = "{ not valid json !!!"

// MARK: - Group B: Concrete NutritionixService with URLProtocol stub
// Run serially to prevent races on NutritionixURLStub static properties.

@Suite(.serialized)
struct ConcreteNutritionixServiceTests {

    // Test 6
    @Test func naturalLanguageSearch_parsesAllFields() async throws {
        let service = makeService(json: naturalValidJSON)
        let results = try await service.naturalLanguageSearch(query: "grilled chicken")
        #expect(results.count == 1)
        let item = results[0]
        #expect(item.name == "grilled chicken")
        #expect(item.calories == 410)
        #expect(item.protein == 30)
        #expect(item.carbs == 50)
        #expect(item.fat == 10)
        #expect(item.servingQuantity == 1.0)
        #expect(item.servingUnit == "breast")
        #expect(item.servingSize == 150.0)
        #expect(item.photoURL == URL(string: "https://example.com/chicken.jpg"))
        #expect(item.brandName == nil)
    }

    // Test 7
    @Test func naturalLanguageSearch_validMacros_validationIsValid() async throws {
        let service = makeService(json: naturalValidJSON)
        let results = try await service.naturalLanguageSearch(query: "grilled chicken")
        #expect(results[0].validation.isValid)
    }

    // Test 8 — difference = provided(600) − calculated(410) = 190
    @Test func naturalLanguageSearch_mismatchedMacros_validationFails() async throws {
        let service = makeService(json: naturalMismatchedJSON)
        let results = try await service.naturalLanguageSearch(query: "mystery food")
        let item = results[0]
        #expect(!item.validation.isValid)
        #expect(item.validation.difference == 190)
    }

    // Test 9a
    @Test func barcodeSearch_returnsSingleItem() async throws {
        let service = makeService(json: barcodeJSON)
        let item = try await service.barcodeSearch(upc: "602652175561")
        #expect(item.name == "Kind Bar")
        #expect(item.brandName == "Kind")
    }

    // Test 9b
    @Test func barcodeSearch_emptyFoods_throwsNoResults() async throws {
        let service = makeService(json: emptyFoodsJSON)
        await #expect(throws: NutritionixError.noResults) {
            _ = try await service.barcodeSearch(upc: "000000000000")
        }
    }

    // Test 10 — common items first, then branded
    @Test func keywordSearch_combinesCommonAndBrandedInOrder() async throws {
        let service = makeService(json: instantJSON)
        let results = try await service.keywordSearch(query: "apple")
        #expect(results.count == 2)
        #expect(results[0].name == "apple")
        #expect(results[0].kind == .common)
        #expect(results[1].name == "Apple Juice")
        #expect(results[1].kind == .branded)
        #expect(results[1].brandName == "Tropicana")
    }

    // Test 11
    @Test func http429_throwsRateLimitExceeded() async throws {
        let service = makeService(json: "{}", statusCode: 429)
        await #expect(throws: NutritionixError.rateLimitExceeded) {
            _ = try await service.naturalLanguageSearch(query: "pizza")
        }
    }

    // Test 12
    @Test func http401_throwsInvalidCredentials() async throws {
        let service = makeService(json: "{}", statusCode: 401)
        await #expect(throws: NutritionixError.invalidCredentials) {
            _ = try await service.barcodeSearch(upc: "12345")
        }
    }

    // Test 13
    @Test func malformedJSON_throwsDecodingFailure() async throws {
        let service = makeService(json: malformedJSON)
        await #expect {
            _ = try await service.naturalLanguageSearch(query: "test")
        } throws: { error in
            guard let e = error as? NutritionixError,
                  case .decodingFailure = e else { return false }
            return true
        }
    }
}
```

- [ ] **Step 2: Run the tests — verify they fail (not error, but fail)**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
    -project MacroBitt.xcodeproj \
    -scheme MacroBittTests \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    2>&1 | grep -E "passed|failed|error:|BUILD"
```

Expected: `BUILD SUCCEEDED` but the 9 `ConcreteNutritionixServiceTests` cases **fail** (the stub methods throw `.noResults` for everything). This confirms the tests are wired up correctly and are meaningfully failing.

- [ ] **Step 3: Commit the failing test file**

```bash
git add MacroBittTests/NutritionixServiceTests.swift
git commit -m "test: add Group B NutritionixService tests (failing — implementation not yet written)"
```

---

### Task 5: Implement service methods — make Group B tests pass

**Files:**
- Modify: `MacroBitt/Services/NutritionixService.swift`

Replace the three stub methods with real implementations.

- [ ] **Step 1: Replace `naturalLanguageSearch`**

Find and replace the stub:

```swift
    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem] {
        throw NutritionixError.noResults
    }
```

With:

```swift
    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem] {
        let url = URL(string: "\(Self.baseURL)/v2/natural/nutrients")!
        // JSONEncoder().encode([String: String]) cannot fail in practice,
        // but if it does the error propagates as-is (not as NutritionixError).
        let body = try JSONEncoder().encode(["query": query])
        let request = authorizedRequest(url: url, method: "POST", body: body)
        let data = try await perform(request)
        let response = try decode(NXNaturalResponse.self, from: data)
        return response.foods.map { parse($0) }
    }
```

- [ ] **Step 2: Replace `barcodeSearch`**

Find and replace the stub:

```swift
    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem {
        throw NutritionixError.noResults
    }
```

With:

```swift
    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem {
        var components = URLComponents(string: "\(Self.baseURL)/v2/search/item")!
        components.queryItems = [URLQueryItem(name: "upc", value: upc)]
        let request = authorizedRequest(url: components.url!)
        let data = try await perform(request)
        let response = try decode(NXSearchItemResponse.self, from: data)
        guard let first = response.foods.first else { throw NutritionixError.noResults }
        return parse(first)
    }
```

- [ ] **Step 3: Replace `keywordSearch`**

Find and replace the stub:

```swift
    func keywordSearch(query: String) async throws -> [NutritionixSuggestion] {
        throw NutritionixError.noResults
    }
```

With:

```swift
    func keywordSearch(query: String) async throws -> [NutritionixSuggestion] {
        var components = URLComponents(string: "\(Self.baseURL)/v2/search/instant")!
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        let request = authorizedRequest(url: components.url!)
        let data = try await perform(request)
        let response = try decode(NXInstantResponse.self, from: data)
        let common  = (response.common  ?? []).map { parseSuggestion($0, kind: .common)  }
        let branded = (response.branded ?? []).map { parseSuggestion($0, kind: .branded) }
        return common + branded
    }
```

- [ ] **Step 4: Run Group B tests — all 9 should pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
    -project MacroBitt.xcodeproj \
    -scheme MacroBittTests \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    2>&1 | grep -E "passed|failed|error:|BUILD"
```

Expected: All 9 `ConcreteNutritionixServiceTests` cases **pass**. Previously-passing `MacroValidatorTests` still pass.

- [ ] **Step 5: Commit**

```bash
git add MacroBitt/Services/NutritionixService.swift
git commit -m "feat: implement NutritionixService — natural language, barcode, keyword search"
```

---

### Task 6: Add Group A tests (MockNutritionixService)

Group A tests verify the protocol interface works correctly with a mock. They also test that `NutritionixError` propagates through the protocol boundary.

**Files:**
- Modify: `MacroBittTests/NutritionixServiceTests.swift`

- [ ] **Step 1: Add `MockNutritionixService` and Group A tests at the end of the test file**

Append after the closing `}` of `ConcreteNutritionixServiceTests`:

```swift
// MARK: - Mock (Group A)

struct MockNutritionixService: NutritionixServiceProtocol {
    var naturalLanguageResult: [NutritionixFoodItem] = []
    var barcodeResult: NutritionixFoodItem? = nil
    var keywordResult: [NutritionixSuggestion] = []
    var thrownError: (any Error)? = nil

    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem] {
        if let error = thrownError { throw error }
        return naturalLanguageResult
    }

    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem {
        if let error = thrownError { throw error }
        guard let item = barcodeResult else { throw NutritionixError.noResults }
        return item
    }

    func keywordSearch(query: String) async throws -> [NutritionixSuggestion] {
        if let error = thrownError { throw error }
        return keywordResult
    }
}

// MARK: - Fixture for Group A

private let mockFoodItem = NutritionixFoodItem(
    name: "egg",
    calories: 148,
    protein: 10,
    carbs: 2,
    fat: 10,
    servingQuantity: 2,
    servingUnit: "large",
    servingSize: 100,
    photoURL: nil,
    brandName: nil,
    validation: MacroValidator.validate(calories: 148, protein: 10, carbs: 2, fat: 10)
)

// MARK: - Group A: MockNutritionixService protocol tests

struct MockNutritionixServiceTests {

    // Test 1
    @Test func naturalLanguageSearch_returnsConfiguredItems() async throws {
        var mock = MockNutritionixService()
        mock.naturalLanguageResult = [mockFoodItem]
        let results = try await mock.naturalLanguageSearch(query: "2 eggs")
        #expect(results.count == 1)
        #expect(results[0].name == "egg")
    }

    // Test 2
    @Test func barcodeSearch_returnsConfiguredItem() async throws {
        var mock = MockNutritionixService()
        mock.barcodeResult = mockFoodItem
        let item = try await mock.barcodeSearch(upc: "012345678901")
        #expect(item.name == "egg")
    }

    // Test 3
    @Test func barcodeSearch_nilResult_throwsNoResults() async throws {
        let mock = MockNutritionixService()   // barcodeResult is nil by default
        await #expect(throws: NutritionixError.noResults) {
            _ = try await mock.barcodeSearch(upc: "000000000000")
        }
    }

    // Test 4
    @Test func keywordSearch_returnsCorrectKinds() async throws {
        var mock = MockNutritionixService()
        mock.keywordResult = [
            NutritionixSuggestion(name: "apple", brandName: nil, photoURL: nil, kind: .common),
            NutritionixSuggestion(name: "Apple Juice", brandName: "Tropicana", photoURL: nil, kind: .branded)
        ]
        let results = try await mock.keywordSearch(query: "apple")
        #expect(results.count == 2)
        #expect(results[0].kind == .common)
        #expect(results[1].kind == .branded)
        #expect(results[1].brandName == "Tropicana")
    }

    // Test 5
    @Test func thrownError_propagatesToCaller() async throws {
        var mock = MockNutritionixService()
        mock.thrownError = NutritionixError.rateLimitExceeded
        await #expect(throws: NutritionixError.rateLimitExceeded) {
            _ = try await mock.naturalLanguageSearch(query: "chicken")
        }
    }
}
```

- [ ] **Step 2: Run all 14 tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
    -project MacroBitt.xcodeproj \
    -scheme MacroBittTests \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    2>&1 | grep -E "passed|failed|error:|BUILD"
```

Expected: All 14 `NutritionixServiceTests` cases pass (5 `MockNutritionixServiceTests` + 9 `ConcreteNutritionixServiceTests`), plus the 6 existing `MacroValidatorTests`.

- [ ] **Step 3: Commit**

```bash
git add MacroBittTests/NutritionixServiceTests.swift
git commit -m "feat: add Group A mock tests — 14 NutritionixService tests total"
```

---

### Task 7: Final build + verification

- [ ] **Step 1: Full build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project MacroBitt.xcodeproj \
    -scheme MacroBitt \
    -destination 'platform=iOS Simulator,id=83F1370A-8A66-4CC5-9784-3E7B220234F1' \
    build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Verify `Config.swift` is gitignored**

```bash
git status
```

Expected: `MacroBitt/Config.swift` does NOT appear. `Config.example.swift` is already committed.

- [ ] **Step 3: Verify `Config.example.swift` is at repo root (not in build target)**

```bash
ls Config.example.swift
```

Expected: file exists at repo root.

- [ ] **Step 4: Commit `Config.example.swift` if not yet committed**

```bash
git status | grep Config.example
```

If it appears as untracked, commit it:

```bash
git add Config.example.swift
git commit -m "chore: add Config.example.swift to repo root"
```

- [ ] **Step 5: Manual verification checklist**

Run the app (⌘R in Xcode) and verify:

1. App launches without crash
2. All existing tabs (Dashboard, Food Log, Weight, Settings) work as before
3. No regressions in food entry or macro validation

---

## Summary

| Task | Files | Tests |
|------|-------|-------|
| 1 | Config.swift, Config.example.swift, .gitignore | — |
| 2 | NutritionixModels.swift | — |
| 3 | NutritionixService.swift (skeleton) | — |
| 4 | NutritionixServiceTests.swift (Group B, failing) | 9 failing |
| 5 | NutritionixService.swift (full impl) | 9 passing |
| 6 | NutritionixServiceTests.swift (Group A) | +5 = 14 passing |
| 7 | — | 14 + 6 existing = 20 total |
