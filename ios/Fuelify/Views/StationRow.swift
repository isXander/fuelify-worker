import SwiftUI

struct StationRow: View {
    let station: StationResponse
    let selectedFuelTypeRaw: String
    /// When set, the row displays the total fill cost (£) instead of pence-per-litre
    var litresNeeded: Double? = nil
    let priceColor: Color?

    private var selectedFuelType: FuelType {
        FuelType(rawValue: selectedFuelTypeRaw) ?? .e10
    }

    private var preferredPrice: FuelPriceEntry? {
        if let sample = station.latestFuelPrices[selectedFuelType] {
            return FuelPriceEntry(fuelType: selectedFuelType, sample: sample)
        }
        return station.fuelPrices.first
    }
    
    /// Total cost in pounds, if a cost calculation is active
    private var totalCostPounds: Double? {
        guard let litres = litresNeeded, let ppl = preferredPrice?.price else { return nil }
        return ppl * litres / 100.0
    }

    private var lastChangedText: String? {
        guard let relative = preferredPrice?.relativeEffectiveDate else { return nil }
        return "Changed \(relative)"
    }

    private var formattedDriveTime: String? {
        guard let seconds = station.driveTimeSeconds else { return nil }
        let minutes = Int(ceil(seconds / 60))
        return "\(minutes) min"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatStationName(station.tradingName))
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let time = formattedDriveTime {
                        TagView(text: time, systemImage: "car", color: .blue)
                    }
                    if station.supermarket {
                        TagView(systemImage: "cart", color: .green)
                    }
                    if station.motorway {
                        TagView(systemImage: "road.lines", color: .blue)
                    }
                }
            }

            Spacer(minLength: 8)

            // Prominent price pill
            if let preferredPrice {
                VStack(alignment: .trailing, spacing: 2) {
                    if let cost = totalCostPounds {
                        Text(String(format: "£%.2f", cost))
                            .font(.title3)
                            .fontWeight(.heavy)
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(priceColor ?? (station.supermarket ? .green : .blue))
                            .background((priceColor ?? (station.supermarket ? .green : .blue)).opacity(0.12), in: Capsule())
                    } else {
                        Text(String(format: "%.1fp", preferredPrice.price))
                            .font(.title3)
                            .fontWeight(.heavy)
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(priceColor ?? (station.supermarket ? .green : .blue))
                            .background((priceColor ?? (station.supermarket ? .green : .blue)).opacity(0.12), in: Capsule())
                    }
                    if let lastChangedText {
                        Text(lastChangedText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button {
                openInMaps(station: station)
            } label: {
                Label("Get Directions", systemImage: "car")
            }
        }
    }
}
