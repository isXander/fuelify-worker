import SwiftData

enum UserPreferencesSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [UserPreferences.self]
    }

    @Model
    final class UserPreferences {
        var selectedFuelTypeRaw: String
        var sortOptionRaw: String
        var tankCapacity: Double
        var tankPrecision: Int
        var fuelEconomy: Double

        init(
            selectedFuelTypeRaw: String = FuelType.e10.rawValue,
            sortOptionRaw: String = SortOption.distance.rawValue,
            tankCapacity: Double = 50.0,
            tankPrecision: Int = 6,
            fuelEconomy: Double = 40.0
        ) {
            self.selectedFuelTypeRaw = selectedFuelTypeRaw
            self.sortOptionRaw = sortOptionRaw
            self.tankCapacity = tankCapacity
            self.tankPrecision = tankPrecision
            self.fuelEconomy = fuelEconomy
        }
    }
}
