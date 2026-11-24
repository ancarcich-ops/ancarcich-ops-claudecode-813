//
//  ScorecardImportViewModel.swift
//  Sticks
//
//  Screenshot import: pick 1–3 scorecard screenshots → the server reads
//  each one (POST /imports/scorecard) → the player reviews an editable
//  grid → saving creates a real, finished round with the existing
//  endpoints (POST /matches, /pars, /score, /complete).
//

import Foundation
import Observation
import UIKit

/// One editable row of the review grid.
struct ImportSeat: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var isMe: Bool
    /// One entry per round column (index 0 = startingHole).
    var scores: [Int?]
    /// Column indexes the reader wasn't sure about.
    var uncertain: Set<Int>
    /// The total printed on the card, when it showed one.
    var printedTotal: Int?
}

/// Which holes the round covers.
enum ImportHoleLayout: String, CaseIterable, Identifiable {
    case full = "18 holes"
    case front = "Front 9"
    case back = "Back 9"

    var id: String { rawValue }
    var count: Int { self == .full ? 18 : 9 }
    var startingHole: Int { self == .back ? 10 : 1 }
}

@Observable
final class ScorecardImportViewModel {
    enum Phase: Equatable {
        case pick
        case reading
        case failed(String)
        case review
        case saving
    }

    static let maxImages = 3
    static let maxSeats = 8

    var phase: Phase = .pick
    var thumbnails: [UIImage] = []
    var warnings: [String] = []
    var sourceLabel: String?

    // Course
    var courseQuery = ""
    var courseResults: [CourseResult] = []
    var selectedCourse: CourseResult?
    var isSearchingCourses = false

    // Round
    var playedAt = Date()
    private(set) var layout: ImportHoleLayout = .full
    /// nil = not on the card; the course's own par fills in on save.
    var pars: [Int?] = Array(repeating: nil, count: 18)
    var seats: [ImportSeat] = []

    // Save
    var saveProgress: Double = 0
    var saveStatus = ""
    var saveError: String?

    private let user: User
    private var myHandicap: Double = 0
    private var searchTask: Task<Void, Never>?
    /// Survives a failed save so a retry never creates a second round.
    private var createdMatchId: String?
    private var createdPlayerIds: [UUID: String] = [:]
    private let api = APIClient.shared

    init(user: User) {
        self.user = user
    }

    // MARK: - Derived

    var holeCount: Int { layout.count }

    func holeNumber(at index: Int) -> Int { layout.startingHole + index }

    var missingScoreCount: Int {
        seats.reduce(0) { $0 + $1.scores.filter { $0 == nil }.count }
    }

    var uncertainCount: Int {
        seats.reduce(0) { $0 + $1.uncertain.count }
    }

    var hasMe: Bool { seats.contains(where: \.isMe) }

