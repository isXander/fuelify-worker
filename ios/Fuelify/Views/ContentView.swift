import SwiftUI
import SwiftData
import MapKit

struct ContentView: View {
    @State private var locationManager = LocationManager()
    @State private var stationService = StationService()
    @State private var selectedStation: StationResponse?
    @State private var sheetDetent: PresentationDetent = .fraction(0.25)
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showSearchHere = false
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var isFollowingUser = true
    @State private var isZoomedOut = false
    @State private var isSatelliteView = false

    /// Latitude span threshold beyond which annotations simplify to dots
    private let zoomOutThreshold: Double = 0.15

    var preferences: UserPreferences

    private var selectedFuelType: FuelType {
        preferences.selectedFuelType
    }

    private var selectedFuelTypeRaw: String {
        preferences.selectedFuelTypeRaw
    }
    
    private var allPricesForSelectedFuel: [Double] {
        stationService.stations.compactMap { station in
            station.latestFuelPrices[selectedFuelType]?.price
        }
    }

    /// Returns the price entry to display on the annotation for the user's preferred fuel type
    private func preferredPrice(for station: StationResponse) -> FuelPriceEntry? {
        if let sample = station.latestFuelPrices[selectedFuelType] {
            return FuelPriceEntry(fuelType: selectedFuelType, sample: sample)
        }
        return station.fuelPrices.first
    }

