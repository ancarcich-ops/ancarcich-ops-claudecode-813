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

/// Slice 28/30: framing modes for the segmented control. TEE / GREEN /
/// HOLE snap the native MapKit camera; 3D swaps the map for the remote
/// photorealistic flyover WebView. Readouts, markers, wind, FIX TEE,
/// and ENTER SCORE are identical in all four.
private enum GPSCameraMode: String, CaseIterable {
    case tee = "TEE"
    case green = "GREEN"
    case hole = "HOLE"
    case threeD = "3D"
}

struct OnCourseGPSView: View {
    let viewModel: MatchDetailViewModel
    let session: SessionStore

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var cameraMode: GPSCameraMode = .hole
    @State private var holeIndex = 0
    @State private var aim: CLLocationCoordinate2D?
    @State private var scoreCell: ScoreCellSelection?
    @State private var showFixTee = false
    @State private var hasInitialized = false
    @State private var isFinishing = false
    @State private var finishError: String?
    // Slice 59: brief "3D didn't load" toast shown when the flyover
    // stalls/fails and the screen auto-drops back to the 2D HOLE map.
    @State private var showFlyoverToast = false
    @State private var flyoverToastTask: Task<Void, Never>?
    // Slice 60: "you skipped a hole" prompt — the hole number to offer
    // scoring for (nil = no alert), plus the holes already prompted this
    // session so a "Not now" isn't immediately re-asked.
    @State private var missedScoreHole: Int?
    @State private var promptedMissedHoles: Set<Int> = []
    // Set when initializeIfNeeded assigns the starting hole so that first
    // programmatic jump (e.g. resuming mid-round) never reads as "you
    // walked off a hole" — consumed by the holeIndex onChange.
    @State private var isInitialHoleAssignment = false

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
            // Slice 29: this screen is intentionally immersive — hide
            // the persistent tab bar while it's up.
            TabChrome.shared.hidesTabBar = true
            RoundSessionService.shared.gpsScreenAppeared()
            initializeIfNeeded()
            RoundSessionService.shared.beginRound(viewModel: viewModel, holeIndex: holeIndex, session: session)
        }
        .onDisappear {
            TabChrome.shared.hidesTabBar = false
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
            // Auto-advance: the FIRST saved score on the displayed hole
            // moves the map to the next hole right away (the sheet keeps
            // cycling remaining players on the hole it opened on); the
            // hole-complete advance is then a guarded no-op.
            ScoreEntryView(
                cell: cell,
                viewModel: viewModel,
                session: session,
                onScoreSaved: { advanceHole(afterCompleting: cell.hole) },
                onHoleComplete: { advanceHole(afterCompleting: cell.hole) }
            )
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
        // Slice 60: moving forward off an unscored hole (GPS auto-advance,
        // rail tap, or post-save advance — all route through holeIndex)
        // offers to enter that score right now instead of waiting for the
        // golfer to stumble on it in the score sheet.
        .alert(
            "Score hole \(missedScoreHole ?? 0)?",
            isPresented: Binding(
                get: { missedScoreHole != nil },
                set: { if !$0 { missedScoreHole = nil } }
            ),
            presenting: missedScoreHole
        ) { hole in
            Button("Enter score") { openMissedScoreSheet(hole) }
            Button("Not now", role: .cancel) { missedScoreHole = nil }
        } message: { hole in
            Text("You moved on without entering your score for hole \(hole).")
        }
    }

    // MARK: - Map

    private func courseMap(_ detail: MatchDetail) -> some View {
        let hole = detail.holeNumber(at: holeIndex)
        let geo = viewModel.response?.holeGeo[hole]
        let hazards = viewModel.response?.hazards[hole] ?? []
        let anchor = currentAnchor(geo)

        return ZStack {
            // Slice 30: 3D renders the remote photorealistic flyover in
            // place of the MapKit map; the native overlays (rail, wind,
            // readout panel, CTAs) stay on top via the safe-area insets.
            // Switching back to TEE/GREEN/HOLE returns to MapKit instantly.
            if cameraMode == .threeD, let url = flyoverURL(detail, geo: geo) {
                flyoverLayer(url: url)
            } else {
                MapReader { proxy in
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
            VStack(spacing: 10) {
                if showFlyoverToast {
                    flyoverFallbackToast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                bottomPanel(detail: detail, geo: geo, anchor: anchor)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onChange(of: holeIndex) { oldIndex, newIndex in
            aim = nil
            RoundSessionService.shared.setHole(index: newIndex, matchId: detail.id)
            // The new hole may lack the geo the current mode needs
            // (e.g. TEE mode onto a hole with no tee) — fall back to
            // HOLE, whose onChange performs the snap instead.
            let geo = viewModel.response?.holeGeo[detail.holeNumber(at: newIndex)]
            if !isModeAvailable(cameraMode, geo: geo) {
                cameraMode = .hole
            } else {
                snapCamera(detail, animated: true)
            }
            // Slice 60: the very first assignment (resume/initial hole in
            // initializeIfNeeded) is a jump, not a walk-off — never prompt.
            if isInitialHoleAssignment {
                isInitialHoleAssignment = false
            } else {
                maybePromptForMissedScore(detail, leftIndex: oldIndex, arrivedIndex: newIndex)
            }
        }
        .onChange(of: cameraMode) { _, _ in
            snapCamera(detail, animated: true)
        }
        // Preload the 3D flyover for the displayed hole in ANY mode —
        // the shared WebView streams tiles in the background while the
        // golfer reads the satellite map, so tapping 3D opens a warm
        // (often fully loaded) scene. Re-runs on hole change and when
        // geo arrives from the fetch.
        .task(id: flyoverURL(detail, geo: geo)) {
            if let url = flyoverURL(detail, geo: geo) {
                FlyoverService.shared.prepare(url: url)
            }
        }
        // Slice 59: the embed reports "stalled"/"error" (or the service
        // watchdog fires) — while 3D is on screen, drop straight to the
        // fast 2D map instead of leaving the golfer on a spinner.
        .onChange(of: FlyoverService.shared.state) { _, newState in
            if newState == .failed { fallBackTo2D() }
        }
        // Belt-and-suspenders: status messages need the page's JS to run.
        // If the WebView never even loads the page, no message arrives —
        // so give 3D ~8s after entry (or a hole change while in 3D) to
        // report ready, then run the same fallback. The task is cancelled
        // automatically on mode/hole change and on disappear.
        .task(id: "\(cameraMode.rawValue)-\(holeIndex)") {
            guard cameraMode == .threeD else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled,
                  FlyoverService.shared.state != .ready else { return }
            fallBackTo2D()
        }
    }

    /// Slice 59: the flyover stalled or failed while 3D was showing —
    /// return to the 2D HOLE map with a brief toast. The 3D segment stays
    /// tappable; re-entering retries the load cleanly (the service
    /// re-prepares a failed page on attach).
    private func fallBackTo2D() {
        guard cameraMode == .threeD else { return }
        withAnimation { cameraMode = .hole }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        withAnimation { showFlyoverToast = true }
        flyoverToastTask?.cancel()
        flyoverToastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation { showFlyoverToast = false }
        }
    }

    /// Non-blocking pill above the distance panel: cream label on a dark
    /// glass capsule, auto-dismissed after ~2.5s.
    private var flyoverFallbackToast: some View {
        Text("3D DIDN'T LOAD — SHOWING THE 2D MAP")
            .font(SticksFont.label(11, weight: .bold))
            .kerning(1.4)
            .foregroundStyle(Color.sticksCream)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.7))
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            .environment(\.colorScheme, .dark)
            .accessibilityLabel("3D view didn't load. Showing the 2D map.")
    }

    /// The 3D flyover layer: a dark backdrop + spinner behind the
    /// transparent WebView while the mesh streams in (the page paints its
    /// own scrim over it, then the flyover fades in). The WebView itself
    /// is owned by FlyoverService — preloaded before 3D is tapped and
    /// kept alive across mode switches. Failed/stalled loads don't render
    /// anything here — the screen auto-falls back to the 2D map (slice 59).
    private func flyoverLayer(url: URL) -> some View {
        let state = FlyoverService.shared.state
        return ZStack {
            Color(red: 0x0B / 255, green: 0x0F / 255, blue: 0x0D / 255)
            if state == .loading {
                ProgressView()
                    .tint(Color.sticksGreen)
            }
            HoleFlyoverWebView()
        }
        .ignoresSafeArea()
        .task(id: url) {
            FlyoverService.shared.prepare(url: url)
        }
    }

    /// Builds the production flyover embed URL for the current hole from
    /// its geo — nil when either the tee or green coordinate is missing
    /// (the 3D segment is grayed out in that case, so this never renders
    /// a broken page).
    private func flyoverURL(_ detail: MatchDetail, geo: HoleGeo?) -> URL? {
        guard let geo,
              let tee = geo.teeCoordinate,
              let green = geo.greenCoordinate else { return nil }

        var components = URLComponents(string: "https://sticks-golf.vercel.app/embed/hole-flyover")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "teeLat", value: String(tee.latitude)),
            URLQueryItem(name: "teeLng", value: String(tee.longitude)),
            URLQueryItem(name: "greenLat", value: String(green.latitude)),
            URLQueryItem(name: "greenLng", value: String(green.longitude)),
            URLQueryItem(name: "n", value: String(detail.holeNumber(at: holeIndex))),
            URLQueryItem(name: "par", value: String(detail.par(at: holeIndex))),
        ]
        if let yards = geo.distanceYds, yards.isFinite, yards > 0 {
            items.append(URLQueryItem(name: "yards", value: String(Int(yards.rounded()))))
        }
        components?.queryItems = items
        return components?.url
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
            if let lat = hazard.lat, let lng = hazard.lng, GolfGeo.isUsable(lat: lat, lng: lng) {
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
            cameraModeControl(geo)

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
                        .font(SticksFont.sans(12))
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

    // MARK: - Camera mode control

    /// TEE · GREEN · HOLE · 3D segments. Modes whose geo is missing are
    /// grayed out: TEE needs a tee coordinate, GREEN needs a green, and
    /// 3D needs both (the flyover flies tee→green).
    private func cameraModeControl(_ geo: HoleGeo?) -> some View {
        HStack(spacing: 3) {
            ForEach(GPSCameraMode.allCases, id: \.self) { mode in
                let available = isModeAvailable(mode, geo: geo)
                Button {
                    guard cameraMode != mode else { return }
                    cameraMode = mode
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(mode.rawValue)
                        .font(SticksFont.label(11, weight: .bold))
                        .kerning(1.4)
                        .foregroundStyle(segmentColor(mode, available: available))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(cameraMode == mode ? Color.sticksGreen : .clear)
                        .clipShape(.rect(cornerRadius: 8))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!available)
                .accessibilityLabel("\(mode.rawValue) view")
            }
        }
        .padding(3)
        .background(.white.opacity(0.1))
        .clipShape(.rect(cornerRadius: 11))
    }

    private func segmentColor(_ mode: GPSCameraMode, available: Bool) -> Color {
        if !available { return .white.opacity(0.25) }
        return cameraMode == mode ? Color.sticksCream : .white.opacity(0.65)
    }

    private func isModeAvailable(_ mode: GPSCameraMode, geo: HoleGeo?) -> Bool {
        switch mode {
        case .tee: geo?.teeCoordinate != nil
        case .green: geo?.greenCoordinate != nil
        case .hole: geo?.teeCoordinate != nil || geo?.greenCoordinate != nil
        case .threeD: geo?.teeCoordinate != nil && geo?.greenCoordinate != nil
        }
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
                .font(SticksFont.sans(13))
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
        let startIndex: Int
        if RoundSessionService.shared.activeMatchId == detail.id {
            // Re-opening the GPS screen mid-round: resume the hole the
            // round session last showed instead of recomputing.
            startIndex = min(RoundSessionService.shared.holeIndex, max(detail.holes - 1, 0))
        } else {
            startIndex = initialHoleIndex(detail)
        }
        if startIndex != holeIndex {
            // Flag the programmatic jump so the holeIndex onChange doesn't
            // read it as walking off an unscored hole (slice 60).
            isInitialHoleAssignment = true
            holeIndex = startIndex
        }
        snapCamera(detail, animated: false)
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

    /// Snaps the native MapKit camera to the current mode's framing for
    /// the current hole (~0.5s animated). Runs on mode change and hole
    /// change. 3D doesn't route through MapKit (the flyover WebView owns
    /// its own camera), so it snaps HOLE framing underneath — the map is
    /// correctly framed the instant the user switches back.
    private func snapCamera(_ detail: MatchDetail, animated: Bool) {
        let hole = detail.holeNumber(at: holeIndex)
        guard let geo = viewModel.response?.holeGeo[hole] else { return }

        let target: MapCameraPosition?
        switch cameraMode {
        case .hole, .threeD: target = holeCamera(geo, hole: hole)
        case .tee: target = teeCamera(geo)
        case .green: target = greenCamera(geo)
        }
        guard let target else { return }

        if animated {
            withAnimation(.easeInOut(duration: 0.5)) { camera = target }
        } else {
            camera = target
        }
    }

    /// HOLE: fits tee + green + hazards into the visible band between the
    /// top rail row and the bottom panel, rotated so tee→green points
    /// up-screen. The top/bottom fractions pad the camera so hazard chips
    /// never render underneath the hole rail.
    private func holeCamera(_ geo: HoleGeo, hole: Int) -> MapCameraPosition? {
        if let tee = geo.teeCoordinate, let green = geo.greenCoordinate {
            let heading = GolfGeo.bearing(from: tee, to: green)
            let midpoint = GolfGeo.midpoint(tee, green)

            // Everything that must stay inside the visible band, projected
            // onto the hole axis (meters from midpoint, + = up-course).
            var points = [tee, green]
            points += (viewModel.response?.hazards[hole] ?? []).compactMap { hazard in
                guard let lat = hazard.lat, let lng = hazard.lng,
                      GolfGeo.isUsable(lat: lat, lng: lng) else { return nil }
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
            let center = GolfGeo.coordinate(from: midpoint, bearing: heading, meters: centerOffset)
            let distance = span / Self.groundSpanPerDistance
            // MapKit throws (hard crash) on non-finite camera values — bad
            // geo degrades to the un-reframed map instead.
            guard GolfGeo.isUsable(lat: center.latitude, lng: center.longitude),
                  distance.isFinite, distance > 0, heading.isFinite else { return nil }
            return .camera(MapCamera(
                centerCoordinate: center,
                distance: distance,
                heading: heading,
                pitch: 0
            ))
        }
        if let single = geo.teeCoordinate ?? geo.greenCoordinate {
            return .camera(MapCamera(centerCoordinate: single, distance: 700, heading: 0, pitch: 0))
        }
        return nil
    }

    /// TEE: tight top-down on the tee box, heading tee→green so you look
    /// up the hole from the tee.
    private func teeCamera(_ geo: HoleGeo) -> MapCameraPosition? {
        guard let tee = geo.teeCoordinate else { return nil }
        let heading = geo.greenCoordinate.map { GolfGeo.bearing(from: tee, to: $0) } ?? 0
        guard heading.isFinite else { return nil }
        return .camera(MapCamera(centerCoordinate: tee, distance: 200, heading: heading, pitch: 0))
    }

    /// GREEN: centered on the green (a fixed target — no re-follow),
    /// zoomed so the green polygon plus greenside bunkers are readable.
    /// Falls back to ~120m when there's no polygon.
    private func greenCamera(_ geo: HoleGeo) -> MapCameraPosition? {
        guard let green = geo.greenCoordinate else { return nil }
        let heading = geo.teeCoordinate.map { GolfGeo.bearing(from: $0, to: green) } ?? 0
        guard heading.isFinite else { return nil }

        var distance: Double = 120
        let vertices = geo.greenPolygonCoordinates
        if vertices.count >= 3 {
            let radiusMeters = vertices
                .map { GolfGeo.yards(from: green, to: $0) / GolfGeo.yardsPerMeter }
                .max() ?? 0
            // Green diameter at ~40% of the visible ground span keeps
            // front/center/back and the surrounding bunkers in frame.
            let span = (radiusMeters * 2) / 0.4
            distance = max(span / Self.groundSpanPerDistance, 120)
        }
        guard distance.isFinite, distance > 0 else { return nil }
        return .camera(MapCamera(centerCoordinate: green, distance: distance, heading: heading, pitch: 0))
    }

    /// Advances to the next hole as soon as the score sheet saves a score
    /// on the hole that's on screen (and again, as a guarded no-op, when
    /// the hole completes). Scoring an EARLIER hole (e.g. the unscored
    /// hole an auto-advance walked away from) stays on the current hole.
    private func advanceHole(afterCompleting hole: Int) {
        guard let detail = viewModel.detail,
              hole == detail.holeNumber(at: holeIndex),
              holeIndex < detail.holes - 1 else { return }
        withAnimation { holeIndex += 1 }
    }

    // MARK: - Missed-score prompt (slice 60)

    /// Fires the "Score hole N?" alert when the golfer moves FORWARD off
    /// a hole they haven't scored themselves. One prompt per hole per
    /// on-course session; never on finished rounds, never for spectators,
    /// never when tapping back to an earlier hole.
    private func maybePromptForMissedScore(_ detail: MatchDetail, leftIndex: Int, arrivedIndex: Int) {
        // Only when actually moving forward.
        guard arrivedIndex > leftIndex else { return }
        // Only during a live round — no nagging on finished rounds or
        // pre-round hole browsing.
        guard detail.status == .inProgress else { return }
        // Me only (v1): the prompt is about *your* score, so it needs a seat.
        guard detail.myMatchPlayerId != nil else { return }
        guard leftIndex >= 0, leftIndex < detail.holes else { return }
        let leftHole = detail.holeNumber(at: leftIndex)
        // Already scored? Nothing to do (same myScores the rail reads).
        guard myScores(detail)[leftHole] == nil else { return }
        // Only prompt once per hole per session.
        guard !promptedMissedHoles.contains(leftHole) else { return }
        promptedMissedHoles.insert(leftHole)
        missedScoreHole = leftHole
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Opens the score sheet on the MISSED hole (not the current one).
    /// Saving there is position-safe: the sheet's advance callbacks are
    /// guarded to the currently displayed hole, so the map stays on the
    /// hole being played.
    private func openMissedScoreSheet(_ hole: Int) {
        guard let detail = viewModel.detail else { return }
        let player = detail.players.first { $0.id == detail.myMatchPlayerId }
            ?? viewModel.sortedPlayers.first
        guard let player,
              let index = (0 ..< detail.holes).first(where: { detail.holeNumber(at: $0) == hole })
        else { return }
        missedScoreHole = nil
        scoreCell = ScoreCellSelection(player: player, hole: hole, par: detail.par(at: index))
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
