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
