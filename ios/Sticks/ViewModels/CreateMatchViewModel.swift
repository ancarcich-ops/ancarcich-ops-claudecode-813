//
//  CreateMatchViewModel.swift
//  Sticks
//
//  Slice 20: state for the create-match flow — course search (name +
//  one-shot "near me" fix), the seat list with player suggestions,
//  side-game toggles, group picker, and the POST /matches submit.
//

import CoreLocation
import Foundation
import Observation

/// Everything the create form needs to reopen as slice 27's EDIT MODE —
/// the loaded match, its side-game kinds, and the group it was posted to
/// (carried on the summary, not the detail).
struct MatchEditContext {
    let detail: MatchDetail
    let sideGameKinds: [String]
    let groupId: String?
}

@Observable
final class CreateMatchViewModel {
    /// One seat in the players list. `userId` present = linked Sticks
    /// account (from a suggestion pick); absent = a guest seat.
    struct Seat: Identifiable, Equatable {
        let id: UUID
        var name: String
        var handicapText: String
        var userId: String?
        var username: String?
        var avatarUrl: String?
        let isMe: Bool
        /// The chosen tee's id (CourseTee.id) — nil until tees load or
        /// when the course has no rated tees.
        var teeId: String?
        /// Team assignment for SCRAMBLE/BOTH — 0 = Team A, 1 = Team B.
        /// Ignored for INDIVIDUAL rounds.
        var team: Int = 0
    }

    // MARK: Course

    var courseQuery = ""
    private(set) var courseResults: [CourseResult] = []
    private(set) var isSearchingCourses = false
    var selectedCourse: CourseResult? {
        didSet {
            guard oldValue?.name != selectedCourse?.name else { return }
            // Clearing the course (CHANGE) reopens the search group.
            if selectedCourse == nil { openRoundGroup = 0 }
            teesTask?.cancel()
            tees = []
            defaultTeeName = nil
            for index in seats.indices { seats[index].teeId = nil }
        }
    }
    private(set) var isLocating = false
    /// Set when a "Near me" attempt couldn't get a fix — degrade to name search.
    private(set) var nearMeFailed = false
    /// Last successful nearby fetch — restored whenever the search box
    /// empties so the step never goes blank after a cleared query.
    private var nearbyCache: [CourseResult] = []
    /// The silent open-of-flow nearby load runs at most once.
    private var didAutoLoadNearby = false

    // MARK: Guided reveal (slice 45)

    /// Web-parity progressive reveal on the Round step. `roundStage` is
    /// the furthest answered group (0 course → 1 tee & holes → 2 format
    /// → 3 all answered); `openRoundGroup` is the group currently
    /// expanded (nil = everything collapsed to chips).
    private(set) var roundStage = 0
    var openRoundGroup: Int? = 0

    // MARK: Setup

    var holes = 18 {
        didSet {
            guard holes != oldValue else { return }
            if holes == 18 {
                startsOnBack = false
            } else {
                // Nassau is 18-hole only — server rejects it on 9.
                sideGames.remove("NASSAU")
            }
        }
    }
    var startsOnBack = false
    var scoringMode = "NET"
    /// The round's tee time — maps to the create body's `scheduledAt`.
    /// Defaults to now, matching the web's starting state (slice 45).
    var teeTime: Date = .now
    /// Game format — INDIVIDUAL (all-vs-all), SCRAMBLE (one ball per
    /// team), or BOTH (individual + a team match on top). Slice 39.
    /// Picking a team format while solo grows the round to a twosome
    /// (the inverse of "solo forces Individual").
    var format = "INDIVIDUAL" {
        didSet {
            guard format != oldValue else { return }
            if format != "INDIVIDUAL", seats.count < 2, canAddSeat {
                addSeat()
            }
        }
    }

    /// Single web-parity holes control — Full 18 / Front 9 / Back 9
    /// (Back 9 = 9 holes starting on hole 10).
    enum HolesChoice: Hashable {
        case full18, front9, back9
    }

    var holesChoice: HolesChoice {
        get {
            if holes == 18 { return .full18 }
            return startsOnBack ? .back9 : .front9
        }
        set {
            switch newValue {
            case .full18:
                holes = 18
                startsOnBack = false
            case .front9:
                holes = 9
                startsOnBack = false
            case .back9:
                holes = 9
                startsOnBack = true
            }
        }
    }

    // MARK: Tees

    /// Rated tee sets for the selected course. Empty = no rating yet —
    /// the picker is hidden and players post without teeName.
    private(set) var tees: [CourseTee] = []
    private(set) var defaultTeeName: String?
    private var teesTask: Task<Void, Never>?

