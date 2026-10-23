import CoreLocation

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Best-effort current location. Returns nil if it's denied or takes too long.
    func current(timeout: TimeInterval = 8) async -> CLLocation? {
        if let recent = manager.location, abs(recent.timestamp.timeIntervalSinceNow) < 60 {
            return recent
        }
        return await withCheckedContinuation { cont in
            waiters.append(cont)
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                resolve(nil)
                return
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.resolve(self.manager.location)
            }
        }
    }

    private func resolve(_ location: CLLocation?) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.resolve(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resolve(self.manager.location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard !self.waiters.isEmpty else { return }
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: self.resolve(nil)
            default: break
            }
        }
    }

    /// Street address in English (for Alex, drivers, 911).
    func address(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US"))
        guard let p = placemarks?.first else { return nil }
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street, p.locality, p.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func mapsLink(_ location: CLLocation) -> String {
        String(format: "https://maps.apple.com/?ll=%.6f,%.6f&q=Standort", location.coordinate.latitude, location.coordinate.longitude)
    }
}
