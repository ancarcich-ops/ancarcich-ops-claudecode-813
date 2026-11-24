//
//  ScorecardImport.swift
//  Sticks
//
//  Shapes for POST /imports/scorecard — the server reads one scorecard
//  screenshot (18Birdies, Arccos, GHIN, paper…) and returns the visible
//  holes, pars and per-player gross scores. Decoded tolerantly: every
//  field may be missing or null. Spec: docs/scorecard-import-spec.md.
//

import Foundation

nonisolated struct ScorecardImportResponse: Decodable {
    let source: String?
    let courseName: String?
    let matchedCourseId: String?
    let matchedCourseName: String?
    /// "YYYY-MM-DD" when the card shows one.
    let date: String?
    let roundHoles: Int?
    let holes: [ImportedHole]
    let players: [ImportedPlayer]
    let warnings: [String]

    private enum CodingKeys: String, CodingKey {
        case source, course, date, roundHoles, holes, players, warnings
    }

    private enum CourseKeys: String, CodingKey {
        case name, matchedCourseId, matchedCourseName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try? container.decodeIfPresent(String.self, forKey: .source)
        if let course = try? container.nestedContainer(keyedBy: CourseKeys.self, forKey: .course) {
            courseName = try? course.decodeIfPresent(String.self, forKey: .name)
            matchedCourseId = try? course.decodeIfPresent(String.self, forKey: .matchedCourseId)
            matchedCourseName = try? course.decodeIfPresent(String.self, forKey: .matchedCourseName)
        } else {
            courseName = nil
            matchedCourseId = nil
            matchedCourseName = nil
        }
        date = try? container.decodeIfPresent(String.self, forKey: .date)
        roundHoles = try? container.decodeIfPresent(Int.self, forKey: .roundHoles)
        holes = (try? container.decodeIfPresent([ImportedHole].self, forKey: .holes)) ?? []
        players = (try? container.decodeIfPresent([ImportedPlayer].self, forKey: .players)) ?? []
        warnings = (try? container.decodeIfPresent([String].self, forKey: .warnings)) ?? []
    }
}

nonisolated struct ImportedHole: Decodable {
    let number: Int
    let par: Int?

    private enum CodingKeys: String, CodingKey { case number, par }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(Int.self, forKey: .number)
        par = try? container.decodeIfPresent(Int.self, forKey: .par)
    }
}

nonisolated struct ImportedScore: Decodable {
    let hole: Int
    let strokes: Int?
    let uncertain: Bool

    private enum CodingKeys: String, CodingKey { case hole, strokes, uncertain }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hole = try container.decode(Int.self, forKey: .hole)
        strokes = try? container.decodeIfPresent(Int.self, forKey: .strokes)
        uncertain = (try? container.decodeIfPresent(Bool.self, forKey: .uncertain)) ?? false
    }
}

nonisolated struct ImportedPlayer: Decodable {
    let name: String
    let scores: [ImportedScore]
    let total: Int?
    let isLikelyMe: Bool

    private enum CodingKeys: String, CodingKey { case name, scores, total, isLikelyMe }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        scores = (try? container.decodeIfPresent([ImportedScore].self, forKey: .scores)) ?? []
        total = try? container.decodeIfPresent(Int.self, forKey: .total)
        isLikelyMe = (try? container.decodeIfPresent(Bool.self, forKey: .isLikelyMe)) ?? false
    }
}