    // MARK: Players

    var seats: [Seat] = []
    private(set) var recentPartners: [PlayerSuggestion] = []
    private(set) var playerResults: [PlayerSuggestion] = []
    private(set) var isSearchingPlayers = false
    private(set) var myLastHandicap: Double?

    // MARK: Side games / group

    var sideGames: Set<String> = []
    private(set) var groups: [SticksGroup] = []
    var selectedGroupId: String?

    // MARK: Submit

    private(set) var isCreating = false
    private(set) var createError: String?

    /// Set = the form is editing an existing round (PATCH on submit)
    /// instead of creating one (POST).
    private(set) var editingMatchId: String?

    private let api: APIClient
    private let locationProvider = OneShotLocationProvider()
    private var courseSearchTask: Task<Void, Never>?
    private var playerSearchTask: Task<Void, Never>?

    init(api: APIClient = .shared, editing: MatchEditContext? = nil, user: User? = nil) {
        self.api = api
        guard let editing, let user else { return }
        // Property observers don't fire during init, so these seeds never
        // trip the course-change/holes-change resets.
        let detail = editing.detail
        editingMatchId = detail.id
        selectedCourse = CourseResult(
            id: detail.courseName,
            name: detail.courseName,
            city: nil,
            holes: detail.holes,
            access: nil,
            distanceMi: nil
        )
        holes = detail.holes
        startsOnBack = detail.holes == 9 && detail.startingHole == 10
        scoringMode = detail.scoringMode
        let knownFormats = ["INDIVIDUAL", "SCRAMBLE", "BOTH"]
        let detailFormat = detail.format.uppercased()
        format = knownFormats.contains(detailFormat) ? detailFormat : "INDIVIDUAL"
        sideGames = Set(editing.sideGameKinds)
        selectedGroupId = editing.groupId
        teeTime = detail.scheduledAt
        // Edit mode opens with everything answered — all chips, like
        // the web's roundStep = 3.
        roundStage = 3
        openRoundGroup = nil
        seats = detail.players
            .sorted { ($0.seat ?? Int.max, $0.id) < ($1.seat ?? Int.max, $1.id) }
            .map { player in
                Seat(
                    id: UUID(),
                    name: player.displayName,
                    handicapText: Self.formatHandicap(player.handicap ?? 0),
                    userId: player.userId,
                    username: nil,
                    avatarUrl: nil,
                    isMe: player.userId == user.id,
                    // Tees re-default from the course's tee list once it
                    // loads (pre-filling the exact prior tee is optional).
                    teeId: nil,
                    team: Self.teamIndex(player.team)
                )
            }
    }

    var isEditing: Bool { editingMatchId != nil }

    /// Location permission hard-denied — hide the "Near me" button entirely.
    var isLocationDenied: Bool { locationProvider.isDenied }

    var canAddSeat: Bool { seats.count < 8 }

    // MARK: Teams (slice 39)

    /// SCRAMBLE and BOTH seat players onto Team A / Team B.
    var usesTeams: Bool { format != "INDIVIDUAL" }

    var teamACount: Int { seats.filter { $0.team != 1 }.count }
    var teamBCount: Int { seats.filter { $0.team == 1 }.count }

    /// Team formats need both teams non-empty; INDIVIDUAL always passes.
    var teamsAreValid: Bool {
        !usesTeams || (teamACount > 0 && teamBCount > 0)
    }

    func setTeam(seatId: UUID, team: Int) {
        guard let index = seats.firstIndex(where: { $0.id == seatId }) else { return }
        seats[index].team = team == 1 ? 1 : 0
    }

    /// 1–8 seats and every seat has a name plus a parseable handicap —
    /// the Players step's gate (slice 32).
    var seatsAreValid: Bool {
        guard (1 ... 8).contains(seats.count) else { return false }
        return seats.allSatisfy { seat in
            !seat.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && Self.parseHandicap(seat.handicapText) != nil
        }
    }

    /// Course chosen + every seat has a name and a parseable handicap
    /// (+ both teams filled when the format uses teams).
    var canCreate: Bool {
        selectedCourse != nil && !isCreating && seatsAreValid && teamsAreValid
    }

    // MARK: - Bootstrap

