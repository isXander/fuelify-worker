import SwiftUI

@MainActor
@Observable
class StationListViewModel {
    // MARK: - Filter state

    var filterAmenities: Set<Amenity> = []
    var filterHideSupermarkets = false
    var filterHideMotorways = false
    var filterHideRegulars = false
    // TODO: modify backend to give opening hours and implement these filters
    var filterOpenNow = false
    var filterOpen24Hours = false

    var hasActiveFilters: Bool {
        !filterAmenities.isEmpty || filterHideMotorways || filterHideSupermarkets || filterHideRegulars || filterOpenNow || filterOpen24Hours
    }

    // MARK: - Sort state

    var sortOption: SortOption = .distance

    // MARK: - Cost calculator state

    var costCalcPresented = false
    var costCalcCurrent: Int = 3
    var costCalcDesired: Int = 6

    /// When set, views show total cost (£) instead of pence-per-litre
    var litresNeeded: Double? = nil

    // MARK: - UI state

    var showSettings = false
    var navigationPath = NavigationPath()

    // MARK: - Derived data

    func filteredAndSortedStations(
        from stations: [StationResponse],
        fuelType: FuelType
    ) -> [StationResponse] {
        var result = stations.filter { passesFilter($0) }

        // Apply sort
        result.sort { a, b in
            switch sortOption {
            case .distance:
                return (a.driveDistanceMeters ?? .infinity) < (b.driveDistanceMeters ?? .infinity)
            case .driveTime:
                return (a.driveTimeSeconds ?? .infinity) < (b.driveTimeSeconds ?? .infinity)
            case .price:
                let aPrice = a.latestFuelPrices[fuelType]?.price ?? .infinity
                let bPrice = b.latestFuelPrices[fuelType]?.price ?? .infinity
                return aPrice < bPrice
            }
        }

        return result
    }

    func priceColor(for station: StationResponse, allPrices: [Double], fuelType: FuelType) -> Color? {
        if let p = station.latestFuelPrices[fuelType]?.price {
            return priceTierColor(for: p, in: allPrices)
        }
        return nil
    }

    /// Whether a station passes the current filter criteria
    func passesFilter(_ station: StationResponse) -> Bool {
        if filterHideRegulars && (!station.supermarket && !station.motorway) {
            return false
        }
        if station.supermarket && filterHideSupermarkets {
            return false
        }
        // motorway stations that are also supermarket stations (mainly morrisons)
        // should not be treated as motorways, as they are usually supermarket priced
        if (station.motorway && !station.supermarket) && filterHideMotorways {
            return false
        }
        if !filterAmenities.isEmpty {
            if !filterAmenities.isSubset(of: Set(station.amenities)) {
                return false
            }
        }
        return true
    }

    func clearFilters() {
        filterAmenities = []
        filterHideSupermarkets = false
        filterHideMotorways = false
        filterHideRegulars = false
    }
}
