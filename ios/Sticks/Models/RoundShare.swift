//
//  RoundShare.swift
//  Sticks
//
//  Slice 29: a live share link for a round — public URL, whether the
//  viewer sees the caller's scores, an optional ETA-home destination,
//  and a heads-up buffer in minutes.
//

import Foundation

nonisolated struct RoundShare: Decodable, Identifiable, Hashable {
    let id: String
    let token: String
    let url: String
    let includeScores: Bool
    let destAddress: String?
    let bufferMin: Int
}
