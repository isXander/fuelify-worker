import SwiftUI
import SwiftData
import MapKit

struct ContentView: View {
    @State private var locationManager = LocationManager()
    @State private var stationService = StationService()
    @State private var viewModel = StationListViewModel()
    
    @State private var sheetDetent: PresentationDetent = .fraction(0.25)
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var trackedVisibleRegion: MKCoordinateRegion?
    
    @State private var isFollowingUser = true
    @State private var isZoomedOut = false
    @State private var selectedStation: StationResponse?
    @State private var showSearchHere = false

    /// Latitude span threshold beyond which annotations simplify to dots
    private let zoomOutThreshold: Double = 0.15

    var preferences: UserPreferences

    private var selectedFuelType: FuelType {
        preferences.selectedFuelType
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
    
    private var visibleRegion: MKCoordinateRegion? {
        cameraPosition.region ?? trackedVisibleRegion
    }

    private var searchSpan: MKCoordinateSpan {
        visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
    }
    
    private var bottomMapPadding: Double {
        switch sheetDetent {
        case .large, .medium:
            return 0.55
        case .fraction(0.25):
            return 0.25
        case .fraction(0.1):
            return 0.08
        default:
            return 0.0
        }
    }

    var body: some View {
        mapView
            // allow the maps legal attribution to be visible on minimum detent
            .safeAreaPadding(.bottom, 60)
            .sheet(isPresented: .constant(true)) {
                stationListSheet
            }
            .onChange(of: preferences.selectedFuelType) {
                handleFuelTypeChange()
            }
            .task {
                await initialLoad()
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
        }
        // Apple Maps has this anchored above the sheet but I haven't found a way to reimplement this
        .overlay(alignment: .top) {
            searchHereButton
        }
        // Reduce footprint of annotations when there are lots of them on the screen close together
        .onMapCameraChange(frequency: .continuous) { context in
            let zoomed = context.region.span.latitudeDelta > zoomOutThreshold
            if zoomed != isZoomedOut {
                isZoomedOut = zoomed
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            trackedVisibleRegion = context.region
            if cameraPosition.positionedByUser {
                showSearchHere = true
                isFollowingUser = false
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
            StationAnnotationContent(
                station: station,
                viewModel: viewModel,
                isZoomedOut: isZoomedOut,
                isSelected: selectedStation == station,
                color: color,
                price: preferredPrice(for: station)
            )
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
            stations: stationService.stations,
            isLoading: stationService.isLoading,
            selectedStation: $selectedStation,
            detent: $sheetDetent,
            preferences: preferences,
            viewModel: viewModel
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
            trackedVisibleRegion = nil
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
        guard let station else {
            print("station gone")
            return
        }

        sheetDetent = .medium
        
        focusMapOnPoint(
            station.location.coordinate,
            skipIfInView: !isZoomedOut,
            zoomLon: 0.007,
        )
    }
    
    private func focusMapOnPoint(_ point: CLLocationCoordinate2D, skipIfInView: Bool = false, zoomLon: CLLocationDegrees? = nil) {
        if let visibleRegion {
            let bottomPadding = bottomMapPadding
            
            let center = visibleRegion.center
            let span = visibleRegion.span
            let spanRatio = span.latitudeDelta / span.longitudeDelta
            
            let targetSpan = if let zoomLon {
                MKCoordinateSpan(
                    latitudeDelta: zoomLon * spanRatio,
                    longitudeDelta: zoomLon,
                )
            } else {
                span
            }
            
            let sheetOffset = targetSpan.latitudeDelta * bottomPadding / 2.0
            let paddedCenterLat = point.latitude - sheetOffset
            
            let targetCenter = CLLocationCoordinate2D(
                latitude: paddedCenterLat,
                longitude: point.longitude,
            )
            
            let halfSpanLat = span.latitudeDelta / 2.0
            let halfSpanLon = span.longitudeDelta / 2.0
            let isNotInView = targetCenter.latitude > center.latitude + halfSpanLat || targetCenter.latitude < center.latitude - halfSpanLat || targetCenter.longitude > center.longitude + halfSpanLon || targetCenter.longitude < center.longitude - halfSpanLon
            
            if isNotInView || !skipIfInView {
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: targetCenter,
                            span: targetSpan,
                        ))
                    }
                }
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

// MARK: - Annotation content view
// Extracted into its own View so SwiftUI can independently observe
// the @Observable viewModel and re-render when filter state changes.

private struct StationAnnotationContent: View {
    let station: StationResponse
    var viewModel: StationListViewModel
    let isZoomedOut: Bool
    let isSelected: Bool
    let color: Color
    let price: FuelPriceEntry?

    var body: some View {
        let matchesFilter = viewModel.passesFilter(station)

        Group {
            if isZoomedOut && !isSelected {
                Circle()
                    .fill(color)
                    .stroke(Color.white, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
            } else {
                PriceAnnotationView(
                    price: price,
                    isSupermarket: station.supermarket,
                    isMotorway: station.motorway,
                    isSelected: isSelected,
                    tintColor: color,
                    litresNeeded: viewModel.litresNeeded
                )
            }
        }
        .opacity(matchesFilter ? 1.0 : 0.15)
        .animation(.easeInOut(duration: 0.2), value: matchesFilter)
    }
}

#Preview {
    ContentView(preferences: UserPreferences())
        .modelContainer(for: UserPreferences.self, inMemory: true)
}

