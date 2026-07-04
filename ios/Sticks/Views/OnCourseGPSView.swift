//
//  OnCourseGPSView.swift
//  Sticks
//
//  Slice 4: full-screen satellite map per hole with live distances.
//  - Camera fits tee + green, rotated so tee→green points up-screen.
//  - Distances anchor from the player when GPS is available AND the player
//    is within ~2 miles of the hole; otherwise from the tee ("FROM TEE"),
//    so the screen works in the simulator and when previewing from home.
//  - Tap the map to set an AIM point (anchor→aim and aim→green).
//  - Location permission is requested when this screen first opens.
//
//  Companions (Live Activity + watch snapshot) are ROUND-scoped, not
//  screen-scoped: this view starts the round session on appear and feeds
//  it the displayed hole, but RoundSessionService owns the update loop —
//  leaving this screen does NOT end the activity.
//

import SwiftUI
import MapKit

struct OnCourseGPSView: View {
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var holeIndex = 0
    @State private var aim: CLLocationCoordinate2D?
    @State private var scoreCell: ScoreCellSelection?
    @State private var showFixTee = false
    @State private var hasInitialized = false
    @State private var isFinishing = false
    @State private var finishError: String?

    /// Round-scoped location source — owned by the session service so
    /// GPS updates (and the companions they feed) survive leaving this
    /// screen while a round is live.
    private var locationService: LocationService { RoundSessionService.shared.location }

    /// Where distances are measured from.
    private struct DistanceAnchor {
        let coordinate: CLLocationCoordinate2D
        let isPlayer: Bool
        var prefix: String { isPlayer ? "TO PIN" : "FROM TEE" }
        var originName: String { isPlayer ? "YOU" : "TEE" }
    }

    var body: some View {
        Group {
            if let detail = viewModel.detail {
                courseMap(detail)
            } else {
                ZStack {
                    Color.sticksBg.ignoresSafeArea()
                    ProgressView().tint(Color.sticksGreen)
                }
            }
        }
        // The system nav bar is fully hidden — the custom back button sits
        // on the hole rail row, reclaiming a full row of map space.
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            RoundSessionService.shared.gpsScreenAppeared()
            initializeIfNeeded()
            RoundSessionService.shared.beginRound(viewModel: viewModel, holeIndex: holeIndex, session: session)
        }
        .onDisappear {
            // Round-scoped: the Live Activity, watch snapshot, and
            // background location persist past this screen. The session
            // stops foreground location only when no round is active.
            RoundSessionService.shared.gpsScreenDisappeared()
        }
        // An UPCOMING match can flip to IN_PROGRESS via the poll while
        // this screen is open — start the round session when it does.
        .onChange(of: viewModel.detail?.status) { _, status in
            if status == .inProgress {
                RoundSessionService.shared.beginRound(viewModel: viewModel, holeIndex: holeIndex, session: session)
            }
        }
        // Slice 7.2: GPS auto-advance — when the round session advances
        // the hole from a location fix, this screen follows with the same
        // transition as a manual rail tap (the holeIndex onChange clears
        // the aim and reframes the camera). Light haptic, no alert.
        .onChange(of: RoundSessionService.shared.holeIndex) { _, newIndex in
            guard hasInitialized,
                  let detail = viewModel.detail,
                  RoundSessionService.shared.activeMatchId == detail.id,
                  newIndex != holeIndex,
                  newIndex < detail.holes else { return }
            withAnimation { holeIndex = newIndex }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .sheet(item: $scoreCell) { cell in
            ScoreEntryView(cell: cell, viewModel: viewModel, session: session) {
                advanceHole(afterCompleting: cell.hole)
            }
        }
        .sheet(isPresented: $showFixTee) {
            if let detail = viewModel.detail {
                let hole = detail.holeNumber(at: holeIndex)
                FixTeeView(
                    viewModel: viewModel,
                    session: session,
                    locationService: locationService,
                    hole: hole,
                    geo: viewModel.response?.holeGeo[hole]
                )
            }
        }
    }

    // MARK: - Map