    private var searchSpan: MKCoordinateSpan {
        visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.0001, longitudeDelta: 0.0001)
    }

    private func bottomPadding(for height: CGFloat) -> CGFloat {
        if sheetDetent == .large {
            return 0
        } else if sheetDetent == .medium {
            return height * 0.55
        } else if sheetDetent == .fraction(0.25) {
            return height * 0.25
        } else {
            return height * 0.08
        }
    }

    var body: some View {
        GeometryReader { geometry in
            mapView
                .safeAreaPadding(.bottom, bottomPadding(for: geometry.size.height))
                .sheet(isPresented: .constant(true)) {
                    stationListSheet
                }
                .onChange(of: preferences.selectedFuelTypeRaw) {
                    handleFuelTypeChange()
                }
                .task {
                    await initialLoad()
                }
        }
    }

    // MARK: - Subviews

    private var mapView: some View {
        Map(position: $cameraPosition, selection: $selectedStation) {
            UserAnnotation()
            ForEach(stationService.stations) { station in
                stationAnnotation(for: station)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .top) {
            searchHereButton
        }
        .onMapCameraChange(frequency: .continuous) { context in
            let zoomed = context.region.span.latitudeDelta > zoomOutThreshold
            if zoomed != isZoomedOut {
                isZoomedOut = zoomed
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            if cameraPosition.positionedByUser {
                showSearchHere = true
                isFollowingUser = false
                selectedStation = nil
            }
        }
        .onChange(of: cameraPosition.followsUserLocation) { _, following in
            handleFollowUserChange(following: following)
        }
        .onChange(of: selectedStation) { _, newValue in
            handleSelectedStationChange(newValue)
        }
    }

    private func stationAnnotation(for station: StationResponse) -> some MapContent {
        let color = annotationColor(for: station)

        return Annotation(
            station.tradingName,
            coordinate: CLLocationCoordinate2D(
                latitude: station.latitude,
                longitude: station.longitude
            )
        ) {
            if isZoomedOut && station != selectedStation {
                Circle()
                    .fill(color)
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            } else {
                PriceAnnotationView(
                    price: preferredPrice(for: station),
                    isSupermarket: station.supermarket,
                    isMotorway: station.motorway,
                    isSelected: selectedStation == station,
                    tintColor: color
                )
            }
        }
        .tag(station)
        .annotationTitles(.hidden)
    }

    private func annotationColor(for station: StationResponse) -> Color {
        if let p = preferredPrice(for: station)?.price {
            return priceTierColor(for: p, in: allPricesForSelectedFuel)
        } else {
            return station.supermarket ? .green : .blue
        }
    }

    @ViewBuilder
    private var searchHereButton: some View {
        if showSearchHere && !stationService.isLoading {
            Button {
                searchHere()
            } label: {
                Label("Search Here", systemImage: "magnifyingglass")
            }
            .buttonStyle(.glass)
            .padding(.top, 8)
        }
    }

    private var stationListSheet: some View {
        StationListSheet(
            stations: sortedStations,
            isLoading: stationService.isLoading,
            selectedStation: $selectedStation,
            preferences: preferences
        )
        .presentationDetents([.fraction(0.1), .fraction(0.25), .medium, .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .interactiveDismissDisabled()
    }

    // MARK: - Actions

    private func handleFollowUserChange(following: Bool) {
        if following && !isFollowingUser {
            isFollowingUser = true
            showSearchHere = false
            visibleRegion = nil
            Task {
                if let location = locationManager.userLocation {
                    await stationService.fetchStations(
                        near: location.coordinate,
                        spanLatitude: visibleRegion?.span.latitudeDelta ?? 0.1,
                        spanLongitude: visibleRegion?.span.longitudeDelta ?? 0.1,
                        fuelType: selectedFuelType,
                        userLocation: location.coordinate
                    )
                }
            }
        }
    }

    private func handleSelectedStationChange(_ station: StationResponse?) {
        guard let station else { return }

        sheetDetent = .medium

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeInOut(duration: 0.3)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: station.latitude,
                        longitude: station.longitude
                    ),
                    latitudinalMeters: 1000,
                    longitudinalMeters: 1000
                ))
            }
        }
    }

    private func handleFuelTypeChange() {
        showSearchHere = false
        Task {
            let userCoord = locationManager.userLocation?.coordinate
            if cameraPosition.followsUserLocation, let userCoord {
                await stationService.fetchStations(
                    near: userCoord,
                    spanLatitude: searchSpan.latitudeDelta,
                    spanLongitude: searchSpan.longitudeDelta,
                    fuelType: selectedFuelType,
                    userLocation: userCoord
                )
            } else if let region = visibleRegion {
                await stationService.fetchStations(
                    near: region.center,
                    spanLatitude: searchSpan.latitudeDelta,
                    spanLongitude: searchSpan.longitudeDelta,
                    fuelType: selectedFuelType,
                    userLocation: userCoord
                )
            } else if let userCoord {
                await stationService.fetchStations(
                    near: userCoord,
                    spanLatitude: searchSpan.latitudeDelta,
                    spanLongitude: searchSpan.longitudeDelta,
                    fuelType: selectedFuelType,
                    userLocation: userCoord
                )
            }
        }
    }

    private func initialLoad() async {
        locationManager.requestPermission()

        while locationManager.userLocation == nil {
            try? await Task.sleep(for: .milliseconds(200))
        }

        if let location = locationManager.userLocation {
            await stationService.fetchStations(
                near: location.coordinate,
                spanLatitude: searchSpan.latitudeDelta,
                spanLongitude: searchSpan.longitudeDelta,
                fuelType: selectedFuelType,
                userLocation: location.coordinate
            )
        }
    }

    private var sortedStations: [StationResponse] {
        stationService.stations.sorted { a, b in
            switch preferences.sortOption {
            case .distance:
                return (a.driveDistanceMeters ?? .infinity) < (b.driveDistanceMeters ?? .infinity)
            case .driveTime:
                return (a.driveTimeSeconds ?? .infinity) < (b.driveTimeSeconds ?? .infinity)
            case .price:
                let aPrice = preferredPrice(for: a)?.price ?? .infinity
                let bPrice = preferredPrice(for: b)?.price ?? .infinity
                return aPrice < bPrice
            }
        }
    }

    private func searchHere() {
        Task {
            if let region = visibleRegion {
                showSearchHere = false
                await stationService.fetchStations(
                    near: region.center,
                    spanLatitude: searchSpan.latitudeDelta,
                    spanLongitude: searchSpan.longitudeDelta,
                    fuelType: selectedFuelType,
                    userLocation: locationManager.userLocation?.coordinate
                )
            }
        }
    }
}

#Preview {
    ContentView(preferences: UserPreferences())
        .modelContainer(for: UserPreferences.self, inMemory: true)
}

