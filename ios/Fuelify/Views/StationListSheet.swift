import SwiftUI
import SwiftData
import MapKit

struct StationListSheet: View {
    let stations: [StationResponse]
    let isLoading: Bool
    @Binding var selectedStation: StationResponse?
    @Binding var detent: PresentationDetent
    @Bindable var preferences: UserPreferences
    @Bindable var viewModel: StationListViewModel

    private var selectedFuelType: FuelType {
        preferences.selectedFuelType
    }

    private var displayedStations: [StationResponse] {
        viewModel.filteredAndSortedStations(from: stations, fuelType: selectedFuelType)
    }

    private var allPricesForDisplayedStations: [Double] {
        displayedStations.compactMap { $0.latestFuelPrices[selectedFuelType]?.price }
    }

    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            mainBody
                .navigationTitle("Fuelify")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        fuelTypePicker
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }

                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.costCalcPresented = true
                        } label: {
                            Label("Enter amount", systemImage: "gauge.with.dots.needle.bottom.50percent.badge.plus")
                        }
                        .tint(viewModel.litresNeeded != nil ? .blue : nil)
                    }

                    ToolbarItem(placement: .topBarLeading) {
                        filterMenu
                    }
                }
                .navigationDestination(for: StationResponse.self) { station in
                    StationDetailView(station: station)
                }
                .fullScreenCover(isPresented: $viewModel.showSettings) {
                    NavigationStack {
                        SettingsView(preferences: preferences)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") {
                                        viewModel.showSettings = false
                                    }
                                }
                            }
                    }
                }
                .sheet(isPresented: $viewModel.costCalcPresented) {
                    TotalPriceCalculatorView(
                        totalSegments: preferences.tankPrecision,
                        tankCapacity: preferences.tankCapacity,
                        currentSegments: $viewModel.costCalcCurrent,
                        desiredSegments: $viewModel.costCalcDesired,
                        onApply: { litres in
                            viewModel.litresNeeded = litres
                            viewModel.costCalcPresented = false
                        },
                        onClear: {
                            viewModel.litresNeeded = nil
                            viewModel.costCalcPresented = false
                        }
                    )
                    .presentationDetents([.medium])
                }
        }
        .onChange(of: selectedStation) { _, station in
            if let station {
                viewModel.navigationPath = NavigationPath([station])
                selectedStation = nil
            }
        }
    }

    // MARK: - Toolbar items

    private var fuelTypePicker: some View {
        Menu {
            Picker(selection: $preferences.selectedFuelTypeRaw) {
                ForEach(FuelType.allCases) { fuelType in
                    Text(fuelType.displayName).tag(fuelType.rawValue)
                }
            } label: {}
        } label: {
            Text(preferences.selectedFuelType.shortName)
        }
    }

    private var filterMenu: some View {
        Menu {
            // Supermarket toggle
            Button {
                viewModel.filterHideSupermarkets.toggle()
            } label: {
                Label(
                    "Hide Supermarkets",
                    systemImage: viewModel.filterHideSupermarkets ? "checkmark.circle.fill" : "cart"
                )
            }

            // Motorway toggle
            Button {
                viewModel.filterHideMotorways.toggle()
            } label: {
                Label(
                    "Hide Motorways",
                    systemImage: viewModel.filterHideMotorways ? "checkmark.circle.fill" : "road.lanes"
                )
            }
            
            // Regular toggle
            Button {
                viewModel.filterHideRegulars.toggle()
            } label: {
                Label(
                    "Hide Regulars",
                    systemImage: viewModel.filterHideRegulars ? "checkmark.circle.fill" : "house"
                )
            }
            
            Divider()
            
            // Open now toggle
            Button {
                viewModel.filterOpenNow.toggle()
            } label: {
                Label(
                    "Open Now",
                    systemImage: viewModel.filterOpenNow ? "checkmark.circle.fill" : "door.left.hand.open"
                )
            }
            
            Button {
                viewModel.filterOpen24Hours.toggle()
            } label: {
                Label(
                    "Open 24 Hours",
                    systemImage: viewModel.filterOpen24Hours ? "checkmark.circle.fill" : "24.circle"
                )
            }

            Divider()

            // Amenities submenu
            Menu("Amenities") {
                ForEach(Amenity.allCases) { amenity in
                    Button {
                        if viewModel.filterAmenities.contains(amenity) {
                            viewModel.filterAmenities.remove(amenity)
                        } else {
                            viewModel.filterAmenities.insert(amenity)
                        }
                    } label: {
                        Label(
                            amenity.displayName,
                            systemImage: viewModel.filterAmenities.contains(amenity)
                                ? "checkmark.circle.fill"
                                : amenity.systemImage
                        )
                    }
                }
            }

            if viewModel.hasActiveFilters {
                Divider()

                Button(role: .destructive) {
                    viewModel.clearFilters()
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Filter", systemImage: viewModel.hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - Main body

    @ViewBuilder
    private var mainBody: some View {
        if isLoading {
            ProgressView("Finding stations...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayedStations.isEmpty {
            if viewModel.hasActiveFilters && !stations.isEmpty {
                ContentUnavailableView(
                    "No Matching Stations",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try adjusting your filters.")
                )
            } else {
                ContentUnavailableView(
                    "No Stations Found",
                    systemImage: "fuelpump.slash",
                    description: Text("No petrol stations found nearby.")
                )
            }
        } else {
            let allPrices = allPricesForDisplayedStations

            List {
                Section {
                    ForEach(displayedStations) { station in
                        StationRow(
                            station: station,
                            selectedFuelTypeRaw: preferences.selectedFuelTypeRaw,
                            litresNeeded: viewModel.litresNeeded,
                            priceColor: viewModel.priceColor(
                                for: station,
                                allPrices: allPrices,
                                fuelType: selectedFuelType
                            )
                        )
                        .onTapGesture {
                            selectedStation = station
                        }
                    }
                } header: {
                    HStack {
                        Text("Nearby")

                        Spacer()

                        sortPicker
                    }
                }
                .headerProminence(.increased)
            }
        }
    }

    // MARK: - Sort picker

    private var sortPicker: some View {
        Picker("Sort", selection: $viewModel.sortOption) {
            ForEach(SortOption.allCases) { option in
                Label(option.rawValue, systemImage: option.systemImage)
                    .tag(option)
            }
        }
        .buttonStyle(.glass)
    }
}

struct TotalPriceCalculatorView: View {
    let totalSegments: Int
    let tankCapacity: Double
    @Binding var currentSegments: Int
    @Binding var desiredSegments: Int
    var onApply: (Double) -> Void
    var onClear: () -> Void
    
    private var litresNeeded: Double {
        let segmentsToFill = max(desiredSegments - currentSegments, 0)
        return tankCapacity * Double(segmentsToFill) / Double(totalSegments)
    }
    
    var body: some View {
        NavigationStack {
            FuelGagueView(segments: totalSegments, full: currentSegments, flashing: max(desiredSegments - currentSegments, 0))
                .padding(.horizontal, 10)
                .drawingGroup()
            
            Form {
                
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Current")
                            
                            Spacer()
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(currentSegments) },
                                set: { currentSegments = Int($0) },
                            ),
                            in: 0.0...Double(totalSegments),
                            step: 1.0,
                        ) {
                            Text("Current Fuel Level")
                        } minimumValueLabel: {
                            Text("E")
                        } maximumValueLabel: {
                            Text("F")
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Desired")
                            
                            Spacer()
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(desiredSegments) },
                                set: { desiredSegments = Int($0) },
                            ),
                            in: 0...Double(totalSegments),
                            step: 1.0,
                        ) {
                            Text("Desired Fuel Level")
                        } minimumValueLabel: {
                            Text("E")
                        } maximumValueLabel: {
                            Text("F")
                        }
                    }
                    
                    LabeledContent("Amount to add") {
                        Text(String(format: "%.1f L", litresNeeded))
                    }
                }
            }
            .navigationTitle("Cost Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onApply(litresNeeded)
                    } label: {
                        Label("Done", systemImage: "checkmark")
                    }
                    .disabled(litresNeeded <= 0)
                }
                
                // Removes the cost calculation and returns to showing pence per litre
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .destructive) {
                        onClear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .onChange(of: currentSegments) { _, newValue in
            if desiredSegments < newValue {
                desiredSegments = newValue
            }
        }
    }
}

