//
//  SideGameSettingsSchema.swift
//  Sticks
//
//  The settings each side game takes, for the CREATE step — before a
//  match exists. The server only serves this schema per match
//  (GET /matches/:id/side-games), so creation reads, in order:
//    1. `sideGames` on GET /round-options, when the server ships it
//       (requested in docs/rork-slice-create-side-game-settings.md);
//    2. this bundled copy, captured verbatim from the live per-match
//       picker on 2026-11-14.
//  POST /matches ignores inline configs (verified live), so the picked
//  settings are posted after creation via POST /matches/:id/side-game-config.
//

import Foundation

/// One game's settings fields, as served.
nonisolated struct SideGameSchema: Decodable, Hashable {
    let kind: String
    let settings: [SideGameSetting]
    /// False when the game needs more than a flat form (Match's
    /// per-player strokes, Team vs team's rules).
    let settingsComplete: Bool

    private enum CodingKeys: String, CodingKey {
        case kind, settings, settingsComplete
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        settings = (try? container.decodeIfPresent([SideGameSetting].self, forKey: .settings)) ?? []
        settingsComplete = (try? container.decode(Bool.self, forKey: .settingsComplete)) ?? true
    }
}

extension SideGameSchema {
    /// Bundled fallback — the live schema verbatim. Served copy wins.
    static let fallback: [SideGameSchema] = {
        let data = Data(fallbackJSON.utf8)
        return (try? JSONDecoder().decode([SideGameSchema].self, from: data)) ?? []
    }()

    private static let fallbackJSON = #"""
[
  {
    "kind": "STABLEFORD",
    "settingsComplete": true,
    "settings": []
  },
  {
    "kind": "SKINS",
    "settingsComplete": true,
    "settings": [
      {
        "key": "pushRule",
        "label": "On tied holes",
        "type": "choice",
        "default": "CARRYOVER",
        "choices": [
          {
            "value": "CARRYOVER",
            "label": "Carry over",
            "blurb": "Skin rolls to the next hole."
          },
          {
            "value": "NO_CARRY",
            "label": "No carry",
            "blurb": "Tied hole pays nothing; reset to 1."
          }
        ]
      }
    ]
  },
  {
    "kind": "NASSAU",
    "settingsComplete": true,
    "settings": [
      {
        "key": "stake",
        "label": "Stake per bet",
        "type": "money",
        "default": null,
        "min": 0,
        "blurb": "Front nine, back nine and total are priced separately. Empty or 0 means no money."
      },
      {
        "key": "autoPress",
        "label": "Auto-press",
        "type": "boolean",
        "default": false,
        "blurb": "Start a fresh line whenever somebody goes far enough ahead."
      },
      {
        "key": "autoPressThreshold",
        "label": "Press at",
        "type": "number",
        "default": 2,
        "min": 1,
        "max": 9,
        "step": 1,
        "dependsOn": "autoPress",
        "blurb": "How many holes ahead starts a new line."
      }
    ]
  },
  {
    "kind": "BBB",
    "settingsComplete": true,
    "settings": []
  },
  {
    "kind": "SNAKE",
    "settingsComplete": true,
    "settings": [
      {
        "key": "stake",
        "label": "Stake",
        "type": "money",
        "default": null,
        "min": 0,
        "blurb": "What the snake is worth at the end. Empty or 0 means no money."
      },
      {
        "key": "doubling",
        "label": "Doubles each pass",
        "type": "boolean",
        "default": false,
        "blurb": "The snake is worth twice as much every time it changes hands."
      }
    ]
  },
  {
    "kind": "WOLF",
    "settingsComplete": true,
    "settings": [
      {
        "key": "pushRule",
        "label": "On tied holes",
        "type": "choice",
        "default": "CARRYOVER",
        "choices": [
          {
            "value": "CARRYOVER",
            "label": "Carry over"
          },
          {
            "value": "NO_CARRY",
            "label": "No carry"
          }
        ]
      }
    ]
  },
  {
    "kind": "TEAM_VS_TEAM",
    "settingsComplete": false,
    "settings": []
  },
  {
    "kind": "MATCH",
    "settingsComplete": false,
    "settings": []
  },
  {
    "kind": "SIXES",
    "settingsComplete": true,
    "settings": [
      {
        "key": "stake",
        "label": "Stake",
        "type": "money",
        "default": null,
        "min": 0,
        "blurb": "Empty or 0 means no money."
      }
    ]
  },
  {
    "kind": "TARGETS",
    "settingsComplete": true,
    "settings": [
      {
        "key": "stat",
        "label": "Target",
        "type": "choice",
        "default": "PAR_OR_BETTER",
        "choices": [
          {
            "value": "PAR_OR_BETTER",
            "label": "Pars or better"
          },
          {
            "value": "BIRDIE_OR_BETTER",
            "label": "Birdies or better"
          }
        ]
      },
      {
        "key": "target",
        "label": "How many",
        "type": "number",
        "default": 9,
        "min": 1,
        "max": 18,
        "step": 1,
        "blurb": "The number everybody aims for."
      },
      {
        "key": "ante",
        "label": "Ante",
        "type": "money",
        "default": null,
        "min": 0,
        "blurb": "Per player. Winners split the pot; all-hit or no-hit refunds. Empty or 0 means no ante."
      }
    ]
  }
]
"""#
}
