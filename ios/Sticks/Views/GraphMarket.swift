//
//  GraphMarket.swift
//  Sticks
//
//  Slice 71: the market picker model for the Live-odds tab. Each case
//  is one graphable market — Win % plus the side games the server
//  sends chart series for — with its pill label, y-axis caption, and
//  value formatter (matching the web formatters).
//

import SwiftUI

/// Web market identity colors, assigned by seat order — shared by the
/// Win % chart, the market player rows, and the side-game line charts.
enum MarketPalette {
    static func color(_ index: Int) -> Color {
        switch index % 4 {
        case 0: return .sticksGreen
        case 1: return Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
        case 2: return .sticksGold
        default: return .sticksError
        }
    }
}

enum GraphMarket: Identifiable, Hashable {
    case win
    case stableford, skins, nassauF9, nassauB9, nassauTotal, bbb, snake, wolf, match, sixes

    var id: String { label }

    /// Side games in web pill order — Win % is always prepended.
    static let sideGameOrder: [GraphMarket] = [
        .stableford, .skins, .nassauF9, .nassauB9, .nassauTotal,
        .bbb, .snake, .wolf, .match, .sixes,
    ]

    var label: String {
        switch self {
        case .win: return "Win %"
        case .stableford: return "Stableford"
        case .skins: return "Skins"
        case .nassauF9: return "Nassau · F9"
        case .nassauB9: return "Nassau · B9"
        case .nassauTotal: return "Nassau · Total"
        case .bbb: return "BBB"
        case .snake: return "Snake"
        case .wolf: return "Wolf"
        case .match: return "Match"
        case .sixes: return "Sixes"
        }
    }

    /// Y-axis caption under the chart (matches the web).
    var yLabel: String {
        switch self {
        case .win: return "win probability"
        case .stableford, .bbb, .wolf: return "points (cumulative)"
        case .skins: return "skins won"
        case .nassauF9, .nassauB9, .nassauTotal: return "net vs par (lower wins)"
        case .snake: return "3-putts (lower wins)"
        case .match, .sixes: return "dots (cumulative)"
        }
    }

    /// Format a value for the axis/legend (matches the web formatters).
    func format(_ n: Double) -> String {
        let i = Int(n.rounded())
        switch self {
        case .win: return "\(i)%"
        case .stableford, .bbb, .wolf: return "\(i) pt\(i == 1 ? "" : "s")"
        case .skins: return "\(i) skin\(i == 1 ? "" : "s")"
        case .snake: return "\(i) 3-putt\(i == 1 ? "" : "s")"
        case .nassauF9, .nassauB9, .nassauTotal: return i == 0 ? "E" : (i > 0 ? "+\(i)" : "\(i)")
        case .match, .sixes: return i == 0 ? "AS" : (i > 0 ? "+\(i)" : "\(i)")
        }
    }

    /// The series rows for this market from the decoded set (nil for .win).
    func rows(_ series: SideGameSeries?) -> [SideGameSeriesRow]? {
        guard let series else { return nil }
        switch self {
        case .win: return nil
        case .stableford: return series.stableford?.rows
        case .skins: return series.skins?.rows
        case .nassauF9: return series.nassauF9?.rows
        case .nassauB9: return series.nassauB9?.rows
        case .nassauTotal: return series.nassauTotal?.rows
        case .bbb: return series.bbb?.rows
        case .snake: return series.snake?.rows
        case .wolf: return series.wolf?.rows
        case .match: return series.match?.rows
        case .sixes: return series.sixes?.rows
        }
    }
}
