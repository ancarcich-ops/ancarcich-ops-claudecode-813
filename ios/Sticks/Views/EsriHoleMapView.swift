//
//  EsriHoleMapView.swift
//  Sticks
//
//  Slice 66: the Esri World Imagery renderer for the on-course 2D map.
//  SwiftUI's `Map` can only draw Apple's basemap, so this is a small
//  MKMapView (UIViewRepresentable) with an EsriImageryTileOverlay on top
//  of Apple satellite (the automatic fallback for any failed tile). It
//  reproduces exactly what OnCourseGPSView.mapContent draws — the green
//  polygon, tee/pin/hazard/aim markers (the SAME SwiftUI views, hosted
//  via UIHostingConfiguration), the dashed aim lines, and tap-to-aim —
//  and mirrors the TEE/GREEN/HOLE camera framing math, so ONLY the
//  imagery differs from the Apple path.
//

import MapKit
import SwiftUI

struct EsriHoleMapView: UIViewRepresentable {
    let geo: HoleGeo?
    let hazards: [Hazard]
    let anchorCoordinate: CLLocationCoordinate2D?
    let aim: CLLocationCoordinate2D?
    let greenForAim: CLLocationCoordinate2D?
    let cameraMode: GPSCameraMode
    let holeIndex: Int
    let onAim: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView
        // Apple imagery underneath = the automatic fallback wherever an
        // Esri tile is missing or fails (canReplaceMapContent is false).
        mapView.mapType = .satellite
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true
        mapView.isPitchEnabled = false   // flat, like the 2D Apple map
        mapView.isRotateEnabled = true
        mapView.showsCompass = false
        mapView.addOverlay(EsriImageryTileOverlay(), level: .aboveLabels)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        mapView.addGestureRecognizer(tap)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        let contentKey = contentFingerprint
        if coordinator.lastContentKey != contentKey {
            coordinator.lastContentKey = contentKey
            coordinator.reconcileContent(on: mapView)
        }

