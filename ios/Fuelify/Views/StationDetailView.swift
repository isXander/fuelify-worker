import SwiftUI
import MapKit

struct StationDetailView: View {
    let station: StationResponse

    @State private var stationMapItem: MKMapItem
    
    init(station: StationResponse) {
        self.station = station
        self._stationMapItem = State(initialValue: stationToMapItem(station: station))
    }
    
    private var normalisedAddress: String? {
        stationMapItem.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(stationMapItem.name ?? station.tradingName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .transition(.blurReplace)
                    Text(station.brandName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Address
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            if let normalisedAddress {
                                Text(normalisedAddress)
                                    .transition(.blurReplace)
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.addressLine1)
                                    if !station.addressLine2.isEmpty {
                                        Text(station.addressLine2)
                                    }
                                    Text("\(station.city), \(station.postcode)")
                                }
                                .transition(.blurReplace)
                            }
                        }
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                    .font(.subheadline)
                    .animation(.smooth, value: normalisedAddress)
                }

                // Drive distance and time
                HStack(spacing: 16) {
                    if let meters = station.driveDistanceMeters {
                        let measurement = Measurement(value: meters, unit: UnitLength.meters)
                        Label {
                            Text(measurement, format: .measurement(width: .abbreviated, usage: .road))
                        } icon: {
                            Image(systemName: "car")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    if let seconds = station.driveTimeSeconds {
                        Label {
                            Text(Duration.seconds(seconds), format: .units(allowed: [.hours, .minutes], width: .abbreviated))
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }

                // Tags
                HStack(spacing: 8) {
                    if station.supermarket {
                        TagView(text: "Supermarket", color: .green)
                    }
                    if station.motorway {
                        TagView(text: "Motorway", color: .orange)
                    }
                }

                Divider()

                // Fuel Prices
                if !station.fuelPrices.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fuel Prices")
                            .font(.headline)

                        ForEach(station.fuelPrices) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.fuelType.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("Last changed \(entry.relativeEffectiveDate ?? entry.effectiveDate)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(String(format: "%.1fp", entry.price))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                            .padding(12)
                            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                // Directions button
                Button {
                    openInMaps(mapItem: stationMapItem)
                } label: {
                    Label("Get Directions", systemImage: "arrow.trianglehead.turn.up.right.diamond.fill")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle(station.tradingName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    
                } label: {
                    Label("Favourite", systemImage: "star")
                }
            }
        }
        .task {
            await resolveAddress()
        }
    }

    private func resolveAddress() async {
        if let mapItem = await findMapItem(station: station) {
            stationMapItem = mapItem
        }
    }
}