    /// Seeds seat 1 with the signed-in user, then loads recent partners
    /// (for myLastHandicap prefill) and the caller's groups in parallel.
    /// In edit mode the seats arrive pre-filled and the course's tees
    /// are fetched straight away.
    func bootstrap(user: User, session: SessionStore) async {
        if seats.isEmpty {
            seats = [Seat(
                id: UUID(),
                name: user.displayName,
                handicapText: "0",
                userId: user.id,
                username: user.username,
                avatarUrl: nil,
                isMe: true,
                teeId: nil
            )]
            // Web default: Twosome — seat 2 arrives empty, ready to name.
            if !isEditing { addSeat() }
        }
        if isEditing, let course = selectedCourse, tees.isEmpty {
            loadTees(for: course.name, session: session)
        }
        guard let token = session.token else { return }

        async let suggest = try? api.suggestPlayers(query: nil, token: token)
        async let groupList = try? api.groups(token: token)

        if let response = await suggest {
            recentPartners = response.players
            myLastHandicap = response.myLastHandicap
            // Never overwrite a real prefilled handicap in edit mode.
            if !isEditing,
               let handicap = response.myLastHandicap,
               let index = seats.firstIndex(where: { $0.isMe }),
               seats[index].handicapText == "0" {
                seats[index].handicapText = Self.formatHandicap(handicap)
            }
        }
        if let response = await groupList {
            groups = response.groups
        }
    }

    // MARK: - Course search

