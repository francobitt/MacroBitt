//
//  DashboardView.swift
//  MacroBitt
//

import SwiftUI
import SwiftData

// MARK: - Root Tab View

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        NavigationStack {
            DashboardContentView(today: today)
                .navigationTitle("Dashboard")
                .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            guard (try? modelContext.fetch(FetchDescriptor<UserSettings>()))?.isEmpty == true else { return }
            modelContext.insert(UserSettings())
        }
    }
}

// MARK: - Content View

private struct DashboardContentView: View {
    @Query private var todayLogs: [DailyLog]
    @Query private var allSettings: [UserSettings]

    init(today: Date) {
        _todayLogs = Query(filter: #Predicate<DailyLog> { $0.date == today })
    }

    private var entries: [FoodEntry] { todayLogs.first?.entries ?? [] }
    private var settings: UserSettings? { allSettings.first }

    private var totalCalories: Double { entries.reduce(0) { $0 + $1.calories } }
    private var totalProtein:  Double { entries.reduce(0) { $0 + $1.protein  } }
    private var totalCarbs:    Double { entries.reduce(0) { $0 + $1.carbs    } }
    private var totalFat:      Double { entries.reduce(0) { $0 + $1.fat      } }

    var body: some View {
        ScrollView {
            if let settings {
                DashboardCard(
                    totalCalories: totalCalories,
                    totalProtein:  totalProtein,
                    totalCarbs:    totalCarbs,
                    totalFat:      totalFat,
                    settings:      settings
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

// MARK: - Dashboard Card

private struct DashboardCard: View {
    let totalCalories: Double
    let totalProtein:  Double
    let totalCarbs:    Double
    let totalFat:      Double
    let settings: UserSettings

    var body: some View {
        VStack(spacing: 28) {
            CalorieRingView(
                consumed: totalCalories,
                goal: settings.dailyCalorieGoal
            )

            HStack(spacing: 0) {
                MacroRingView(
                    label: "Protein",
                    consumed: totalProtein,
                    goal: settings.proteinGoal,
                    unit: "g",
                    color: Color(red: 1.0, green: 0.45, blue: 0.2)
                )
                Spacer()
                MacroRingView(
                    label: "Carbs",
                    consumed: totalCarbs,
                    goal: settings.carbsGoal,
                    unit: "g",
                    color: Color(red: 1.0, green: 0.78, blue: 0.0)
                )
                Spacer()
                MacroRingView(
                    label: "Fat",
                    consumed: totalFat,
                    goal: settings.fatGoal,
                    unit: "g",
                    color: Color(red: 0.62, green: 0.32, blue: 1.0)
                )
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            Color(red: 0.08, green: 0.08, blue: 0.12),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }
}

// MARK: - Calorie Ring

private struct CalorieRingView: View {
    let consumed: Double
    let goal: Double

    private var progress: Double { goal > 0 ? consumed / goal : 0 }
    private var remaining: Double { max(0, goal - consumed) }

    private let ringColor = Color(red: 0.2, green: 0.6, blue: 1.0)

    var body: some View {
        ZStack {
            ProgressRing(progress: progress, color: ringColor, lineWidth: 18)
                .frame(width: 190, height: 190)

            VStack(spacing: 2) {
                Text(consumed.formatted(.number.precision(.fractionLength(0))))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("kcal")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 2)
                Text("\(remaining.formatted(.number.precision(.fractionLength(0)))) left")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(ringColor)
            }
        }
    }
}

// MARK: - Macro Ring

private struct MacroRingView: View {
    let label: String
    let consumed: Double
    let goal: Double
    let unit: String
    let color: Color

    private var progress: Double { goal > 0 ? consumed / goal : 0 }
    private var remaining: Double { max(0, goal - consumed) }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ProgressRing(progress: progress, color: color, lineWidth: 10)
                    .frame(width: 84, height: 84)

                VStack(spacing: 1) {
                    Text(consumed.formatted(.number.precision(.fractionLength(0))))
                        .font(.system(.callout, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text(unit)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            VStack(spacing: 2) {
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text("\(remaining.formatted(.number.precision(.fractionLength(0))))\(unit) left")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(color.opacity(0.85))
            }
        }
    }
}

// MARK: - Progress Ring

private struct ProgressRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(CGFloat(progress), 1.0))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: progress)
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .modelContainer(for: [FoodEntry.self, DailyLog.self, UserSettings.self], inMemory: true)
}
