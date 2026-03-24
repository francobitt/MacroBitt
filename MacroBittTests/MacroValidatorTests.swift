//
//  MacroValidatorTests.swift
//  MacroBittTests
//

import Testing
@testable import MacroBitt

struct MacroValidatorTests {

    // P=30 × 4 + C=50 × 4 + F=10 × 9 = 120 + 200 + 90 = 410 kcal
    @Test func validEntry() {
        let r = MacroValidator.validate(calories: 410, protein: 30, carbs: 50, fat: 10)
        #expect(r.isValid)
        #expect(r.calculatedCalories == 410)
        #expect(r.difference == 0)
    }

    @Test func invalidEntry_overBudget() {
        let r = MacroValidator.validate(calories: 600, protein: 30, carbs: 50, fat: 10)
        #expect(!r.isValid)
        #expect(r.calculatedCalories == 410)
        #expect(r.difference == 190)   // 600 - 410
    }

    @Test func withinTolerance() {
        // 413 entered, 410 calculated — 3 kcal difference ≤ 5
        let r = MacroValidator.validate(calories: 413, protein: 30, carbs: 50, fat: 10)
        #expect(r.isValid)
    }

    @Test func atToleranceBoundaryIsValid() {
        // Exactly 5 kcal difference — still valid
        let r = MacroValidator.validate(calories: 415, protein: 30, carbs: 50, fat: 10)
        #expect(r.isValid)
    }

    @Test func justOverToleranceIsInvalid() {
        // 6 kcal difference — invalid
        let r = MacroValidator.validate(calories: 416, protein: 30, carbs: 50, fat: 10)
        #expect(!r.isValid)
    }

    @Test func negativeDifference() {
        // Entered less than calculated
        let r = MacroValidator.validate(calories: 400, protein: 30, carbs: 50, fat: 10)
        #expect(!r.isValid)
        #expect(r.difference == -10)   // 400 - 410
    }
}
