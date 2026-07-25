//
//  RoundAlertMode.swift
//  Sticks
//
//  Slice 72: per-round alert overrides. A round can opt IN to pushes
//  even when the viewer's global categories (or their follow/group
//  relationships) wouldn't deliver any — the "important match I want to
//  follow" case — or opt OUT so a noisy round goes quiet without
//  touching global settings.
//
//  Wire value: "default" | "all" | "mute".
//

import Foundation

nonisolated enum RoundAlertMode: String, Codable, CaseIterable, Sendable {
    /// No override — the server's normal follow/group + category rules.
    case standard = "default"
    /// Send every round alert for this round, ignoring category toggles.
    case all = "all"
    /// Send nothing for this round.
    case mute = "mute"

    /// Tolerant decoding — unknown values fall back to `.standard`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RoundAlertMode(rawValue: raw) ?? .standard
    }

    var chipLabel: String {
        switch self {
        case .standard: return "DEFAULT"
        case .all: return "ALL ALERTS"
        case .mute: return "MUTE"
        }
    }

    var iconName: String {
        switch self {
        case .standard: return "bell.badge"
        case .all: return "bell.fill"
        case .mute: return "bell.slash.fill"
        }
    }

    var caption: String {
        switch self {
        case .standard:
            return "Follows your notification settings — you'll only hear about this round if you follow a player or share a group."
        case .all:
            return "Every alert from this round: tee-off, birdies and better, the turn, and final scores."
        case .mute:
            return "No alerts from this round, even from players you follow."
        }
    }
}
