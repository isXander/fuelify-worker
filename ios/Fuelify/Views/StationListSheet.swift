import SwiftUI

struct StationListSheet: View {
    let stations: [StationResponse]
    let isLoading: Bool
    @Binding var selectedStation: StationResponse?
    @Bindable var preferences: UserPreferences

    @State private var navigationPath = NavigationPath()
    @State private var showSettings = false

    private var selectedFuelType: FuelType {
        preferences.selectedFuelType
    }

    private var allPricesForSelectedFuel: [Double] {
        stations.compactMap { station in
            station.latestFuelPrices[selectedFuelType]?.price
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                Menu {
                    Picker("Sort By", selection: $preferences.sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Label(option.rawValue, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                } label: {
                    Label(preferences.sortOption.rawValue, systemImage: "arrow.up.arrow.down")
                }
                
                if isLoading {
                    ProgressView("Finding stations...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if stations.isEmpty {
                    ContentUnavailableView(
                        "No Stations Found",
                        systemImage: "fuelpump.slash",
                        description: Text("No petrol stations found nearby.")
                    )
                } else {
                    List(stations) { station in
                        StationRow(
                            station: station,
                            selectedFuelTypeRaw: preferences.selectedFuelTypeRaw,
                            priceColor: {
                                if let p = station.latestFuelPrices[selectedFuelType]?.price {
                                    return priceTierColor(for: p, in: allPricesForSelectedFuel)
                                } else {
                                    return nil
                                }
                            }()
                        )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedStation = station
                            }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Nearby Stations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .navigationDestination(for: StationResponse.self) { station in
                StationDetailView(station: station)
            }
            .fullScreenCover(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(preferences: preferences)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    showSettings = false
                                }
                            }
                        }
                }
            }
        }
        .onChange(of: selectedStation) { _, station in
            if let station {
                navigationPath = NavigationPath([station])
                selectedStation = nil
            }
        }
    }
}