    private func courseMap(_ detail: MatchDetail) -> some View {
        let hole = detail.holeNumber(at: holeIndex)
        let geo = viewModel.response?.holeGeo[hole]
        let hazards = viewModel.response?.hazards[hole] ?? []
        let anchor = currentAnchor(geo)

        return MapReader { proxy in
            Map(position: $camera) {
                mapContent(geo: geo, hazards: hazards, anchor: anchor)
            }
            .mapStyle(.imagery(elevation: .flat))
            .onTapGesture { screenPoint in
                guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                aim = coordinate
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 10) {
                // Back button and hole rail share one row: the button is
                // fixed at the leading edge, chips scroll behind it and
                // fade out under it (see HoleRailView's leading mask).
                ZStack(alignment: .leading) {
                    HoleRailView(detail: detail, scores: myScores(detail), selectedIndex: $holeIndex)
                    backButton
                        .padding(.leading, 12)
                }
                if let wind = viewModel.response?.wind {
                    WindTile(wind: wind)
                        .padding(.trailing, 12)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomPanel(detail: detail, geo: geo, anchor: anchor)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .onChange(of: holeIndex) { _, newIndex in
            aim = nil
            RoundSessionService.shared.setHole(index: newIndex, matchId: detail.id)
            frameCurrentHole(detail, animated: true)
        }
    }

    /// Fixed back button on the hole rail row — chips scroll past it.
    /// Kept at 44×44 (not shrunk to chip height) and centered vertically
    /// against the chips by the enclosing ZStack.
    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.55))
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
        .environment(\.colorScheme, .dark)
        .accessibilityLabel("Back")
    }

