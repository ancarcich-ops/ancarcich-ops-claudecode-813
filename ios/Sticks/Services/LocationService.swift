//
//  LocationService.swift
//  Sticks
//
//  CoreLocation wrapper owned by RoundSessionService. Permission is
//  requested the first time `start()` is called — i.e. when the GPS
//  screen opens, never at app launch. Best accuracy with a ~5m distance
//  filter (the Live Activity only pushes on ≥5yd change, so sub-5m
//  updates are wasted battery). Background delivery is opt-in per round
//  via `setBackgroundUpdates(_:)` and torn down the moment a round ends.
//

import CoreLocation
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var horizontalAccuracyMeters: Double?
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Monotonic count of delivered GPS fixes. Lets consumers distinguish
    /// a NEW fix from re-reads of an unchanged coordinate — auto-advance
    /// counts consecutive FIXES, not observation re-runs.
    private(set) var fixSequence = 0

    private let manager = CLLocationManager()
    private var isUpdating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Battery: the companions only care about ≥5yd movement.
        manager.distanceFilter = 5
        // Golfers stand still between shots — auto-pause would kill
        // updates mid-round and never resume until foregrounded.
        manager.pausesLocationUpdatesAutomatically = false
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

    /// Enables/disables background location delivery. ON only while a
    /// round session is active (requires the `location` UIBackgroundMode
    /// declared on the app target); OFF the moment the round ends so the
    /// app never tracks outside a round. The system's background-location
    /// indicator is shown while enabled — honest, and required for
    /// when-in-use authorization to keep delivering in the background.
    func setBackgroundUpdates(_ enabled: Bool) {
        manager.allowsBackgroundLocationUpdates = enabled
        manager.showsBackgroundLocationIndicator = enabled
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
            self.fixSequence += 1
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
