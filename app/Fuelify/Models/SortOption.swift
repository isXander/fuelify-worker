import Foundation

enum SortOption: String, CaseIterable, Identifiable {
    case distance = "Distance"
    case driveTime = "Drive Time"
    case price = "Price"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .distance: return "location"
        case .driveTime: return "car"
        case .price: return "sterlingsign"
        }
    }
}
