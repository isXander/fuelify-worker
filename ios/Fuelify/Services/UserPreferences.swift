import SwiftData
import SwiftUI

typealias UserPreferences = UserPreferencesSchemaV2.UserPreferences

extension UserPreferences {
    // MARK: - Convenience accessors

    var selectedFuelType: FuelType {
        get { FuelType(rawValue: selectedFuelTypeRaw) ?? .e10 }
        set { selectedFuelTypeRaw = newValue.rawValue }
    }

    var sortOption: SortOption {
        get { SortOption(rawValue: sortOptionRaw) ?? .distance }
        set { sortOptionRaw = newValue.rawValue }
    }

    // MARK: - Singleton fetch-or-create

    /// Returns the single `UserPreferences` record, creating one with defaults if none exists.
    /// On first launch after migration, seeds from any existing UserDefaults values.
    @MainActor
    static func resolve(in context: ModelContext) -> UserPreferences {
        let descriptor = FetchDescriptor<UserPreferences>()

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        // Create defaults if not present
        let prefs = UserPreferences(
            selectedFuelTypeRaw: FuelType.e10.rawValue,
            sortOptionRaw: SortOption.distance.rawValue
        )
        context.insert(prefs)

        return prefs
    }
}

enum UserPreferencesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [UserPreferencesSchemaV1.self, UserPreferencesSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: UserPreferencesSchemaV1.self, toVersion: UserPreferencesSchemaV2.self),
        ]
    }
}
