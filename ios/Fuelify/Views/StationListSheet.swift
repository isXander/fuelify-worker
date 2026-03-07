import SwiftUI
import SwiftData
import MapKit

struct StationListSheet: View {
    let stations: [StationResponse]
    let isLoading: Bool
    @Binding var selectedStation: StationResponse?
    @Binding var detent: PresentationDetent
    @Bindable var preferences: UserPreferences

    @State private var navigationPath = NavigationPath()
    @State private var showSettings = false
    
    @State private var searchField = ""
    @State private var searchAmenities: [Amenity] = []
    @State private var searchAmenitiesSuggestions: [Amenity] = Amenity.allCases
    
    @State private var searchPresented = false
    
    @State private var costCalcPresented = false
    @State private var costCalcCurrent: Int = 3
    @State private var costCalcDesired: Int = 6
    
    /// When set, views show total cost (£) instead of pence-per-litre
    @Binding var litresNeeded: Double?

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
                if !searchPresented {
                    mainBody
                } else {
                    searchBody
                }
            }
            .navigationTitle("Fuelify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        costCalcPresented = true
                    } label: {
                        Label("Enter amount", systemImage: "gauge.with.dots.needle.bottom.50percent.badge.plus")
                    }
                    .tint(litresNeeded != nil ? .blue : nil)
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
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
            .searchable(text: $searchField, tokens: $searchAmenities, isPresented: $searchPresented, placement: .navigationBarDrawer, prompt: "Filter brands, amenities, and more") { token in
                Text(token.displayName)
                
            }
            .sheet(isPresented: $costCalcPresented) {
                TotalPriceCalculatorView(
                    totalSegments: preferences.tankPrecision,
                    tankCapacity: preferences.tankCapacity,
                    currentSegments: $costCalcCurrent,
                    desiredSegments: $costCalcDesired,
                    onApply: { litres in
                        litresNeeded = litres
                        costCalcPresented = false
                    },
                    onClear: {
                        litresNeeded = nil
                        costCalcPresented = false
                    }
                )
                .presentationDetents([.medium])
            }
        }
        .onChange(of: selectedStation) { _, station in
            if let station {
                navigationPath = NavigationPath([station])
                selectedStation = nil
            }
        }
        .onChange(of: searchPresented) { _, new in
            detent = new ? .large : .medium
        }
    }
    
    @ViewBuilder
    private var mainBody: some View {
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
            VStack(alignment: .leading) {
                List {
                    Section("Nearby") {
                        ForEach(stations) { station in
                            StationRow(
                                station: station,
                                selectedFuelTypeRaw: preferences.selectedFuelTypeRaw,
                                litresNeeded: litresNeeded,
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
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var searchBody: some View {
        Form {
            Section("Amenities") {
                ForEach(Amenity.allCases) { amenity in
                    Button {
                        searchAmenities.append(amenity)
                    } label: {
                        Label(amenity.displayName, systemImage: amenity.systemImage)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                litresNeeded: .constant(nil)
            )
            .presentationDetents([.fraction(0.25), .medium, .large], selection: $detent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .interactiveDismissDisabled()
        }
        
        .modelContainer(for: UserPreferences.self, inMemory: true)
}

