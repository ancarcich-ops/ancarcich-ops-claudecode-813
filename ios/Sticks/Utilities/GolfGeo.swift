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

    /// True when a server-provided lat/lng pair is safe to hand to MapKit.
    /// MapKit throws NSInvalidArgumentException (a hard crash) on
    /// out-of-range or non-finite coordinates, and (0, 0) is null-island
    /// junk from unmapped courses — all of it must degrade to "no geo"
    /// instead of crashing the GPS screen.
    static func isUsable(lat: Double, lng: Double) -> Bool {
        lat.isFinite && lng.isFinite
            && abs(lat) <= 90 && abs(lng) <= 180
            && !(lat == 0 && lng == 0)
    }

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

    /// Ray-cast point-in-polygon on lat/lng. Planar approximation — accurate
    /// enough at the scale of a green. Mirrors the web's pointInLatLngPolygon.
    static func isInside(_ p: CLLocationCoordinate2D,
                         polygon: [CLLocationCoordinate2D]) -> Bool {
        guard polygon.count >= 3 else { return false }
        let px = p.longitude, py = p.latitude
        var inside = false
        var j = polygon.count - 1
        for i in 0 ..< polygon.count {
            let xi = polygon[i].longitude, yi = polygon[i].latitude
            let xj = polygon[j].longitude, yj = polygon[j].latitude
            if ((yi > py) != (yj > py)) &&
               (px < (xj - xi) * (py - yi) / (yj - yi) + xi) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Hazards worth a distance pill: on-screen the bunker/water is always
    /// visible, but we drop the PILL when it would (a) sit inside the green
    /// polygon or (b) be past the green (not a carry on the approach) — same
    /// as the web map (`pointInLatLngPolygon` skip + `distance > pinD - 10`
    /// carry rule). `anchor` is the same reference point the pill's distance
    /// is measured from, so the "beyond the green" test agrees with the
    /// number we'd show. Shared by BOTH 2D renderers (Apple `Map` and the
    /// Esri MKMapView) so they behave identically.
    static func annotatableHazards(geo: HoleGeo?,
                                   hazards: [Hazard],
                                   anchor: CLLocationCoordinate2D?) -> [Hazard] {
        let greenPoly = geo?.greenPolygonCoordinates ?? []
        let greenCenterDist: Double? = {
            guard let anchor, let green = geo?.greenCoordinate else { return nil }
            return yards(from: anchor, to: green)
        }()
        return hazards.filter { hazard in
            guard let lat = hazard.lat, let lng = hazard.lng,
                  isUsable(lat: lat, lng: lng) else { return false }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            // (a) overlap: inside the green polygon
            if greenPoly.count >= 3, isInside(coord, polygon: greenPoly) {
                return false
            }
            // (b) beyond the green: farther from the anchor than the green
            //     center (10y buffer, mirroring the web's `pinD - 10`)
            if let anchor, let greenCenterDist {
                let d = yards(from: anchor, to: coord)
                if d > greenCenterDist - 10 { return false }
            }
            return true
        }
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
        guard let teeLat, let teeLng, GolfGeo.isUsable(lat: teeLat, lng: teeLng) else { return nil }
        return CLLocationCoordinate2D(latitude: teeLat, longitude: teeLng)
    }

    var greenCoordinate: CLLocationCoordinate2D? {
        guard let greenLat, let greenLng, GolfGeo.isUsable(lat: greenLat, lng: greenLng) else { return nil }
        return CLLocationCoordinate2D(latitude: greenLat, longitude: greenLng)
    }

    var greenFrontCoordinate: CLLocationCoordinate2D? {
        guard let greenFrontLat, let greenFrontLng,
              GolfGeo.isUsable(lat: greenFrontLat, lng: greenFrontLng) else { return nil }
        return CLLocationCoordinate2D(latitude: greenFrontLat, longitude: greenFrontLng)
    }

    var greenBackCoordinate: CLLocationCoordinate2D? {
        guard let greenBackLat, let greenBackLng,
              GolfGeo.isUsable(lat: greenBackLat, lng: greenBackLng) else { return nil }
        return CLLocationCoordinate2D(latitude: greenBackLat, longitude: greenBackLng)
    }

    /// Invalid vertices are dropped — callers already require ≥3 points
    /// before drawing the polygon.
    var greenPolygonCoordinates: [CLLocationCoordinate2D] {
        (greenPolygon ?? []).compactMap { point in
            guard GolfGeo.isUsable(lat: point.lat, lng: point.lng) else { return nil }
            return CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng)
        }
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
