import Foundation

enum FuelType: String, Codable, CaseIterable, Identifiable {
    case e10 = "E10"
    case e5 = "E5"
    case b7Standard = "B7STANDARD"
    case b7Premium = "B7PREMIUM"
    case b10 = "B10"
    case hvo = "HVO"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .e10: return "Unleaded (E10)"
        case .e5: return "Super Unleaded (E5)"
        case .b7Standard: return "Diesel (B7)"
        case .b7Premium: return "Premium Diesel (B7)"
        case .b10: return "Biodiesel (B10)"
        case .hvo: return "Renewable Diesel (HVO)"
        }
    }

    var shortName: String {
        switch self {
        case .e10: return "E10"
        case .e5: return "E5"
        case .b7Standard: return "B7"
        case .b7Premium: return "B7+"
        case .b10: return "B10"
        case .hvo: return "HVO"
        }
    }
}