    var namesAreValid: Bool {
        seats.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var canSave: Bool {
        phase == .review && selectedCourse != nil && !seats.isEmpty && hasMe
            && namesAreValid && missingScoreCount == 0
    }

    /// What's blocking Save, in the order the player should fix it.
    var saveBlocker: String? {
        if selectedCourse == nil { return "Pick the course" }
        if seats.isEmpty { return "Add a player" }
        if !hasMe { return "Mark which row is you" }
        if !namesAreValid { return "Every player needs a name" }
        if missingScoreCount > 0 {
            return missingScoreCount == 1 ? "1 score missing" : "\(missingScoreCount) scores missing"
        }
        return nil
    }

    func total(for seat: ImportSeat) -> Int {
        seat.scores.compactMap { $0 }.reduce(0, +)
    }

    var parTotal: Int? {
        let known = pars.compactMap { $0 }
        return known.count == pars.count ? known.reduce(0, +) : nil
    }

    // MARK: - Bootstrap

    func bootstrap(session: SessionStore) async {
        guard let token = session.token else { return }
        if let response = try? await api.suggestPlayers(query: nil, token: token),
           let handicap = response.myLastHandicap {
            myHandicap = handicap
        }
    }

    // MARK: - Reading

    /// Sends every picked screenshot in parallel and merges what comes
    /// back. Partial success still lands on the review grid with the
    /// failures listed as warnings.
    func read(images: [UIImage], session: SessionStore) async {
        guard let token = session.token else { return }
        let picked = Array(images.prefix(Self.maxImages))
        guard !picked.isEmpty else { return }
        thumbnails = picked
        phase = .reading

        var responses: [(Int, ScorecardImportResponse)] = []
        var firstError: APIError?
        var sawOtherError = false

        await withTaskGroup(of: (Int, Result<ScorecardImportResponse, Error>).self) { group in
            for (index, image) in picked.enumerated() {
                group.addTask {
                    guard let jpeg = await Self.jpegData(from: image) else {
                        return (index, .failure(APIError(message: "Couldn't prepare that screenshot.", statusCode: 0)))
                    }
                    do {
                        let response = try await APIClient.shared.importScorecard(jpegData: jpeg, token: token)
                        return (index, .success(response))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for await (index, result) in group {
                switch result {
                case .success(let response): responses.append((index, response))
                case .failure(let error as APIError):
                    if error.isUnauthorized { session.signOut(); return }
                    if firstError == nil { firstError = error }
                case .failure: sawOtherError = true
                }
            }
        }

        guard !responses.isEmpty else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            if let firstError {
                phase = .failed(Self.friendlyMessage(for: firstError))
            } else {
                phase = .failed(sawOtherError
                    ? "Can't reach Sticks. Check your connection and try again."
                    : "Couldn't read that screenshot.")
            }
            return
        }

        let ordered = responses.sorted { $0.0 < $1.0 }.map(\.1)
        var extraWarnings: [String] = []
        let failedCount = picked.count - responses.count
        if failedCount > 0 {
            extraWarnings.append(failedCount == 1
                ? "One screenshot couldn't be read. Check the grid for missing holes."
                : "\(failedCount) screenshots couldn't be read. Check the grid for missing holes.")
        }
        apply(ordered, extraWarnings: extraWarnings, session: session)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        phase = .review
    }

    /// Server messages are golfer-facing; a missing endpoint (the server
    /// side hasn't shipped) gets a clear fallback instead of a raw code.
    static func friendlyMessage(for error: APIError) -> String {
        switch error.statusCode {
        case 404, 405, 501:
            return "Scorecard reading isn't available yet. You can still enter the scores by hand."
        default:
            return error.message
        }
    }

    /// Merges per-image results by absolute hole number and player name.
    private func apply(_ responses: [ScorecardImportResponse], extraWarnings: [String], session: SessionStore) {
        var parByHole: [Int: Int] = [:]
        var holeNumbers = Set<Int>()
        var roundHoles: Int?

        struct Merged {
            var name: String
            var isLikelyMe: Bool
            var strokes: [Int: Int] = [:]
            var uncertain = Set<Int>()
            var total: Int?
            var totalCount = 0
        }
        var merged: [Merged] = []

        func key(_ name: String) -> String {
            name.lowercased().filter { $0.isLetter || $0.isNumber }
        }

        for response in responses {
            if let r = response.roundHoles { roundHoles = max(roundHoles ?? 0, r) }
            for hole in response.holes where (1 ... 18).contains(hole.number) {
                holeNumbers.insert(hole.number)
                if let par = hole.par, (3 ... 6).contains(par) { parByHole[hole.number] = par }
            }
            for (playerIndex, player) in response.players.enumerated() {
                let k = key(player.name)
                let slot: Int
                if !k.isEmpty, let existing = merged.firstIndex(where: { key($0.name) == k }) {
                    slot = existing
                } else if k.isEmpty, merged.indices.contains(playerIndex) {
                    slot = playerIndex
                } else {
                    merged.append(Merged(name: player.name, isLikelyMe: player.isLikelyMe))
                    slot = merged.count - 1
                }
                merged[slot].isLikelyMe = merged[slot].isLikelyMe || player.isLikelyMe
                for score in player.scores where (1 ... 18).contains(score.hole) {
                    holeNumbers.insert(score.hole)
                    if let strokes = score.strokes, (1 ... 15).contains(strokes) {
                        merged[slot].strokes[score.hole] = strokes
                    }
                    if score.uncertain { merged[slot].uncertain.insert(score.hole) }
                }
                if let total = player.total {
                    merged[slot].total = (merged[slot].total ?? 0) + total
                    merged[slot].totalCount += 1
                }
            }
        }

        // Which holes the round covers.
        let hasFront = holeNumbers.contains { $0 <= 9 }
        let hasBack = holeNumbers.contains { $0 >= 10 }
        if hasBack && !hasFront && roundHoles != 18 {
            layout = .back
        } else if hasFront && !hasBack && roundHoles == 9 {
            layout = .front
        } else if hasFront && !hasBack && roundHoles == nil && holeNumbers.count <= 9 {
            // A lone front-nine card: assume a 9-hole round; the picker
            // flips it to 18 in one tap if the back nine was just cut off.
            layout = .front
        } else {
            layout = .full
        }

        pars = (0 ..< holeCount).map { parByHole[holeNumber(at: $0)] }

        // Which row is me.
        let myKeys = Set([key(user.displayName), key(user.username)].filter { !$0.isEmpty })
        var meIndex = merged.firstIndex(where: \.isLikelyMe)
            ?? merged.firstIndex(where: { myKeys.contains(key($0.name)) || $0.name.lowercased() == "you" || $0.name.lowercased() == "me" })
        if meIndex == nil, merged.count == 1 { meIndex = 0 }

        seats = merged.prefix(Self.maxSeats).enumerated().map { index, player in
            var uncertain = Set<Int>()
            let scores: [Int?] = (0 ..< holeCount).map { column in
                let hole = holeNumber(at: column)
                if player.uncertain.contains(hole) { uncertain.insert(column) }
                return player.strokes[hole]
            }
            let isMe = index == meIndex
            return ImportSeat(
                name: isMe ? user.displayName : player.name,
                isMe: isMe,
                scores: scores,
                uncertain: uncertain,
                printedTotal: player.totalCount == responses.count ? player.total : nil
            )
        }
        if seats.isEmpty {
            seats = [blankSeat(isMe: true)]
        }

        // Course + date.
        let first = responses.first
        if let raw = responses.compactMap(\.source).first {
            sourceLabel = Self.sourceName(raw)
        } else {
            sourceLabel = nil
        }
        let courseName = responses.compactMap(\.courseName).first
        if let match = responses.first(where: { $0.matchedCourseId != nil }),
           let id = match.matchedCourseId {
            selectedCourse = CourseResult(
                id: id,
                name: match.matchedCourseName ?? match.courseName ?? "Course",
                city: nil,
                holes: 18,
                access: nil,
                distanceMi: nil
            )
            courseQuery = selectedCourse?.name ?? ""
        } else if let courseName, !courseName.isEmpty {
            courseQuery = courseName
            searchCourses(session: session)
        }
        if let dateString = responses.compactMap(\.date).first ?? first?.date,
           let parsed = Self.parseDay(dateString) {
            playedAt = parsed
        }

        warnings = responses.flatMap(\.warnings) + extraWarnings
    }

    // MARK: - Manual entry

    func startManual() {
        layout = .full
        pars = Array(repeating: nil, count: 18)
        seats = [blankSeat(isMe: true)]
        warnings = []
        thumbnails = []
        sourceLabel = nil
        phase = .review
    }

    private func blankSeat(isMe: Bool) -> ImportSeat {
        ImportSeat(
            name: isMe ? user.displayName : "",
            isMe: isMe,
            scores: Array(repeating: nil, count: holeCount),
            uncertain: [],
            printedTotal: nil
        )
    }

    func startOver() {
        phase = .pick
        thumbnails = []
        warnings = []
        saveError = nil
    }

    // MARK: - Editing

    /// Switches 18 ↔ front 9 ↔ back 9, keeping every score whose hole
    /// survives the change.
    func setLayout(_ newLayout: ImportHoleLayout) {
        guard newLayout != layout else { return }
        let oldStart = layout.startingHole
        let oldPars = pars
        let oldSeats = seats
        layout = newLayout

        func carry<T>(_ values: [T?], _ column: Int) -> T? {
            let hole = holeNumber(at: column)
            let oldIndex = hole - oldStart
            return values.indices.contains(oldIndex) ? values[oldIndex] : nil
        }

        pars = (0 ..< holeCount).map { carry(oldPars, $0) }
        seats = oldSeats.map { seat in
            var copy = seat
            copy.scores = (0 ..< holeCount).map { carry(seat.scores, $0) }
            copy.uncertain = Set((0 ..< holeCount).filter { column in
                seat.uncertain.contains(holeNumber(at: column) - oldStart)
            })
            copy.printedTotal = nil
            return copy
        }
    }

    func setScore(_ value: Int?, seat seatID: UUID, column: Int) {
        guard let index = seats.firstIndex(where: { $0.id == seatID }),
              seats[index].scores.indices.contains(column) else { return }
        seats[index].scores[column] = value
        seats[index].uncertain.remove(column)
    }

    func setPar(_ value: Int?, column: Int) {
        guard pars.indices.contains(column) else { return }
        pars[column] = value
    }

    func markMe(_ seatID: UUID) {
        for index in seats.indices {
            let wasMe = seats[index].isMe
            seats[index].isMe = seats[index].id == seatID
            // The "me" seat posts under the account name; a guest row
            // that stops being me gets its card name back blank-safe.
            if seats[index].isMe { seats[index].name = user.displayName }
            else if wasMe && seats[index].name == user.displayName { seats[index].name = "" }
        }
    }

    func addSeat() {
        guard seats.count < Self.maxSeats else { return }
        seats.append(blankSeat(isMe: !hasMe))
    }

    func removeSeat(_ seatID: UUID) {
        seats.removeAll { $0.id == seatID }
    }

    // MARK: - Course search

    func searchCourses(session: SessionStore) {
        searchTask?.cancel()
        let query = courseQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if let selectedCourse, selectedCourse.name == query { return }
        guard query.count >= 2, let token = session.token else {
            courseResults = []
            isSearchingCourses = false
            return
        }
        isSearchingCourses = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            let response = try? await api.searchCourses(query: query, token: token)
            guard !Task.isCancelled else { return }
            courseResults = response?.courses ?? []
            isSearchingCourses = false
        }
    }

    func selectCourse(_ course: CourseResult) {
        selectedCourse = course
        courseQuery = course.name
        courseResults = []
        searchTask?.cancel()
        isSearchingCourses = false
        if course.holes == 9, layout == .full {
            setLayout(.front)
        }
    }

    func clearCourse() {
        selectedCourse = nil
        courseQuery = ""
        courseResults = []
    }

    // MARK: - Save

    /// Creates the round, applies card pars over the course's, posts
    /// every score, then completes it. Returns the match id on success.
    /// A failure part-way keeps the created round so Save retries
    /// finish it instead of making a duplicate.
    func save(session: SessionStore) async -> String? {
        guard canSave, let course = selectedCourse, let token = session.token else { return nil }
        phase = .saving
        saveError = nil
        saveProgress = 0.02
        let seatsSnapshot = seats

        do {
            // 1. Create (once).
            let matchId: String
            if let createdMatchId {
                matchId = createdMatchId
            } else {
                saveStatus = "Creating round…"
                let players = seatsSnapshot.map { seat in
                    CreateMatchPlayer(
                        displayName: seat.isMe ? user.displayName : seat.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        handicap: seat.isMe ? myHandicap : 0,
                        userId: seat.isMe ? user.id : nil,
                        teeName: nil,
                        teeGender: nil,
                        team: nil
                    )
                }
                let body = CreateMatchRequest(
                    courseName: course.name,
                    holes: holeCount,
                    startingHole: layout.startingHole,
                    scheduledAt: ISO8601DateFormatter().string(from: min(playedAt, Date())),
                    scoringMode: "GROSS",
                    format: "INDIVIDUAL",
                    players: players,
                    sideGames: nil,
                    groupId: nil,
                    tournamentId: nil,
                    teamHandicapMode: nil,
                    teamRules: nil
                )
                matchId = try await api.createMatch(body, token: token).match.id
                createdMatchId = matchId
            }
            saveProgress = 0.1

            // 2. Seat ids + course pars.
            let detail = try await api.matchDetail(id: matchId, token: token).match
            if createdPlayerIds.isEmpty {
                createdPlayerIds = Self.mapSeats(seatsSnapshot, to: detail.players, myUserId: user.id)
            }
            guard createdPlayerIds.count == seatsSnapshot.count else {
                throw APIError(message: "Couldn't match the players on the new round. Try again.", statusCode: 0)
            }

            let merged = (0 ..< holeCount).map { pars[$0] ?? detail.par(at: $0) }
            if merged != detail.pars {
                saveStatus = "Setting pars…"
                _ = try await api.setPars(matchId: matchId, pars: merged, token: token)
            }
            saveProgress = 0.15

            // 3. Scores, six at a time.
            struct Post: Sendable { let playerId: String; let hole: Int; let strokes: Int }
            var posts: [Post] = []
            for seat in seatsSnapshot {
                guard let playerId = createdPlayerIds[seat.id] else { continue }
                for (column, strokes) in seat.scores.enumerated() {
                    if let strokes { posts.append(Post(playerId: playerId, hole: holeNumber(at: column), strokes: strokes)) }
                }
            }
            let totalPosts = max(posts.count, 1)
            var done = 0
            saveStatus = "Saving scores…"
            try await withThrowingTaskGroup(of: Void.self) { group in
                var iterator = posts.makeIterator()
                func enqueue() -> Bool {
                    guard let post = iterator.next() else { return false }
                    group.addTask {
                        try await APIClient.shared.postScore(
                            matchId: matchId,
                            matchPlayerId: post.playerId,
                            hole: post.hole,
                            strokes: post.strokes,
                            token: token
                        )
                    }
                    return true
                }
                for _ in 0 ..< 6 { if !enqueue() { break } }
                while try await group.next() != nil {
                    done += 1
                    saveProgress = 0.15 + 0.8 * Double(done) / Double(totalPosts)
                    saveStatus = "Saving scores… \(done)/\(posts.count)"
                    _ = enqueue()
                }
            }

            // 4. Finish.
            saveStatus = "Finishing…"
            try await api.postComplete(matchId: matchId, token: token)
            saveProgress = 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationCenter.default.post(name: .sticksMatchesDidChange, object: nil)
            return matchId
        } catch let error as APIError {
            if error.isUnauthorized { session.signOut(); return nil }
            fail(error.message)
        } catch {
            fail("Can't reach Sticks. Check your connection and try again.")
        }
        return nil
    }

    private func fail(_ message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        saveError = createdMatchId == nil
            ? message
            : "\(message) The round was started. Tap Save again to finish it."
        phase = .review
    }

    /// Seat → matchPlayerId: the linked "me" seat by userId, guests by
    /// name, then leftovers in creation order.
    private static func mapSeats(_ seats: [ImportSeat], to players: [MatchDetailPlayer], myUserId: String) -> [UUID: String] {
        var result: [UUID: String] = [:]
        var available = players
        for seat in seats where seat.isMe {
            if let index = available.firstIndex(where: { $0.userId == myUserId }) {
                result[seat.id] = available.remove(at: index).id
            }
        }
        for seat in seats where !seat.isMe {
            let name = seat.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let index = available.firstIndex(where: { $0.userId == nil && $0.displayName.lowercased() == name }) {
                result[seat.id] = available.remove(at: index).id
            }
        }
        for seat in seats where result[seat.id] == nil {
            if !available.isEmpty { result[seat.id] = available.removeFirst().id }
        }
        return result
    }

    // MARK: - Helpers

    private static func sourceName(_ raw: String) -> String? {
        switch raw.lowercased() {
        case "18birdies": return "18Birdies"
        case "arccos": return "Arccos"
        case "ghin": return "GHIN"
        case "golfshot": return "Golfshot"
        case "paper": return "a paper card"
        default: return nil
        }
    }

    private static func parseDay(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let day = formatter.date(from: String(string.prefix(10))) else { return nil }
        // Morning tee time on that day, never in the future.
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        return min(morning, Date())
    }

    /// Long edge ≤ 2400 px (scorecard digits need the resolution), JPEG
    /// stepped down until it's under 5 MB.
    nonisolated static func jpegData(from image: UIImage) async -> Data? {
        let maxDimension: CGFloat = 2400
        let maxBytes = 5 * 1024 * 1024
        let size = image.size
        let longEdge = max(size.width * image.scale, size.height * image.scale)
        let scale = longEdge > 0 ? min(1, maxDimension / longEdge) : 1
        let target = CGSize(
            width: (size.width * image.scale * scale).rounded(),
            height: (size.height * image.scale * scale).rounded()
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        var quality: CGFloat = 0.8
        while quality >= 0.3 {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.15
        }
        return nil
    }
}
