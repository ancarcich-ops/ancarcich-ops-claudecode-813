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
    }

    // MARK: Course

    var courseQuery = ""
    private(set) var courseResults: [CourseResult] = []
    private(set) var isSearchingCourses = false
    var selectedCourse: CourseResult?
    private(set) var isLocating = false
    /// Set when a "Near me" attempt couldn't get a fix — degrade to name search.
    private(set) var nearMeFailed = false

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

    private let api: APIClient
    private let locationProvider = OneShotLocationProvider()
    private var courseSearchTask: Task<Void, Never>?
    private var playerSearchTask: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Location permission hard-denied — hide the "Near me" button entirely.
    var isLocationDenied: Bool { locationProvider.isDenied }

    var canAddSeat: Bool { seats.count < 8 }

    /// Course chosen + every seat has a name and a parseable handicap.
    var canCreate: Bool {
        guard selectedCourse != nil, !isCreating else { return false }
        guard (1 ... 8).contains(seats.count) else { return false }
        return seats.allSatisfy { seat in
            !seat.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && Self.parseHandicap(seat.handicapText) != nil
        }
    }

    // MARK: - Bootstrap

    /// Seeds seat 1 with the signed-in user, then loads recent partners
    /// (for myLastHandicap prefill) and the caller's groups in parallel.
    func bootstrap(user: User, session: SessionStore) async {
        if seats.isEmpty {
            seats = [Seat(
                id: UUID(),
                name: user.displayName,
                handicapText: "0",
                userId: user.id,
                username: user.username,
                avatarUrl: nil,
                isMe: true
            )]
        }
        guard let token = session.token else { return }

        async let suggest = try? api.suggestPlayers(query: nil, token: token)
        async let groupList = try? api.groups(token: token)

        if let response = await suggest {
            recentPartners = response.players
            myLastHandicap = response.myLastHandicap
            if let handicap = response.myLastHandicap,
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
            courseResults = []
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
            if response.courses.isEmpty { nearMeFailed = true }
        } catch {
            nearMeFailed = true
        }
    }

    func selectCourse(_ course: CourseResult) {
        selectedCourse = course
        courseQuery = ""
        courseResults = []
        nearMeFailed = false
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
            isMe: false
        ))
    }

    func removeSeat(id: UUID) {
        seats.removeAll { $0.id == id && !$0.isMe }
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

    /// POST /matches. Returns the created match id on success; on
    /// 400/403 surfaces the server's message verbatim and re-enables.
    func create(session: SessionStore) async -> String? {
        guard canCreate, let course = selectedCourse else { return nil }
        guard let token = session.token else {
            session.signOut()
            return nil
        }
        isCreating = true
        createError = nil
        defer { isCreating = false }

        let players = seats.map { seat in
            CreateMatchPlayer(
                displayName: seat.name.trimmingCharacters(in: .whitespacesAndNewlines),
                handicap: Self.parseHandicap(seat.handicapText) ?? 0,
                userId: seat.userId
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
            scoringMode: scoringMode,
            players: players,
            sideGames: games.isEmpty ? nil : games.sorted(),
            groupId: selectedGroupId
        )
        do {
            let response = try await api.createMatch(request, token: token)
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
