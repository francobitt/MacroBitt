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
        guard !response.foods.isEmpty else { throw NutritionixError.noResults }
        return response.foods.map { parse($0) }
    }

    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem {
        var components = URLComponents(string: "\(Self.baseURL)/v2/search/item")!
        components.queryItems = [URLQueryItem(name: "upc", value: upc)]
        let request = authorizedRequest(url: components.url!, method: "GET", body: nil)
        let response: NXSearchItemResponse = try await perform(request)
        guard let first = response.foods.first else { throw NutritionixError.noResults }
        return parse(first)
    }

    func nixItemIdSearch(id: String) async throws -> NutritionixFoodItem {
        var components = URLComponents(string: "\(Self.baseURL)/v2/search/item")!
        components.queryItems = [URLQueryItem(name: "nix_item_id", value: id)]
        let request = authorizedRequest(url: components.url!, method: "GET", body: nil)
        let response: NXSearchItemResponse = try await perform(request)
        guard let first = response.foods.first else { throw NutritionixError.noResults }
        return parse(first)
    }

    func keywordSearch(query: String) async throws -> [NutritionixSuggestion] {
        var components = URLComponents(string: "\(Self.baseURL)/v2/search/instant")!
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        let request = authorizedRequest(url: components.url!, method: "GET", body: nil)
        let response: NXSearchInstantResponse = try await perform(request)
        let common = response.common.map {
            NutritionixSuggestion(
                name:      $0.food_name,
                brandName: $0.brand_name,
                photoURL:  $0.photo?.thumb.flatMap { URL(string: $0) },
                kind:      .common,
                nixItemId: $0.nix_item_id
            )
        }
        let branded = response.branded.map {
            NutritionixSuggestion(
                name:      $0.food_name,
                brandName: $0.brand_name,
                photoURL:  $0.photo?.thumb.flatMap { URL(string: $0) },
                kind:      .branded,
                nixItemId: $0.nix_item_id
            )
        }
        return common + branded
    }

    // MARK: - Private Helpers

    private func authorizedRequest(url: URL, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(appID,  forHTTPHeaderField: "x-app-id")
        request.setValue(appKey, forHTTPHeaderField: "x-app-key")
        request.setValue("0",    forHTTPHeaderField: "x-remote-user-id")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NutritionixError.httpError(statusCode: -1)
            }
            try mapStatusCode(http)
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch let decodingError as DecodingError {
                throw NutritionixError.decodingFailure(decodingError)
            }
        } catch let urlError as URLError {
            throw NutritionixError.networkFailure(urlError)
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
        let calories = nxFood.nf_calories           ?? 0.0
        let protein  = nxFood.nf_protein            ?? 0.0
        let carbs    = nxFood.nf_total_carbohydrate ?? 0.0
        let fat      = nxFood.nf_total_fat          ?? 0.0
        let photoURL = nxFood.photo?.thumb.flatMap { URL(string: $0) }
        return NutritionixFoodItem(
            name:               nxFood.food_name,
            calories:           calories,
            protein:            protein,
            carbs:              carbs,
            fat:                fat,
            servingQuantity:    nxFood.serving_qty          ?? 1.0,
            servingUnit:        nxFood.serving_unit,
            servingWeightGrams: nxFood.serving_weight_grams ?? 0.0,
            photoURL:           photoURL,
            brandName:          nxFood.brand_name,
            validation:         MacroValidator.validate(
                                    calories: calories, protein: protein,
                                    carbs: carbs, fat: fat)
        )
    }
}
