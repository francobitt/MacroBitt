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
