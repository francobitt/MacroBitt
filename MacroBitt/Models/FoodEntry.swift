//
//  FoodEntry.swift
//  MacroBitt
//
//  Created by francobitt on 3/23/26.
//

import SwiftData
import Foundation

@Model
final class FoodEntry {
    var id: UUID
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var servingSize: String?
    var servingCount: Double
    var timestamp: Date
    var mealType: MealType

    init(
        id: UUID = UUID(),
        name: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        servingSize: String? = nil,
        servingCount: Double = 1.0,
        timestamp: Date = Date(),
        mealType: MealType
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingSize = servingSize
        self.servingCount = servingCount
        self.timestamp = timestamp
        self.mealType = mealType
    }
}
