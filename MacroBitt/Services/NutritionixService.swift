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
