import CoreLocation

@MainActor
@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var userLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            userLocation = locations.last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location request failed; userLocation remains nil
    }
}
