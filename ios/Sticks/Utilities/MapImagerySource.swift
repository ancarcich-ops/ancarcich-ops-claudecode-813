//
//  MapImagerySource.swift
//  Sticks
//
//  Slice 66: which satellite imagery the on-course 2D map renders.
//  Persisted via @AppStorage("mapImagerySource") — default Esri, with
//  the original Apple `Map` path one Settings tap away. The GPS screen
//  reads it live, so flipping the toggle swaps the renderer instantly.
//

import Foundation

nonisolated enum MapImagerySource: String, CaseIterable, Identifiable {
    case esri = "esri"
    case apple = "apple"

    var id: String { rawValue }

    var label: String { self == .esri ? "Esri (sharper)" : "Apple" }
}