    /// Debounced GET /courses?q=. Clearing the query clears results.
    func searchCourses(session: SessionStore) {
        courseSearchTask?.cancel()
        nearMeFailed = false
        let query = courseQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            // Cleared/short query → fall back to the nearby list if we
            // have one, so the step isn't left blank.
            courseResults = nearbyCache
            isSearchingCourses = false
            return
        }
        isSearchingCourses = true
        courseSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let token = session.token else { return }
            do {
                let response = try await api.searchCourses(query: query, token: token)
                guard !Task.isCancelled else { return }
                courseResults = response.courses
            } catch {
                guard !Task.isCancelled else { return }
                courseResults = []
            }
            isSearchingCourses = false
        }
    }

    /// One CoreLocation fix → GET /courses?lat&lng, nearest first.
    /// Degrades to name search (nearMeFailed) when no fix is available.
    func findNearby(session: SessionStore) async {
        guard !isLocating else { return }
        isLocating = true
        nearMeFailed = false
        defer { isLocating = false }

        guard let coordinate = await locationProvider.requestFix() else {
            nearMeFailed = true
            return
        }
        guard let token = session.token else { return }
        do {
            let response = try await api.nearbyCourses(
                lat: coordinate.latitude,
                lng: coordinate.longitude,
                token: token
            )
            courseResults = response.courses
            nearbyCache = response.courses
            if response.courses.isEmpty { nearMeFailed = true }
        } catch {
            nearMeFailed = true
        }
    }

    /// Silent "near me" that runs when the flow opens, so the course
    /// step starts pre-filled instead of blank. Skips edit mode and
    /// denied permission, and never surfaces an error — any failure
    /// just leaves the list empty for manual search.
    func autoLoadNearby(session: SessionStore) async {
        guard !didAutoLoadNearby,
              !isEditing,
              selectedCourse == nil,
              courseQuery.isEmpty,
              courseResults.isEmpty,
              !locationProvider.isDenied,
              !isLocating
        else { return }
        didAutoLoadNearby = true
        isLocating = true
        defer { isLocating = false }

        guard let coordinate = await locationProvider.requestFix(),
              let token = session.token else { return }
        guard let response = try? await api.nearbyCourses(
            lat: coordinate.latitude,
            lng: coordinate.longitude,
            token: token
        ), !response.courses.isEmpty else { return }

        nearbyCache = response.courses
        // Don't clobber anything the user typed or picked while locating.
        guard selectedCourse == nil, courseQuery.isEmpty else { return }
        courseResults = response.courses
    }

    func selectCourse(_ course: CourseResult, session: SessionStore) {
        selectedCourse = course
        courseQuery = ""
        courseResults = []
        nearMeFailed = false
        loadTees(for: course.name, session: session)
        // The web's auto-reveal: picking a course immediately collapses
        // it to a chip and opens Tee & holes.
        advanceRound(from: 0)
    }

    // MARK: - Guided reveal (slice 45)

    /// Marks `group` answered and opens the next unanswered one — or
    /// collapses everything once all three are done. Re-continuing a
    /// reopened, already-answered group just re-collapses it.
    func advanceRound(from group: Int) {
        if roundStage < group + 1 { roundStage = group + 1 }
        openRoundGroup = roundStage >= 3 ? nil : min(roundStage, 2)
    }

    /// Tapping a collapsed chip re-opens that group (web's StepChip).
    func reopenRoundGroup(_ group: Int) {
        openRoundGroup = group
    }

    // MARK: - Tees

    /// GET /courses/tees for the selected course, cached for the flow
    /// (the didSet on selectedCourse clears it when the course changes).
    /// A failed fetch leaves tees empty — the picker simply stays hidden
    /// and the round posts without teeName (server falls back).
    private func loadTees(for courseName: String, session: SessionStore) {
        teesTask?.cancel()
        guard let token = session.token else { return }
        teesTask = Task {
            let response = try? await api.courseTees(name: courseName, token: token)
            guard !Task.isCancelled, selectedCourse?.name == courseName else { return }
            tees = response?.tees ?? []
            defaultTeeName = response?.defaultTeeName
            applyDefaultTees()
        }
    }

    /// The seed selection: defaultTeeName's men's option, degrading to
    /// any tee of that name, any men's tee, then the first tee.
    private func defaultTee() -> CourseTee? {
        if let name = defaultTeeName {
            if let tee = tees.first(where: { $0.name == name && $0.gender == "M" }) { return tee }
            if let tee = tees.first(where: { $0.name == name }) { return tee }
        }
        return tees.first(where: { $0.gender == "M" }) ?? tees.first
    }

    /// Points every seat without a valid selection at the default tee.
    private func applyDefaultTees() {
        guard !tees.isEmpty, let fallback = defaultTee() else { return }
        for index in seats.indices {
            let current = seats[index].teeId
            if current == nil || !tees.contains(where: { $0.id == current }) {
                seats[index].teeId = fallback.id
            }
        }
    }

    func tee(withId id: String?) -> CourseTee? {
        guard let id else { return nil }
        return tees.first { $0.id == id }
    }

    func setTee(seatId: UUID, teeId: String) {
        guard let index = seats.firstIndex(where: { $0.id == seatId }) else { return }
        seats[index].teeId = teeId
    }

    // MARK: - Players

    /// Debounced GET /players/suggest?q=. Empty query clears results —
    /// the view falls back to recent partners.
    func searchPlayers(query: String, session: SessionStore) {
        playerSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            playerResults = []
            isSearchingPlayers = false
            return
        }
        isSearchingPlayers = true
        playerSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let token = session.token else { return }
            do {
                let response = try await api.suggestPlayers(query: trimmed, token: token)
                guard !Task.isCancelled else { return }
                playerResults = response.players
            } catch {
                guard !Task.isCancelled else { return }
                playerResults = []
            }
            isSearchingPlayers = false
        }
    }

    /// Suggestions for a seat: search results while typing, recent
    /// partners otherwise — minus anyone already seated.
    func suggestions(forQuery query: String) -> [PlayerSuggestion] {
        let seated = Set(seats.compactMap(\.userId))
        let pool = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? recentPartners
            : playerResults
        return pool.filter { !seated.contains($0.userId) }
    }

    func addSeat() {
        guard canAddSeat else { return }
        seats.append(Seat(
            id: UUID(),
            name: "",
            handicapText: "0",
            userId: nil,
            username: nil,
            avatarUrl: nil,
            isMe: false,
            teeId: defaultTee()?.id
        ))
    }

    /// Round-step player-count chips (Solo / Twosome / Threesome /
    /// Foursome). Grows with empty guest seats, shrinks from the bottom
    /// (never removes the "me" seat). Solo forces Individual, like the
    /// web.
    func setPlayerCount(_ count: Int) {
        let target = min(max(count, 1), 8)
        while seats.count < target, canAddSeat {
            addSeat()
        }
        while seats.count > target {
            guard let index = seats.lastIndex(where: { !$0.isMe }) else { break }
            seats.remove(at: index)
        }
        if seats.count < 2, format != "INDIVIDUAL" {
            format = "INDIVIDUAL"
        }
    }

    func removeSeat(id: UUID) {
        seats.removeAll { $0.id == id && !$0.isMe }
        // Solo rounds are always Individual — dropping below 2 players
        // reverts a team format (mirrors the web).
        if seats.count < 2, format != "INDIVIDUAL" {
            format = "INDIVIDUAL"
        }
    }

    /// Links a seat to a suggestion — carries the userId and prefills
    /// the handicap when the suggestion knows one.
    func link(seatId: UUID, to suggestion: PlayerSuggestion) {
        guard let index = seats.firstIndex(where: { $0.id == seatId }) else { return }
        seats[index].name = suggestion.displayName
        seats[index].userId = suggestion.userId
        seats[index].username = suggestion.username
        seats[index].avatarUrl = suggestion.avatarUrl
        if let handicap = suggestion.lastHandicap {
            seats[index].handicapText = Self.formatHandicap(handicap)
        }
        playerResults = []
    }

    /// Hand-editing a linked seat's name makes it a guest again.
    func unlinkIfEdited(seatId: UUID) {
        guard let index = seats.firstIndex(where: { $0.id == seatId }),
              seats[index].userId != nil, !seats[index].isMe else { return }
        seats[index].userId = nil
        seats[index].username = nil
        seats[index].avatarUrl = nil
    }

    /// Steps a seat's handicap by ±1 (blank steps from 0), clamped ±54.
    func stepHandicap(seatId: UUID, by delta: Double) {
        guard let index = seats.firstIndex(where: { $0.id == seatId }) else { return }
        let current = Self.parseHandicap(seats[index].handicapText) ?? 0
        let next = min(max(current + delta, -54), 54)
        seats[index].handicapText = Self.formatHandicap(next)
    }

    // MARK: - Side games

    func toggleSideGame(_ kind: String) {
        if sideGames.contains(kind) {
            sideGames.remove(kind)
        } else {
            sideGames.insert(kind)
        }
    }

    // MARK: - Submit

    func clearError() {
        createError = nil
    }

    /// POST /matches — or PATCH /matches/:id in edit mode. Returns the
    /// match id on success; on 400/403 surfaces the server's message
    /// verbatim and re-enables.
    func create(session: SessionStore) async -> String? {
        guard canCreate, let course = selectedCourse else { return nil }
        guard let token = session.token else {
            session.signOut()
            return nil
        }
        isCreating = true
        createError = nil
        defer { isCreating = false }

        // Belt & braces: a solo round is always Individual, and team
        // assignments only travel on team formats.
        let effectiveFormat = seats.count > 1 ? format : "INDIVIDUAL"
        let sendsTeams = effectiveFormat != "INDIVIDUAL"
        let players = seats.map { seat in
            // Seats on the default still send their tee explicitly; when
            // the course has no rated tees the keys are omitted entirely.
            let tee = tee(withId: seat.teeId)
            return CreateMatchPlayer(
                displayName: seat.name.trimmingCharacters(in: .whitespacesAndNewlines),
                handicap: Self.parseHandicap(seat.handicapText) ?? 0,
                userId: seat.userId,
                teeName: tee?.name,
                teeGender: tee?.gender,
                team: sendsTeams ? seat.team : nil
            )
        }
        // Belt & braces on the server's rules: 18-hole rounds always
        // start on 1; Nassau never posts on 9 holes.
        var games = sideGames
        if holes != 18 { games.remove("NASSAU") }
        let request = CreateMatchRequest(
            courseName: course.name,
            holes: holes,
            startingHole: holes == 18 ? 1 : (startsOnBack ? 10 : 1),
            scheduledAt: ISO8601DateFormatter().string(from: teeTime),
            scoringMode: scoringMode,
            format: effectiveFormat,
            players: players,
            sideGames: games.isEmpty ? nil : games.sorted(),
            groupId: selectedGroupId
        )
        do {
            let response: CreateMatchResponse
            if let editingMatchId {
                response = try await api.updateMatch(id: editingMatchId, request, token: token)
            } else {
                response = try await api.createMatch(request, token: token)
            }
            return response.match.id
        } catch let error as APIError where error.isUnauthorized {
            session.signOut()
            return nil
        } catch let error as APIError {
            createError = error.message
            return nil
        } catch {
            createError = "Can't reach Sticks. Check your connection and try again."
            return nil
        }
    }

    // MARK: - Handicap helpers

    /// Parses a handicap field. Blank = invalid (nil), NOT 0 — the
    /// create button stays disabled. Accepts "," as a decimal separator.
    static func parseHandicap(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    /// Maps a detail player's `team` ("0"/"1", "A"/"B", or null) to the
    /// wizard's 0/1 seat assignment — anything unrecognized lands on A.
    static func teamIndex(_ team: String?) -> Int {
        switch team?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "1", "B": return 1
        default: return 0
        }
    }

    /// "11.6" or "8" — one decimal max, no trailing .0.
    static func formatHandicap(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

// MARK: - One-shot location

/// Grabs a single CoreLocation fix for the "Near me" course search.
/// Self-contained — deliberately separate from LocationService, which is
/// owned by the round session and streams continuously.
final class OneShotLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        // A rough fix is plenty for "courses near me".
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    /// Requests permission if needed and resolves with one fix, or nil
    /// on denial/failure. Never throws — callers degrade to name search.
    func requestFix() async -> CLLocationCoordinate2D? {
        if continuation != nil { return nil }
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            // The auth callback below kicks off requestLocation().
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        default:
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                manager.requestLocation()
            }
        }
    }

    private func resume(with value: CLLocationCoordinate2D?) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.resume(with: nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            self.resume(with: coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.resume(with: nil)
        }
    }
}