    @MapContentBuilder
    private func mapContent(geo: HoleGeo?, hazards: [Hazard], anchor: DistanceAnchor?) -> some MapContent {
        UserAnnotation()

        if let geo, geo.greenPolygonCoordinates.count >= 3 {
            MapPolygon(coordinates: geo.greenPolygonCoordinates)
                .foregroundStyle(.white.opacity(0.08))
                .stroke(.white.opacity(0.9), lineWidth: 1.5)
        }

        if let tee = geo?.teeCoordinate {
            Annotation("", coordinate: tee) {
                TeeMarker()
            }
        }

        if let green = geo?.greenCoordinate {
            Annotation("", coordinate: green) {
                PinMarker()
            }
        }

        ForEach(0 ..< hazards.count, id: \.self) { index in
            let hazard = hazards[index]
            if let lat = hazard.lat, let lng = hazard.lng {
                let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                Annotation("", coordinate: coordinate) {
                    HazardChip(
                        hazard: hazard,
                        distanceYards: anchor.map { GolfGeo.yards(from: $0.coordinate, to: coordinate) }
                    )
                }
            }
        }

        if let aim, let anchor {
            MapPolyline(coordinates: [anchor.coordinate, aim])
                .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            if let green = viewModel.detail.flatMap({ detail in
                viewModel.response?.holeGeo[detail.holeNumber(at: holeIndex)]?.greenCoordinate
            }) {
                MapPolyline(coordinates: [aim, green])
                    .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [3, 5]))
            }
            Annotation("", coordinate: aim) {
                AimMarker()
            }
        }
    }

    // MARK: - Bottom panel

    private func bottomPanel(detail: MatchDetail, geo: HoleGeo?, anchor: DistanceAnchor?) -> some View {
        let hole = detail.holeNumber(at: holeIndex)
        let distances = anchor.flatMap { geo?.distances(from: $0.coordinate) }

        return VStack(spacing: 12) {
            if geo?.greenCoordinate == nil {
                greenNeededBanner
            } else if let anchor, let distances {
                readout(anchor: anchor, distances: distances)
            } else {
                Text("NO GPS DATA FOR THIS HOLE")
                    .font(SticksFont.label(12))
                    .kerning(1.4)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.vertical, 14)
            }

            if let aim, let anchor {
                aimRow(anchor: anchor, aim: aim, green: geo?.greenCoordinate)
            }

            statusRow(detail: detail, anchor: anchor)

            if canFinishRound(detail) {
                if let finishError {
                    Text(finishError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                finishRoundButton
            }

            if detail.canEnterScores {
                Button {
                    openScoreSheet(detail, hole: hole)
                } label: {
                    Text(viewModel.isRoundComplete ? "EDIT A SCORE" : "ENTER SCORE")
                        .font(SticksFont.label(14, weight: .bold))
                        .kerning(2)
                        .foregroundStyle(Color.sticksCream)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.sticksGreen)
                        .clipShape(.rect(cornerRadius: 13))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(14)
        .background(.black.opacity(0.55))
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    private func readout(anchor: DistanceAnchor, distances: GreenDistances) -> some View {
        VStack(spacing: 2) {
            Text("\(anchor.prefix) · CENTER")
                .font(SticksFont.label(11))
                .kerning(2)
                .foregroundStyle(.white.opacity(0.65))

            HStack(alignment: .firstTextBaseline, spacing: 22) {
                flankDistance(label: "FRONT", yards: distances.front)
                Text("\(Int(distances.center.rounded()))")
                    .font(SticksFont.display(58))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: Int(distances.center.rounded()))
                flankDistance(label: "BACK", yards: distances.back)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func flankDistance(label: String, yards: Double) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(SticksFont.label(9))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.55))
            Text("\(Int(yards.rounded()))")
                .font(SticksFont.display(24))
                .foregroundStyle(.white.opacity(0.85))
                .monospacedDigit()
        }
    }

    private func aimRow(anchor: DistanceAnchor, aim: CLLocationCoordinate2D, green: CLLocationCoordinate2D?) -> some View {
        let toAim = Int(GolfGeo.yards(from: anchor.coordinate, to: aim).rounded())
        let aimToGreen = green.map { Int(GolfGeo.yards(from: aim, to: $0).rounded()) }

        return HStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))

            Text(aimText(originName: anchor.originName, toAim: toAim, aimToGreen: aimToGreen))
                .font(SticksFont.label(12, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(.white)

            Spacer()

            Button {
                self.aim = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.white.opacity(0.12))
        .clipShape(.rect(cornerRadius: 11))
    }

    private func aimText(originName: String, toAim: Int, aimToGreen: Int?) -> String {
        if let aimToGreen {
            return "\(originName) → AIM \(toAim)  ·  AIM → PIN \(aimToGreen)"
        }
        return "\(originName) → AIM \(toAim)"
    }

    private func statusRow(detail: MatchDetail, anchor: DistanceAnchor?) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(anchor?.isPlayer == true ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(statusText(anchor: anchor))
                .font(SticksFont.label(10))
                .kerning(1)
                .foregroundStyle(.white.opacity(0.6))

            if canFixTee(detail) {
                Spacer()
                fixTeeButton
            }
        }
    }

    /// FINISH ROUND appears only for seated players (never spectators) and
    /// only once every player has a score on every hole.
    private func canFinishRound(_ detail: MatchDetail) -> Bool {
        detail.myMatchPlayerId != nil && viewModel.isRoundComplete
    }

    private var finishRoundButton: some View {
        Button {
            finishRound()
        } label: {
            HStack(spacing: 8) {
                if isFinishing {
                    ProgressView()
                        .tint(Color.sticksCream)
                } else {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 14, weight: .bold))
                }
                Text("FINISH ROUND")
                    .font(SticksFont.label(14, weight: .bold))
                    .kerning(2)
            }
            .foregroundStyle(Color.sticksCream)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.sticksGold)
            .clipShape(.rect(cornerRadius: 13))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isFinishing)
    }

    /// POSTs the completion, fires a success haptic, and exits back to
    /// match detail (already re-fetched by the view model, so it renders
    /// the COMPLETED state immediately).
    private func finishRound() {
        guard !isFinishing else { return }
        isFinishing = true
        finishError = nil
        Task {
            do {
                try await viewModel.completeMatch(session: session)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                RoundSessionService.shared.endRound()
                dismiss()
            } catch let error as APIError {
                finishError = error.message
            } catch {
                finishError = "Couldn't finish the round. Try again."
            }
            isFinishing = false
        }
    }

    /// FIX TEE appears only when the caller is seated in the match AND
    /// live GPS accuracy is ±35y or better (the server rejects worse).
    private func canFixTee(_ detail: MatchDetail) -> Bool {
        guard detail.myMatchPlayerId != nil,
              locationService.coordinate != nil,
              let accuracy = locationService.horizontalAccuracyYards else { return false }
        return accuracy <= GolfGeo.maxTeeFixAccuracyYards
    }

    private var fixTeeButton: some View {
        Button {
            showFixTee = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "smallcircle.filled.circle")
                    .font(.system(size: 10, weight: .bold))
                Text("FIX TEE")
                    .font(SticksFont.label(10, weight: .bold))
                    .kerning(1.2)
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.14))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func statusText(anchor: DistanceAnchor?) -> String {
        if anchor?.isPlayer == true {
            if let accuracy = locationService.horizontalAccuracyYards {
                return "GPS ±\(Int(accuracy.rounded()))Y"
            }
            return "GPS ACTIVE"
        }
        if locationService.isDenied {
            return "LOCATION OFF — DISTANCES FROM TEE"
        }
        if locationService.coordinate != nil {
            return "NOT AT COURSE — DISTANCES FROM TEE"
        }
        return "WAITING FOR GPS — DISTANCES FROM TEE"
    }

    private var greenNeededBanner: some View {
        VStack(spacing: 6) {
            Text("GREEN NEEDED")
                .font(SticksFont.label(13, weight: .bold))
                .kerning(2)
                .foregroundStyle(.orange)
            Text("Open the web admin to map this hole.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Logic

    /// Player anchor when GPS is authorized, has a fix, and the player is
    /// within ~2 miles of the hole; otherwise the tee (FROM TEE mode).
    private func currentAnchor(_ geo: HoleGeo?) -> DistanceAnchor? {
        if let playerCoordinate = locationService.coordinate,
           locationService.isAuthorized,
           let reference = geo?.greenCoordinate ?? geo?.teeCoordinate,
           GolfGeo.yards(from: playerCoordinate, to: reference) <= GolfGeo.onCourseThresholdYards {
            return DistanceAnchor(coordinate: playerCoordinate, isPlayer: true)
        }
        if let tee = geo?.teeCoordinate {
            return DistanceAnchor(coordinate: tee, isPlayer: false)
        }
        return nil
    }

    private func myScores(_ detail: MatchDetail) -> [Int: Int] {
        detail.players.first { $0.id == detail.myMatchPlayerId }?.scoresByHole ?? [:]
    }

    private func initializeIfNeeded() {
        guard !hasInitialized, let detail = viewModel.detail else { return }
        hasInitialized = true
        if RoundSessionService.shared.activeMatchId == detail.id {
            // Re-opening the GPS screen mid-round: resume the hole the
            // round session last showed instead of recomputing.
            holeIndex = min(RoundSessionService.shared.holeIndex, max(detail.holes - 1, 0))
        } else {
            holeIndex = initialHoleIndex(detail)
        }
        frameCurrentHole(detail, animated: false)
    }

    /// First hole the caller hasn't scored yet, else the starting hole.
    private func initialHoleIndex(_ detail: MatchDetail) -> Int {
        let scores = myScores(detail)
        for index in 0 ..< detail.holes where scores[detail.holeNumber(at: index)] == nil {
            return index
        }
        return 0
    }

    /// Fraction of the screen covered by the merged top row (status bar +
    /// back button/hole rail), with headroom for hazard chip height.
    private static let cameraTopFraction = 0.20
    /// Fraction covered by the bottom readout panel.
    private static let cameraBottomFraction = 0.30
    /// Visible ground height ≈ this × camera distance (empirical for the
    /// satellite camera at pitch 0).
    private static let groundSpanPerDistance = 0.75

    /// Fits tee + green + hazards into the visible band between the top
    /// rail row and the bottom panel, rotated so tee→green points
    /// up-screen. The top/bottom fractions pad the camera so hazard chips
    /// never render underneath the hole rail.
    private func frameCurrentHole(_ detail: MatchDetail, animated: Bool) {
        let hole = detail.holeNumber(at: holeIndex)
        guard let geo = viewModel.response?.holeGeo[hole] else { return }

        let target: MapCameraPosition
        if let tee = geo.teeCoordinate, let green = geo.greenCoordinate {
            let heading = GolfGeo.bearing(from: tee, to: green)
            let midpoint = GolfGeo.midpoint(tee, green)

            // Everything that must stay inside the visible band, projected
            // onto the hole axis (meters from midpoint, + = up-course).
            var points = [tee, green]
            points += (viewModel.response?.hazards[hole] ?? []).compactMap { hazard in
                guard let lat = hazard.lat, let lng = hazard.lng else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
            let projections = points.map {
                GolfGeo.upCourseMeters(of: $0, from: midpoint, heading: heading)
            }
            let upMost = projections.max() ?? 0
            let downMost = projections.min() ?? 0

            let usable = 1 - Self.cameraTopFraction - Self.cameraBottomFraction
            let minSpan = 380 * Self.groundSpanPerDistance
            let span = max((upMost - downMost) / usable, minSpan)
            // Slide the center up-course so the up-most point sits exactly
            // at the top of the visible band, clear of the rail row.
            let centerOffset = upMost - span * (0.5 - Self.cameraTopFraction)
            target = .camera(MapCamera(
                centerCoordinate: GolfGeo.coordinate(from: midpoint, bearing: heading, meters: centerOffset),
                distance: span / Self.groundSpanPerDistance,
                heading: heading,
                pitch: 0
            ))
        } else if let single = geo.teeCoordinate ?? geo.greenCoordinate {
            target = .camera(MapCamera(centerCoordinate: single, distance: 700, heading: 0, pitch: 0))
        } else {
            return
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.7)) { camera = target }
        } else {
            camera = target
        }
    }

    /// Advances to the next hole after the score sheet completes a hole —
    /// but only when the completed hole is the one on screen. Completing
    /// an EARLIER hole (e.g. the unscored hole an auto-advance walked away
    /// from) stays on the current hole.
    private func advanceHole(afterCompleting hole: Int) {
        guard let detail = viewModel.detail,
              hole == detail.holeNumber(at: holeIndex),
              holeIndex < detail.holes - 1 else { return }
        withAnimation { holeIndex += 1 }
    }

    private func openScoreSheet(_ detail: MatchDetail, hole: Int) {
        let player = detail.players.first { $0.id == detail.myMatchPlayerId }
            ?? viewModel.sortedPlayers.first
        guard let player else { return }

        // An auto-advance may have walked off an unscored hole — the
        // sheet defaults to it (once) if it's still unscored.
        var targetIndex = holeIndex
        var targetHole = hole
        if let suggested = RoundSessionService.shared.consumeSuggestedScoreIndex(matchId: detail.id),
           suggested >= 0, suggested < detail.holes {
            let suggestedHole = detail.holeNumber(at: suggested)
            if myScores(detail)[suggestedHole] == nil {
                targetIndex = suggested
                targetHole = suggestedHole
            }
        }
        scoreCell = ScoreCellSelection(player: player, hole: targetHole, par: detail.par(at: targetIndex))
    }
}

// MARK: - Wind tile

/// Wind speed + direction, matching the web app: MPH with an arrow
/// rotated to `fromDeg` (the direction the wind blows FROM).
private struct WindTile: View {
    let wind: Wind

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(wind.fromDeg))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(wind.speedMph.rounded()))")
                    .font(SticksFont.display(18))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("MPH")
                    .font(SticksFont.label(8))
                    .kerning(1.2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.black.opacity(0.55))
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wind \(Int(wind.speedMph.rounded())) miles per hour from \(Int(wind.fromDeg)) degrees")
    }
}

