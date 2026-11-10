//
//  RoundTemplate.swift
//  Sticks
//
//  Slice 94: GET /round-templates — the signed-in player's saved round
//  setups, newest first (the server owns the order; the app never
//  re-sorts). A template is a PRE-FILL, not a commitment: tapping one
//  answers the wizard's questions and collapses every group to a chip,
//  and everything stays editable from there. The payload's exact shape
//  is unprobed, so every field decodes tolerantly and a template with
//  nothing usable still renders as a tappable row via its summary line.
//

import Foundation

nonisolated struct RoundTemplate: Identifiable {
    let id: String
    let courseName: String?
    /// Parsed tee time (ISO8601) when the template carries one.
    let scheduledAt: Date?
    /// A server-rendered date string ("11/10/26") used as-is.
    let dateText: String?
    let holes: Int?
    let scoringMode: String?
    /// Any hole 1–18 — a shotgun template teeing off 7 applies as 7,
    /// never clamped to the 1/10 presets.
    let startingHole: Int?
    /// The player's handicap as a STRING ("11.6") — applied verbatim,
    /// never round-tripped through a number.
    let handicap: String?
    let playerCount: Int?
    let sideGameCount: Int?
    /// Named side-game kinds when the template carries kinds, not just
    /// a count.
    let sideGames: [String]?
}

extension RoundTemplate: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, templateId, courseName, course, scheduledAt, teeTime
        case date, dateText, holes, scoringMode, startingHole, startHole
        case handicap, playerCount, players, sideGameCount, sideGames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func string(_ key: CodingKeys) -> String? {
            (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        func int(_ key: CodingKeys) -> Int? {
            if let value = (try? container.decodeIfPresent(Int.self, forKey: key)) ?? nil {
                return value
            }
            // Some wire shapes send numbers as strings.
            return string(key).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }

        // id: prefer a real id, fall back to any string-ish field, then a
        // made-up one so the row is still ForEach-able.
        id = string(.id) ?? string(.templateId)
            ?? UUID().uuidString

        courseName = string(.courseName) ?? string(.course)

        // scheduledAt: an ISO8601 string on the wire — parse it, but
        // keep a raw date string around too since the server may send
        // the display form pre-rendered.
        let rawDate = string(.scheduledAt) ?? string(.teeTime)
        scheduledAt = rawDate.flatMap(Self.parseDate)
        dateText = string(.date) ?? string(.dateText)

        holes = int(.holes)
        scoringMode = string(.scoringMode)
        startingHole = int(.startingHole) ?? int(.startHole)

        // The handicap is a string per the wire — but if a number
        // shows up, format it rather than dropping the field.
        if let text = string(.handicap) {
            handicap = text
        } else if let number = (try? container.decodeIfPresent(Double.self, forKey: .handicap)) ?? nil {
            handicap = Self.formatHandicap(number)
        } else {
            handicap = nil
        }

        playerCount = int(.playerCount) ?? int(.players)

        // sideGames may be a KIND LIST or a bare count depending on the
        // shape — read it as an array first, then as a number.
        if let kinds = (try? container.decodeIfPresent([String].self, forKey: .sideGames)) ?? nil {
            sideGames = kinds
            sideGameCount = int(.sideGameCount)
        } else {
            sideGames = nil
            sideGameCount = int(.sideGameCount) ?? int(.sideGames)
        }
    }

    /// "11.6" / "8" — one decimal max, no trailing .0 (mirrors the
    /// create form's formatter; kept local so decoding stays
    /// nonisolated).
    static func formatHandicap(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    /// ISO8601 with or without fractional seconds.
    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: trimmed)
            ?? ISO8601DateFormatter().date(from: trimmed)
    }
}

nonisolated struct RoundTemplatesResponse: Decodable {
    let templates: [RoundTemplate]

    private enum CodingKeys: String, CodingKey {
        case templates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        templates = ((try? container.decode([LenientTemplate].self, forKey: .templates)) ?? [])
            .compactMap(\.value)
    }

    /// Wrapper so one malformed row never sinks the whole list.
    private struct LenientTemplate: Decodable {
        let value: RoundTemplate?
        init(from decoder: Decoder) {
            value = try? RoundTemplate(from: decoder)
        }
    }
}

extension RoundTemplate {
    /// The server's date when pre-rendered, otherwise the parsed tee
    /// time as MM/DD/YY — "11/10/26".
    var displayDate: String? {
        if let dateText, !dateText.trimmingCharacters(in: .whitespaces).isEmpty {
            return dateText.trimmingCharacters(in: .whitespaces)
        }
        guard let scheduledAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter.string(from: scheduledAt)
    }

    /// "Net" / "Gross" / "Custom" from the wire enum — the stored value
    /// is never shown raw.
    var scoringLabel: String? {
        guard let scoringMode else { return nil }
        switch scoringMode.uppercased() {
        case "NET": return "Net"
        case "GROSS": return "Gross"
        case "CUSTOM": return "Custom"
        default: return scoringMode
        }
    }

    /// "Rustic Canyon Golf Course 11/10/26 / 18H · Net · 2 players ·
    /// 1 side game" — the chip row's one-line replay of the saved
    /// setup. Missing pieces are simply left out.
    var summaryLine: String {
        var head = [courseName?.trimmingCharacters(in: .whitespacesAndNewlines), displayDate]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if let holes, holes > 0 {
            head += head.isEmpty ? "\(holes)H" : " / \(holes)H"
        }

        var parts = [head]
        if let scoringLabel { parts.append(scoringLabel) }
        if let playerCount, playerCount > 0 {
            parts.append(playerCount == 1 ? "1 player" : "\(playerCount) players")
        }
        if let sideGameCount, sideGameCount > 0 {
            parts.append(sideGameCount == 1 ? "1 side game" : "\(sideGameCount) side games")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
