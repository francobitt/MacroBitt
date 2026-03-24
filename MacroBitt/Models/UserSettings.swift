//
//  UserSettings.swift
//  MacroBitt
//
//  Created by francobitt on 3/23/26.
//

import SwiftData

@Model
final class UserSettings {
    var dailyCalorieGoal: Double
    var proteinGoal: Double
    var carbsGoal: Double
    var fatGoal: Double

    init(
        dailyCalorieGoal: Double = 2000,
        proteinGoal: Double = 150,
        carbsGoal: Double = 200,
        fatGoal: Double = 65
    ) {
        self.dailyCalorieGoal = dailyCalorieGoal
        self.proteinGoal = proteinGoal
        self.carbsGoal = carbsGoal
        self.fatGoal = fatGoal
    }
}
