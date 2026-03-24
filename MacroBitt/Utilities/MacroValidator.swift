//
//  MacroValidator.swift
//  MacroBitt
//

struct MacroValidator {
    struct Result {
        let isValid: Bool
        let calculatedCalories: Double
        let difference: Double   // provided − calculated (signed)
    }

    static let tolerance: Double = 5

    static func validate(calories: Double, protein: Double,
                         carbs: Double, fat: Double) -> Result {
        let calc = (fat * 9) + (carbs * 4) + (protein * 4)
        let diff = calories - calc
        return Result(isValid: abs(diff) <= tolerance,
                      calculatedCalories: calc,
                      difference: diff)
    }
}