        // Reframe on mode/hole change AND when the geo's key coordinates
        // arrive from the fetch (tee/green presence flips false → true).
        let cameraKey = "\(cameraMode.rawValue)-\(holeIndex)-\(geo?.teeCoordinate != nil)-\(geo?.greenCoordinate != nil)"
        if coordinator.lastCameraKey != cameraKey {
            let animated = coordinator.lastCameraKey != nil
            coordinator.lastCameraKey = cameraKey
            coordinator.reframeCamera(on: mapView, animated: animated)
        }
    }

    /// Change signature for the map content. The anchor is rounded to
    /// ~1 m so a GPS tick only rebuilds annotations when the player has
    /// actually moved (hazard chip distances are whole yards anyway).
    private var contentFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(geo)
        hasher.combine(hazards)
        hasher.combine(anchorCoordinate.map { Int(($0.latitude * 1e5).rounded()) })
        hasher.combine(anchorCoordinate.map { Int(($0.longitude * 1e5).rounded()) })
        hasher.combine(aim?.latitude)
        hasher.combine(aim?.longitude)
        hasher.combine(greenForAim?.latitude)
        hasher.combine(greenForAim?.longitude)
        return hasher.finalize()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: EsriHoleMapView
        weak var mapView: MKMapView?

        var lastContentKey: Int?
        var lastCameraKey: String?

        private var greenPolygon: MKPolygon?
        private var anchorAimLine: MKPolyline?
        private var aimGreenLine: MKPolyline?
        private var markerAnnotations: [EsriMarkerAnnotation] = []

        init(parent: EsriHoleMapView) {
            self.parent = parent
        }

        // MARK: Tap-to-aim (mirrors the MapReader tap on the Apple path)

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onAim(coordinate)
        }

        // MARK: Content reconciliation

        /// Removes our overlays/annotations and re-adds them from the
        /// current inputs — the hole geometry is small, so a full swap
        /// is cheaper than diffing. The tile overlay is never touched.
        func reconcileContent(on mapView: MKMapView) {
            var stale: [MKOverlay] = []
            if let greenPolygon { stale.append(greenPolygon) }
            if let anchorAimLine { stale.append(anchorAimLine) }
            if let aimGreenLine { stale.append(aimGreenLine) }
            if !stale.isEmpty { mapView.removeOverlays(stale) }
            greenPolygon = nil
            anchorAimLine = nil
            aimGreenLine = nil

            if !markerAnnotations.isEmpty {
                mapView.removeAnnotations(markerAnnotations)
                markerAnnotations = []
            }

            if let geo = parent.geo {
                let vertices = geo.greenPolygonCoordinates
                if vertices.count >= 3 {
                    let polygon = MKPolygon(coordinates: vertices, count: vertices.count)
                    mapView.addOverlay(polygon, level: .aboveLabels)
                    greenPolygon = polygon
                }
                if let tee = geo.teeCoordinate {
                    markerAnnotations.append(EsriMarkerAnnotation(kind: .tee, coordinate: tee))
                }
                if let green = geo.greenCoordinate {
                    markerAnnotations.append(EsriMarkerAnnotation(kind: .pin, coordinate: green))
                }
            }

            // Slice 67: the same pill filter as the Apple path — no pill on
            // hazards that sit ON the green polygon or PAST the green. The
            // camera framing above still uses the raw list, matching the
            // Apple renderer's framing math exactly.
            let shownHazards = GolfGeo.annotatableHazards(
                geo: parent.geo,
                hazards: parent.hazards,
                anchor: parent.anchorCoordinate
            )
            for hazard in shownHazards {
                guard let lat = hazard.lat, let lng = hazard.lng,
                      GolfGeo.isUsable(lat: lat, lng: lng) else { continue }
                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                let distance = parent.anchorCoordinate.map { GolfGeo.yards(from: $0, to: coordinate) }
                markerAnnotations.append(
                    EsriMarkerAnnotation(kind: .hazard(hazard, distance), coordinate: coordinate)
                )
            }

            if let aim = parent.aim, let anchor = parent.anchorCoordinate {
                let anchorLine = MKPolyline(coordinates: [anchor, aim], count: 2)
                mapView.addOverlay(anchorLine, level: .aboveLabels)
                anchorAimLine = anchorLine
                if let green = parent.greenForAim {
                    let greenLine = MKPolyline(coordinates: [aim, green], count: 2)
                    mapView.addOverlay(greenLine, level: .aboveLabels)
                    aimGreenLine = greenLine
                }
                markerAnnotations.append(EsriMarkerAnnotation(kind: .aim, coordinate: aim))
            }

            if !markerAnnotations.isEmpty {
                mapView.addAnnotations(markerAnnotations)
            }
        }

        // MARK: Camera (mirrors OnCourseGPSView's snapCamera framing)

        func reframeCamera(on mapView: MKMapView, animated: Bool) {
            guard let geo = parent.geo,
                  let camera = Self.camera(mode: parent.cameraMode, geo: geo, hazards: parent.hazards)
            else { return }
            mapView.setCamera(camera, animated: animated)
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            if let polygon = overlay as? MKPolygon {
                // Matches mapContent's MapPolygon styling.
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = UIColor.white.withAlphaComponent(0.08)
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.9)
                renderer.lineWidth = 1.5
                return renderer
            }
            if let line = overlay as? MKPolyline {
                // Matches mapContent's dashed aim lines.
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.lineWidth = 2
                if line === aimGreenLine {
                    renderer.strokeColor = UIColor.white.withAlphaComponent(0.55)
                    renderer.lineDashPattern = [3, 5]
                } else {
                    renderer.strokeColor = .white
                    renderer.lineDashPattern = [6, 5]
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // MKUserLocation (and anything else) → default blue dot.
            guard let marker = annotation as? EsriMarkerAnnotation else { return nil }

            let identifier = marker.reuseIdentifier
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: marker, reuseIdentifier: identifier)
            view.annotation = marker
            view.canShowCallout = false
            view.displayPriority = .required
            configure(view, for: marker)
            return view
        }

        /// Hosts the SAME SwiftUI marker views the Apple map's
        /// Annotations use, so markers are pixel-identical.
        private func configure(_ view: MKAnnotationView, for marker: EsriMarkerAnnotation) {
            view.subviews.forEach { $0.removeFromSuperview() }

            let content: UIView
            switch marker.kind {
            case .tee:
                content = Self.hosted(TeeMarker())
            case .pin:
                content = Self.hosted(PinMarker())
            case .aim:
                content = Self.hosted(AimMarker())
            case .hazard(let hazard, let distance):
                content = Self.hosted(HazardChip(hazard: hazard, distanceYards: distance))
            }

            var size = content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            if size.width < 1 || size.height < 1 {
                size = content.intrinsicContentSize
            }
            content.frame = CGRect(origin: .zero, size: size)
            content.isUserInteractionEnabled = false   // taps pass through to tap-to-aim
            view.bounds = CGRect(origin: .zero, size: size)
            view.centerOffset = .zero   // centered on the coordinate, like SwiftUI Annotation
            view.addSubview(content)
        }

        private static func hosted<Marker: View>(_ marker: Marker) -> UIView {
            let content = UIHostingConfiguration { marker }
                .margins(.all, 0)
                .makeContentView()
            content.backgroundColor = .clear
            return content
        }

        // MARK: Framing math (mirrors OnCourseGPSView's camera helpers)

        /// Same layout fractions as OnCourseGPSView — the merged top row
        /// and the bottom readout panel — so both renderers frame holes
        /// identically. Keep in sync with that file.
        private static let cameraTopFraction = 0.20
        private static let cameraBottomFraction = 0.30
        private static let groundSpanPerDistance = 0.75

        private static func camera(mode: GPSCameraMode, geo: HoleGeo, hazards: [Hazard]) -> MKMapCamera? {
            switch mode {
            case .hole, .threeD: holeCamera(geo: geo, hazards: hazards)
            case .tee: teeCamera(geo: geo)
            case .green: greenCamera(geo: geo)
            }
        }

        /// HOLE: fits tee + green + hazards into the visible band between
        /// the top rail row and the bottom panel, rotated so tee→green
        /// points up-screen.
        private static func holeCamera(geo: HoleGeo, hazards: [Hazard]) -> MKMapCamera? {
            if let tee = geo.teeCoordinate, let green = geo.greenCoordinate {
                let heading = GolfGeo.bearing(from: tee, to: green)
                let midpoint = GolfGeo.midpoint(tee, green)

                var points = [tee, green]
                points += hazards.compactMap { hazard -> CLLocationCoordinate2D? in
                    guard let lat = hazard.lat, let lng = hazard.lng,
                          GolfGeo.isUsable(lat: lat, lng: lng) else { return nil }
                    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
                let projections = points.map {
                    GolfGeo.upCourseMeters(of: $0, from: midpoint, heading: heading)
                }
                let upMost = projections.max() ?? 0
                let downMost = projections.min() ?? 0

                let usable = 1 - cameraTopFraction - cameraBottomFraction
                let minSpan = 380 * groundSpanPerDistance
                let span = max((upMost - downMost) / usable, minSpan)
                let centerOffset = upMost - span * (0.5 - cameraTopFraction)
                let center = GolfGeo.coordinate(from: midpoint, bearing: heading, meters: centerOffset)
                let distance = span / groundSpanPerDistance
                guard GolfGeo.isUsable(lat: center.latitude, lng: center.longitude),
                      distance.isFinite, distance > 0, heading.isFinite else { return nil }
                return MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: 0, heading: heading)
            }
            if let single = geo.teeCoordinate ?? geo.greenCoordinate {
                return MKMapCamera(lookingAtCenter: single, fromDistance: 700, pitch: 0, heading: 0)
            }
            return nil
        }

        /// TEE: tight top-down on the tee box, heading tee→green.
        private static func teeCamera(geo: HoleGeo) -> MKMapCamera? {
            guard let tee = geo.teeCoordinate else { return nil }
            let heading = geo.greenCoordinate.map { GolfGeo.bearing(from: tee, to: $0) } ?? 0
            guard heading.isFinite else { return nil }
            return MKMapCamera(lookingAtCenter: tee, fromDistance: 200, pitch: 0, heading: heading)
        }

        /// GREEN: centered on the green, zoomed so the polygon plus
        /// greenside bunkers read; ~120m floor without a polygon.
        private static func greenCamera(geo: HoleGeo) -> MKMapCamera? {
            guard let green = geo.greenCoordinate else { return nil }
            let heading = geo.teeCoordinate.map { GolfGeo.bearing(from: $0, to: green) } ?? 0
            guard heading.isFinite else { return nil }

            var distance: Double = 120
            let vertices = geo.greenPolygonCoordinates
            if vertices.count >= 3 {
                let radiusMeters = vertices
                    .map { GolfGeo.yards(from: green, to: $0) / GolfGeo.yardsPerMeter }
                    .max() ?? 0
                let span = (radiusMeters * 2) / 0.4
                distance = max(span / groundSpanPerDistance, 120)
            }
            guard distance.isFinite, distance > 0 else { return nil }
            return MKMapCamera(lookingAtCenter: green, fromDistance: distance, pitch: 0, heading: heading)
        }
    }
}

// MARK: - Marker annotation

/// Carries which SwiftUI marker view the annotation hosts. Nonisolated:
/// MKAnnotation's requirements aren't main-actor-bound, and the payload
/// is all value types.
private nonisolated final class EsriMarkerAnnotation: NSObject, MKAnnotation {
    enum Kind {
        case tee
        case pin
        case aim
        case hazard(Hazard, Double?)
    }

    let kind: Kind
    let coordinate: CLLocationCoordinate2D

    init(kind: Kind, coordinate: CLLocationCoordinate2D) {
        self.kind = kind
        self.coordinate = coordinate
        super.init()
    }

    var reuseIdentifier: String {
        switch kind {
        case .tee: "esri-tee"
        case .pin: "esri-pin"
        case .aim: "esri-aim"
        case .hazard: "esri-hazard"
        }
    }
}
