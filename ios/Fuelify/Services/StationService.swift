import Foundation
import CoreLocation
import MapKit

@MainActor
@Observable
class StationService {
    var stations: [StationResponse] = []
    var isLoading = false
    var errorMessage: String?

    private let baseURL = "https://fuelify.isxander.dev"

    func fetchStations(
        near coordinate: CLLocationCoordinate2D,
        spanLatitude: Double, spanLongitude: Double,
        fuelType: FuelType = .e10,
        userLocation: CLLocationCoordinate2D? = nil
    ) async {
        isLoading = true
        errorMessage = nil

        let body = NearbyStationsRequest(
            fuelType: fuelType,
            originLat: coordinate.latitude,
            originLon: coordinate.longitude,
            spanLat: spanLatitude,
            spanLon: spanLongitude,
        )

        guard let url = URL(string: "\(baseURL)/nearby") else {
            errorMessage = "Invalid URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(NearbyStationsResponse.self, from: data)
            stations = response.results
            if let userLocation = userLocation {
                await calculateETAs(from: userLocation)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func fetchPriceHistory(stationId: String, fuelType: FuelType, interval: HistoryInterval = .last30Days) async -> [FuelPriceSample] {
        guard let url = URL(string: "\(baseURL)/price-history") else {
            return []
        }

        let body = PriceHistoryRequest(
            stationId: stationId,
            interval: interval,
            fuelType: fuelType
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(PriceHistoryResponse.self, from: data)
            return response.samples
        } catch {
            return []
        }
    }

    /// Calculates driving ETA and distance for each station from the given origin
    private func calculateETAs(from origin: CLLocationCoordinate2D) async {
        let stationCoordinates = stations.enumerated().map { (index, station) in
            (index, station.latitude, station.longitude)
        }
        let sourceLat = origin.latitude
        let sourceLon = origin.longitude

        await withTaskGroup(of: (Int, TimeInterval?, Double?).self) { group in
            for (index, lat, lon) in stationCoordinates {
                group.addTask {
                    let sourceLocation = CLLocation(latitude: sourceLat, longitude: sourceLon)
                    let sourceItem = MKMapItem(location: sourceLocation, address: nil)
                    let destinationLocation = CLLocation(latitude: lat, longitude: lon)
                    let destination = MKMapItem(location: destinationLocation, address: nil)
                    let request = MKDirections.Request()
                    request.source = sourceItem
                    request.destination = destination
                    request.transportType = .automobile

                    let directions = MKDirections(request: request)
                    do {
                        let eta = try await directions.calculateETA()
                        return (index, eta.expectedTravelTime, eta.distance)
                    } catch {
                        return (index, nil, nil)
                    }
                }
            }

            for await (index, time, distance) in group {
                if index < stations.count {
                    stations[index].driveTimeSeconds = time
                    stations[index].driveDistanceMeters = distance
                }
            }
        }
    }
}