#Preview {
    @State @Previewable
    var detent: PresentationDetent = .medium
    
    let mockStations: [StationResponse] = [
        StationResponse(
            info: StationInfo(stationId: "1", tradingName: "Tesco Extra", brandName: "Tesco", motorway: false, supermarket: true),
            location: StationLocation(latitude: 51.5074, longitude: -0.1278, addressLine1: "123 High Street", addressLine2: "", city: "London", county: "Greater London", postcode: "SW1A 1AA"),
            amenities: [.carWash, .customerToilets],
            latestFuelPrices: [
                .e10: FuelPriceSample(price: 132.9, effectiveDate: "2026-03-05"),
                .b7Standard: FuelPriceSample(price: 140.9, effectiveDate: "2026-03-05"),
            ],
            driveTimeSeconds: 300
        ),
        StationResponse(
            info: StationInfo(stationId: "2", tradingName: "Shell Kensington", brandName: "Shell", motorway: false, supermarket: false),
            location: StationLocation(latitude: 51.5010, longitude: -0.1920, addressLine1: "45 Kensington Road", addressLine2: "", city: "London", county: "Greater London", postcode: "W8 5EP"),
            amenities: [.customerToilets, .adbluePumps],
            latestFuelPrices: [
                .e10: FuelPriceSample(price: 145.9, effectiveDate: "2026-03-04"),
                .e5: FuelPriceSample(price: 155.9, effectiveDate: "2026-03-04"),
                .b7Standard: FuelPriceSample(price: 149.9, effectiveDate: "2026-03-04"),
            ],
            driveTimeSeconds: 480
        ),
        StationResponse(
            info: StationInfo(stationId: "3", tradingName: "BP Connect M25", brandName: "BP", motorway: true, supermarket: false),
            location: StationLocation(latitude: 51.4700, longitude: -0.2100, addressLine1: "M25 Junction 10", addressLine2: "Services", city: "Cobham", county: "Surrey", postcode: "KT11 3DB"),
            amenities: [.carWash, .customerToilets, .waterFilling, .adbluePumps],
            latestFuelPrices: [
                .e10: FuelPriceSample(price: 155.9, effectiveDate: "2026-03-06"),
                .b7Standard: FuelPriceSample(price: 161.9, effectiveDate: "2026-03-06"),
            ],
            driveTimeSeconds: 900
        ),
        StationResponse(
            info: StationInfo(stationId: "4", tradingName: "Sainsbury's Wandsworth", brandName: "Sainsbury's", motorway: false, supermarket: true),
            location: StationLocation(latitude: 51.4550, longitude: -0.1880, addressLine1: "78 Wandsworth High St", addressLine2: "", city: "London", county: "Greater London", postcode: "SW18 4TF"),
            latestFuelPrices: [
                .e10: FuelPriceSample(price: 133.9, effectiveDate: "2026-03-06"),
                .b7Standard: FuelPriceSample(price: 141.9, effectiveDate: "2026-03-06"),
            ],
            driveTimeSeconds: 720
        ),
    ]
    
    Map {
        
    }
        .sheet(isPresented: .constant(true)) {
            StationListSheet(
                stations: mockStations,
                isLoading: false,
                selectedStation: .constant(nil),
                detent: $detent,
                preferences: UserPreferences(),
                viewModel: StationListViewModel()
            )
            .presentationDetents([.fraction(0.25), .medium, .large], selection: $detent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .interactiveDismissDisabled()
        }
        
        .modelContainer(for: UserPreferences.self, inMemory: true)
}

