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
// .serialized prevents parallel execution — StubURLProtocol.stubbedResponse is shared mutable state

@Suite(.serialized)
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
