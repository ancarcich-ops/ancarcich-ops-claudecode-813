//
//  LocationService.swift
//  Sticks
//
//  CoreLocation wrapper for the on-course screen. Permission is requested
//  the first time `start()` is called — i.e. when the GPS screen opens,
//  never at app launch. Best accuracy, continuous (~1s) updates while the
//  screen is visible; `stop()` on disappear.
//

import CoreLocation
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var horizontalAccuracyMeters: Double?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var isUpdating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        authorizationStatus = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// GPS accuracy in yards, if a fix exists.
    var horizontalAccuracyYards: Double? {
        horizontalAccuracyMeters.map { $0 * GolfGeo.yardsPerMeter }
    }

    /// Requests when-in-use permission (first call only) and starts updates.
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdates()
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    private func beginUpdates() {
        guard !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let coordinate = latest.coordinate
        let accuracy = latest.horizontalAccuracy
        Task { @MainActor in
            self.coordinate = coordinate
            self.horizontalAccuracyMeters = accuracy >= 0 ? accuracy : nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.beginUpdates()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS errors are expected (e.g. simulator with no fix);
        // the UI degrades to FROM TEE mode automatically.
    }
}