// MARK: - Map markers

private struct TeeMarker: View {
    var body: some View {
        Text("T")
            .font(SticksFont.label(11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color.sticksGreen)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }
}

private struct PinMarker: View {
    var body: some View {
        Image(systemName: "flag.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Color.sticksGreen)
            .frame(width: 26, height: 26)
            .background(.white)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.sticksGreen, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }
}

private struct AimMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white, lineWidth: 2)
                .frame(width: 22, height: 22)
            Circle()
                .fill(.white)
                .frame(width: 5, height: 5)
        }
        .shadow(color: .black.opacity(0.5), radius: 3)
    }
}

private struct HazardChip: View {
    let hazard: Hazard
    let distanceYards: Double?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            if let distanceYards {
                Text("\(Int(distanceYards.rounded()))")
                    .font(SticksFont.label(10, weight: .bold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    private var icon: String {
        switch hazard.kind {
        case .water: "drop.fill"
        case .sand: "circle.inset.filled"
        case .oob: "xmark"
        case .other: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch hazard.kind {
        case .water: Color(red: 0.2, green: 0.45, blue: 0.75)
        case .sand: Color(red: 0.72, green: 0.6, blue: 0.36)
        case .oob: Color(red: 0.72, green: 0.28, blue: 0.22)
        case .other: Color(white: 0.35)
        }
    }
}
