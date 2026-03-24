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
    var isFlagged: Bool = false
    var calorieDiscrepancy: Double = 0   // signed total kcal: stored calories − calculated

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
        mealType: MealType,
        isFlagged: Bool = false,
        calorieDiscrepancy: Double = 0.0
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
        self.isFlagged = isFlagged
        self.calorieDiscrepancy = calorieDiscrepancy
    }
}
