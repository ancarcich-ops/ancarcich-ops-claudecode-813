//
//  TabChrome.swift
//  Sticks
//
//  Slice 29: shared UI chrome state. The bottom tab bar is owned by
//  MainTabView (so it survives navigation pushes) and hides ONLY while
//  the immersive on-course GPS screen is up — that screen sets the
//  flag on appear and restores it on disappear.
//

import Observation

@Observable
final class TabChrome {
    static let shared = TabChrome()

    /// True while the on-course GPS screen is visible.
    var hidesTabBar = false
}
