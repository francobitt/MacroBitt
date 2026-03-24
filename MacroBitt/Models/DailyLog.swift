//
//  DailyLog.swift
//  MacroBitt
//
//  Created by francobitt on 3/23/26.
//

import SwiftData
import Foundation

@Model
final class DailyLog {
    var id: UUID
    @Attribute(.unique) var date: Date
    @Relationship(deleteRule: .cascade) var entries: [FoodEntry]

    init(id: UUID = UUID(), date: Date) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.entries = []
    }
}
