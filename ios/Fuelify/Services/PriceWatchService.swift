import Foundation

@MainActor
@Observable
class PriceWatchService {
    private(set) var watchedStations: [WatchedStation] = []
    private(set) var isLoading = false

    private let baseURL = "https://fuelify.isxander.dev"
    private let userIdKey = "fuelify_user_id"

    var userId: String? {
        UserDefaults.standard.string(forKey: userIdKey)
    }

    // MARK: - User Registration

    /// Registers a new user if one doesn't already exist. Call on first launch.
    func ensureRegistered() async {
        if userId != nil { return }
        await registerUser()
    }

    private func registerUser() async {
        guard let url = URL(string: "\(baseURL)/users/register") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(RegisterUserResponse.self, from: data)
            UserDefaults.standard.set(response.userId, forKey: userIdKey)
        } catch {
            print("Failed to register user: \(error)")
        }
    }

    // MARK: - Device Registration

    func registerDevice(token: String) async {
        guard let userId else { return }
        guard let url = URL(string: "\(baseURL)/devices/register") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RegisterDeviceRequest(userId: userId, deviceToken: token)
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (_, _) = try await URLSession.shared.data(for: request)
        } catch {
            print("Failed to register device: \(error)")
        }
    }

    // MARK: - Watch / Unwatch

    func watchStation(stationId: String, fuelType: FuelType) async {
        guard let userId else { return }
        guard let url = URL(string: "\(baseURL)/watch/station") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = WatchStationRequest(userId: userId, stationId: stationId, fuelType: fuelType)
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (_, _) = try await URLSession.shared.data(for: request)
            await fetchWatches()
        } catch {
            print("Failed to watch station: \(error)")
        }
    }

    func unwatchStation(stationId: String, fuelType: FuelType) async {
        guard let userId else { return }
        guard let url = URL(string: "\(baseURL)/watch/station") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = WatchStationRequest(userId: userId, stationId: stationId, fuelType: fuelType)
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (_, _) = try await URLSession.shared.data(for: request)
            await fetchWatches()
        } catch {
            print("Failed to unwatch station: \(error)")
        }
    }

    // MARK: - List Watches

    func fetchWatches() async {
        guard let userId else { return }
        guard let url = URL(string: "\(baseURL)/watches?user_id=\(userId)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ListWatchesResponse.self, from: data)
            watchedStations = response.stations
        } catch {
            print("Failed to fetch watches: \(error)")
        }
    }

    // MARK: - Helpers

    func isWatching(stationId: String, fuelType: FuelType) -> Bool {
        watchedStations.contains { $0.stationId == stationId && $0.fuelType == fuelType }
    }
}

// MARK: - API Types

private struct RegisterUserResponse: Decodable {
    let userId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

private struct RegisterDeviceRequest: Encodable {
    let userId: String
    let deviceToken: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case deviceToken = "device_token"
    }
}

private struct WatchStationRequest: Encodable {
    let userId: String
    let stationId: String
    let fuelType: FuelType

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case stationId = "station_id"
        case fuelType = "fuel_type"
    }
}

struct WatchedStation: Decodable, Identifiable {
    let stationId: String
    let tradingName: String
    let brandName: String
    let fuelType: FuelType

    var id: String { "\(stationId)-\(fuelType.rawValue)" }

    enum CodingKeys: String, CodingKey {
        case stationId = "station_id"
        case tradingName = "trading_name"
        case brandName = "brand_name"
        case fuelType = "fuel_type"
    }
}

private struct ListWatchesResponse: Decodable {
    let stations: [WatchedStation]
}
