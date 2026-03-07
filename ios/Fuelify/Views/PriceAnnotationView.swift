import SwiftUI

struct PriceAnnotationView: View {
    let price: FuelPriceEntry?
    let isSupermarket: Bool
    let isMotorway: Bool
    let isSelected: Bool
    let tintColor: Color

    var body: some View {
        VStack(spacing: 6) {
            if let price {
                Text(String(format: "%.1fp", price.price))
                    .font(.callout)
                    .fontWeight(.heavy)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(tintColor)
                    .background(tintColor.opacity(0.12), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(tintColor.opacity(0.25), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
            }

            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isSupermarket ? .green : .blue)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                if isMotorway {
                    Circle()
                        .fill(.thinMaterial)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Image(systemName: "road.lanes")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                        .offset(x: 2, y: 2)
                }
            }
        }
        .scaleEffect(isSelected ? 1.15 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
