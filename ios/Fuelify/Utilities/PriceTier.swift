import SwiftUI

/// Returns a tier color (green/orange/red) for a given price based on the distribution of prices.
func priceTierColor(for price: Double, in prices: [Double]) -> Color {
    let sorted = prices.sorted()
    guard !sorted.isEmpty else { return .blue }

    let idx1 = Int(Double(sorted.count - 1) * 0.33)
    let idx2 = Int(Double(sorted.count - 1) * 0.66)
    let t1 = sorted[max(0, min(idx1, sorted.count - 1))]
    let t2 = sorted[max(0, min(idx2, sorted.count - 1))]

    if price <= t1 { return .green }
    else if price <= t2 { return .orange }
    else { return .red }
}
