//
//  SideGameSettingsSchema.swift
//  Sticks
//
//  The settings each side game takes, for the CREATE step — before a
//  match exists. Served as `sideGames` on GET /round-options, the same
//  shape as the per-match picker (GET /matches/:id/side-games). No
//  bundled copy: the server owns it. A new round sends the picked
//  settings inline as `sideGameConfigs` on POST /matches.
//

import Foundation

/// One game's settings fields, as served.
nonisolated struct SideGameSchema: Decodable, Hashable {
    let kind: String
    let settings: [SideGameSetting]
    /// False when the game needs more than a flat form (Match's
    /// per-player strokes, Team vs team's rules, Stableford and BBB
    /// points tables).
    let settingsComplete: Bool
    /// Stated, not applied — the create step turns them into blockers.
    let requires18: Bool?
    let requires4Players: Bool?

    private enum CodingKeys: String, CodingKey {
        case kind, settings, settingsComplete, requires18, requires4Players
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        settings = (try? container.decodeIfPresent([SideGameSetting].self, forKey: .settings)) ?? []
        settingsComplete = (try? container.decode(Bool.self, forKey: .settingsComplete)) ?? true
        requires18 = try? container.decodeIfPresent(Bool.self, forKey: .requires18)
        requires4Players = try? container.decodeIfPresent(Bool.self, forKey: .requires4Players)
    }
}
