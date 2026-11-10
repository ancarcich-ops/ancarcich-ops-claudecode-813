//
//  DisplayPrefs.swift
//  Sticks
//
//  Slice 96: GET/POST /me/display-prefs — the account's display
//  choices. `showReactions` decides whether reaction rows RENDER
//  anywhere in the app; it is deliberately separate from the reactions
//  PUSH toggle (/me/push-prefs), which decides whether the phone
//  buzzes. Account-scoped, so turning it off here also quiets the
//  website for the same login.
//

import Foundation

nonisolated struct DisplayPrefsResponse: Decodable {
    var prefs: DisplayPrefs
}

nonisolated struct DisplayPrefs {
    /// Only a real boolean counts — a wire value of the string "false"
    /// is IGNORED rather than read as truthy, so the default (shown)
    /// stands until the server sends a real off.
    var showReactions: Bool = true
}

extension DisplayPrefs: Decodable {
    private enum CodingKeys: String, CodingKey {
        case showReactions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showReactions = (try? container.decodeIfPresent(Bool.self, forKey: .showReactions)) ?? true
    }
}

/// A partial POST body — the server leaves any key not sent exactly as
/// it was, so the app only ever sends the one key it owns.
nonisolated struct DisplayPrefsUpdate: Encodable {
    let showReactions: Bool
}
