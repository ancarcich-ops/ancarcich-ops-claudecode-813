//
//  GolfGeo.swift
//  Sticks
//
//  Client-side golf distance math per the spec. All distances in YARDS,
//  using the haversine formula. Also bearing/midpoint helpers for the
//  hole-up map camera, and HoleGeo conveniences for front/center/back.
//

import CoreLocation

/// Front / center / back distances to the green, in yards.
nonisolated struct GreenDistances: Equatable {
    let front: Double
    let center: Double
    let back: Double
}

nonisolated enum GolfGeo {
    static let yardsPerMeter = 1.0936133

    /// A player more than ~2 miles from the hole is "not at the course" —
    /// distances anchor from the tee instead (FROM TEE mode).
    static let onCourseThresholdYards: Double = 3_520

    /// FIX TEE requires GPS accuracy of ±35y or better (server rejects worse).
    static let maxTeeFixAccuracyYards: Double = 35

    /// Haversine distance in yards.
    static func yards(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLng = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * 6_371_000 * asin(sqrt(min(1, h))) * yardsPerMeter
    }

    /// Initial bearing from `a` to `b` in degrees (0–360, 0 = north).
    /// Used as the map camera heading so tee→green points up-screen.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLng = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Simple midpoint — accurate enough at hole scale (< 700 yds).
    static func midpoint(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (a.latitude + b.latitude) / 2,
            longitude: (a.longitude + b.longitude) / 2
        )
    }

    /// Destination point `meters` away from `origin` along `bearing`
    /// (degrees, 0 = north). Used to slide the map camera center up-course
    /// so the framed hole clears the top rail overlay.
    static func coordinate(
        from origin: CLLocationCoordinate2D,
        bearing: Double,
        meters: Double
    ) -> CLLocationCoordinate2D {
        let angular = meters / 6_371_000
        let bearingRad = bearing * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lng1 = origin.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearingRad))
        let lng2 = lng1 + atan2(
            sin(bearingRad) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lng2 * 180 / .pi)
    }

    /// Signed projection of `point` onto the hole axis, in meters from
    /// `origin` along `heading` (positive = up-course, toward the green).
    /// Used to fit tee, green, and hazards inside the map's visible band.
    static func upCourseMeters(
        of point: CLLocationCoordinate2D,
        from origin: CLLocationCoordinate2D,
        heading: Double
    ) -> Double {
        let distanceMeters = yards(from: origin, to: point) / yardsPerMeter
        guard distanceMeters > 0 else { return 0 }
        let delta = (bearing(from: origin, to: point) - heading) * .pi / 180
        return distanceMeters * cos(delta)
    }
}

extension HoleGeo {
    var teeCoordinate: CLLocationCoordinate2D? {
        guard let teeLat, let teeLng else { return nil }
        return CLLocationCoordinate2D(latitude: teeLat, longitude: teeLng)
    }

    var greenCoordinate: CLLocationCoordinate2D? {
        guard let greenLat, let greenLng else { return nil }
        return CLLocationCoordinate2D(latitude: greenLat, longitude: greenLng)
    }

    var greenFrontCoordinate: CLLocationCoordinate2D? {
        guard let greenFrontLat, let greenFrontLng else { return nil }
        return CLLocationCoordinate2D(latitude: greenFrontLat, longitude: greenFrontLng)
    }

    var greenBackCoordinate: CLLocationCoordinate2D? {
        guard let greenBackLat, let greenBackLng else { return nil }
        return CLLocationCoordinate2D(latitude: greenBackLat, longitude: greenBackLng)
    }

    var greenPolygonCoordinates: [CLLocationCoordinate2D] {
        (greenPolygon ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    /// FRONT / CENTER / BACK from an anchor point, per the spec:
    /// - CENTER = anchor → green center
    /// - FRONT = min distance to any green polygon vertex; else the
    ///   greenFront point; else CENTER − 8
    /// - BACK  = max distance to any vertex; else greenBack; else CENTER + 8
    func distances(from anchor: CLLocationCoordinate2D) -> GreenDistances? {
        guard let green = greenCoordinate else { return nil }
        let center = GolfGeo.yards(from: anchor, to: green)

        let vertexDistances = greenPolygonCoordinates.map { GolfGeo.yards(from: anchor, to: $0) }
        let front: Double
        let back: Double
        if let minVertex = vertexDistances.min(), let maxVertex = vertexDistances.max() {
            front = minVertex
            back = maxVertex
        } else {
            front = greenFrontCoordinate.map { GolfGeo.yards(from: anchor, to: $0) } ?? center - 8
            back = greenBackCoordinate.map { GolfGeo.yards(from: anchor, to: $0) } ?? center + 8
        }
        return GreenDistances(front: front, center: center, back: back)
    }
}
