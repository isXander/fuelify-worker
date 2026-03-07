import SwiftData

enum UserPreferencesSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [UserPreferences.self]
    }

    @Model
    final class UserPreferences {
        var selectedFuelTypeRaw: String
        var sortOptionRaw: String
        var tankCapacity: Double
        var tankPrecision: Int

        init(
            selectedFuelTypeRaw: String = FuelType.e10.rawValue,
            sortOptionRaw: String = SortOption.distance.rawValue,
            tankCapacity: Double = 10.0,
            tankPrecision: Int = 6
        ) {
            self.selectedFuelTypeRaw = selectedFuelTypeRaw
            self.sortOptionRaw = sortOptionRaw
            self.tankCapacity = tankCapacity
            self.tankPrecision = tankPrecision
        }
    }
}
