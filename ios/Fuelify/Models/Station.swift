import Foundation
import MapKit

// MARK: - Nearby Stations

struct NearbyStationsRequest: Encodable {
    let fuelType: FuelType
    let originLat: Double
    let originLon: Double
    let spanLat: Double
    let spanLon: Double

    enum CodingKeys: String, CodingKey {
        case fuelType = "fuel_type"
        case originLat = "origin_lat"
        case originLon = "origin_lon"
        case spanLat = "span_lat"
        case spanLon = "span_lon"
    }
}

struct NearbyStationsResponse: Decodable {
    let results: [StationResponse]
}

// MARK: - Price History

struct PriceHistoryRequest: Encodable {
    let stationId: String
    let interval: HistoryInterval
    let fuelType: FuelType

    enum CodingKeys: String, CodingKey {
        case stationId = "station_id"
        case interval
        case fuelType = "fuel_type"
    }
}

struct PriceHistoryResponse: Decodable {
    let samples: [FuelPriceSample]
}

enum HistoryInterval: String, Codable, CaseIterable, Identifiable {
    case last7Days = "last_7_days"
    case last30Days = "last_30_days"
    case last90Days = "last_90_days"
    case last180Days = "last_180_days"
    case last365Days = "last_365_days"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .last7Days: return "7 Days"
        case .last30Days: return "30 Days"
        case .last90Days: return "90 Days"
        case .last180Days: return "180 Days"
        case .last365Days: return "365 Days"
        }
    }
}

// MARK: - Station

struct StationResponse: Codable, Identifiable, Hashable {
    let info: StationInfo
    let location: StationLocation
    let amenities: [Amenity]

    /// Raw dictionary keyed by the fuel-type string the API sends (e.g. "E10", "B7STANDARD").
    private let latestFuelPricesRaw: [String: FuelPriceSample]

    /// Typed dictionary built from the raw keys.
    var latestFuelPrices: [FuelType: FuelPriceSample] {
        latestFuelPricesRaw.reduce(into: [:]) { result, pair in
            if let ft = FuelType(rawValue: pair.key) {
                result[ft] = pair.value
            }
        }
    }

    var id: String { info.stationId }

    enum CodingKeys: String, CodingKey {
        case info
        case location
        case amenities
        case latestFuelPricesRaw = "latest_fuel_prices"
    }

    // MARK: - Convenience accessors (minimises view-layer churn)

    var tradingName: String { info.tradingName }
    var brandName: String { info.brandName }
    var latitude: Double { location.latitude }
    var longitude: Double { location.longitude }
    var addressLine1: String { location.addressLine1 }
    var addressLine2: String { location.addressLine2 }
    var city: String { location.city }
    var county: String { location.county }
    var postcode: String { location.postcode }
    var motorway: Bool { info.motorway }
    var supermarket: Bool { info.supermarket }

    init(
        info: StationInfo,
        location: StationLocation,
        amenities: [Amenity] = [],
        latestFuelPrices: [FuelType: FuelPriceSample] = [:],
        driveTimeSeconds: TimeInterval? = nil,
        driveDistanceMeters: Double? = nil
    ) {
        self.info = info
        self.location = location
        self.amenities = amenities
        self.latestFuelPricesRaw = Dictionary(uniqueKeysWithValues: latestFuelPrices.map { ($0.key.rawValue, $0.value) })
        self.driveTimeSeconds = driveTimeSeconds
        self.driveDistanceMeters = driveDistanceMeters
    }

    /// All fuel prices as an array, for iteration in views.
    var fuelPrices: [FuelPriceEntry] {
        latestFuelPrices.map { FuelPriceEntry(fuelType: $0.key, sample: $0.value) }
            .sorted { $0.fuelType.rawValue < $1.fuelType.rawValue }
    }

    /// Drive time in seconds from the user's location (populated client-side)
    var driveTimeSeconds: TimeInterval?
    /// Drive distance in meters from the user's location (populated client-side)
    var driveDistanceMeters: Double?
}

struct StationInfo: Codable, Hashable {
    let stationId: String
    let tradingName: String
    let brandName: String
    let motorway: Bool
    let supermarket: Bool

    enum CodingKeys: String, CodingKey {
        case stationId = "station_id"
        case tradingName = "trading_name"
        case brandName = "brand_name"
        case motorway
        case supermarket
    }
}

struct StationLocation: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let addressLine1: String
    let addressLine2: String
    let city: String
    let county: String
    let postcode: String

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case addressLine1 = "address_line_1"
        case addressLine2 = "address_line_2"
        case city
        case county
        case postcode
    }
    
    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Fuel Price

struct FuelPriceSample: Codable, Hashable {
    /// Price in pence per litre.
    let price: Double
    let effectiveDate: String

    enum CodingKeys: String, CodingKey {
        case price
        case effectiveDate = "effective_date"
    }

    /// Parses `effectiveDate` (yyyy-MM-dd) and returns a relative string like "2 days ago"
    var relativeEffectiveDate: String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: effectiveDate) else { return nil }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

/// A fuel type paired with its latest price sample, used for iterating in views.
struct FuelPriceEntry: Identifiable, Hashable {
    let fuelType: FuelType
    let sample: FuelPriceSample

    var id: String { fuelType.rawValue }
    var price: Double { sample.price }
    var effectiveDate: String { sample.effectiveDate }
    var relativeEffectiveDate: String? { sample.relativeEffectiveDate }
}

// MARK: - Amenity

enum Amenity: String, Codable, Hashable, CaseIterable, Identifiable {
    case customerToilets = "customer_toilets"
    case carWash = "car_wash"
    case waterFilling = "water_filling"
    case adbluePackaged = "adblue_packaged"
    case adbluePumps = "adblue_pumps"
    case lpgPumps = "lpg_pumps"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adbluePackaged: return "AdBlue (Packaged)"
        case .adbluePumps: return "AdBlue (Pumps)"
        case .carWash: return "Car Wash"
        case .customerToilets: return "Toilets"
        case .waterFilling: return "Water"
        case .lpgPumps: return "LPG"
        }
    }

    var systemImage: String {
        switch self {
        case .adbluePackaged: return "drop.fill"
        case .adbluePumps: return "fuelpump.fill"
        case .carWash: return "bubbles.and.sparkles"
        case .customerToilets: return "toilet"
        case .waterFilling: return "spigot"
        case .lpgPumps: return "flame"
        }
    }
}
