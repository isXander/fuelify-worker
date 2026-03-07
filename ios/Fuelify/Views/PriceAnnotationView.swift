import SwiftUI

struct PriceAnnotationView: View {
    let price: FuelPriceEntry?
    let isSupermarket: Bool
    let isMotorway: Bool
    let isSelected: Bool
    let tintColor: Color
    /// When set, shows total cost (£) instead of pence-per-litre
    var litresNeeded: Double? = nil
    
    private var displayText: String? {
        guard let price else { return nil }
        if let litres = litresNeeded {
            let costPounds = price.price * litres / 100.0
            return String(format: "£%.2f", costPounds)
        }
        return String(format: "%.1fp", price.price)
    }

    var body: some View {
        VStack(spacing: 6) {
            if let displayText {
                Text(displayText)
                    .font(.headline)
                    .fontWeight(.heavy)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(tintColor)
                    .shadow(color: tintColor, radius: 2, x: 0, y: 0)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black)
                .stroke(tintColor)
        }
        .scaleEffect(isSelected ? 2.0 : 1.0)
        .animation(.easeInOut(duration: 2.0), value: isSelected)
    }
}

import MapKit

#Preview {
    Map {
        Annotation("", coordinate: CLLocationCoordinate2D(latitude: 51.5081, longitude: 0.0759)) {
            PriceAnnotationView(
                price: FuelPriceEntry(fuelType: .e10, sample: FuelPriceSample(price: 134.1, effectiveDate: "")),
                isSupermarket: true,
                isMotorway: false,
                isSelected: false,
                tintColor: .green,
            )
        }
    }
    
}
