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
