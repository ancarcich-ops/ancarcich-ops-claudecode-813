//
//  TutorialTours.swift
//  Sticks
//
//  The words for every coach-mark tour, and the anchor ids the screens
//  tag. Steps whose target isn't on screen are dropped when the tour
//  starts, so copy never assumes a step before it was shown.
//

import Foundation

enum TutorialAnchor {
    static let tabHome = "tab.home"
    static let tabGroups = "tab.groups"
    static let tabStats = "tab.stats"
    static let tabSettings = "tab.settings"

    static let homeNewRound = "home.newRound"
    static let homeSwitcher = "home.switcher"
    static let homeFirstCard = "home.firstCard"

    static let groupsList = "groups.list"
    static let groupsTournaments = "groups.tournaments"
    static let groupsCreate = "groups.create"
    static let groupsJoin = "groups.join"

    static let statsHero = "stats.hero"
    static let statsGlance = "stats.glance"
    static let statsTrend = "stats.trend"
    static let statsLogged = "stats.logged"
    static let statsShare = "stats.share"

    static let settingsHandicap = "settings.handicap"
    static let settingsPeople = "settings.people"
    static let settingsNotifications = "settings.notifications"
    static let settingsWatch = "settings.watch"
    static let settingsReplay = "settings.replay"

    static let matchActions = "match.actions"
    static let matchTabs = "match.tabs"
    static let matchGPS = "match.gps"
    static let matchScorecard = "match.scorecard"
    static let matchStandings = "match.standings"
    static let matchShare = "match.share"

    static let createSteps = "create.steps"
    static let createCourse = "create.course"
    static let createPrimary = "create.primary"
    static let createSideGames = "create.sideGames"
}

enum TutorialTours {
    /// Right after the welcome: a lap of the tab bar, then Home's header.
    static let tabs: [TutorialStep] = [
        TutorialStep(
            target: nil,
            title: "Welcome to Sticks",
            body: "Sticks has four main tabs. Here's a quick lap around them, then you're on the tee.",
            icon: "hand.wave"
        ),
        TutorialStep(
            target: TutorialAnchor.tabHome,
            title: "Home",
            body: "Every round from you and your groups. Live rounds sit up top, with win odds that move as scores come in.",
            icon: "house"
        ),
        TutorialStep(
            target: TutorialAnchor.tabGroups,
            title: "Groups",
            body: "Private feeds for your regular crews. Invite friends with a code, check the leaderboard, run tournaments.",
            icon: "person.2"
        ),
        TutorialStep(
            target: TutorialAnchor.tabStats,
            title: "Stats",
            body: "Your Sticks index, scoring trends, course bests and every round you've logged.",
            icon: "chart.bar"
        ),
        TutorialStep(
            target: TutorialAnchor.tabSettings,
            title: "Settings",
            body: "Profile, handicap, notifications and your Apple Watch.\nCome back here any time to replay these tutorials.",
            icon: "gearshape"
        ),
        TutorialStep(
            target: TutorialAnchor.homeNewRound,
            title: "New round",
            body: "Tee one up from any tab: pick the course, seat your group, add side games. Takes about a minute.",
            icon: "plus"
        ),
        TutorialStep(
            target: TutorialAnchor.homeSwitcher,
            title: "Your feed, your groups",
            body: "Switch between all your groups, one group, or public rounds. Your account and sign-out live in here too.",
            icon: "line.3.horizontal"
        ),
        TutorialStep(
            target: TutorialAnchor.homeFirstCard,
            title: "Open a round",
            body: "Tap any card for the full scorecard, live odds and side games. + Pick calls who you think will win.",
            icon: "hand.tap"
        ),
    ]

    static let groups: [TutorialStep] = [
        TutorialStep(
            target: TutorialAnchor.groupsList,
            title: "Your groups",
            body: "Each group is a private feed: only members see its rounds. Tap a card to open it, or Leaderboard for the standings. Share the invite code to add friends.",
            icon: "person.2"
        ),
        TutorialStep(
            target: TutorialAnchor.groupsTournaments,
            title: "Tournaments",
            body: "Stringing rounds together or playing with a big field? A tournament keeps one leaderboard across every round.",
            icon: "trophy",
            scrolls: true
        ),
        TutorialStep(
            target: TutorialAnchor.groupsCreate,
            title: "Start a group",
            body: "Name it and you'll get an invite code to share.",
            icon: "plus.circle",
            scrolls: true
        ),
        TutorialStep(
            target: TutorialAnchor.groupsJoin,
            title: "Join a group",
            body: "Got a code from a friend? Paste it here.",
            icon: "ticket",
            scrolls: true
        ),
    ]

    static let stats: [TutorialStep] = [
        TutorialStep(
            target: TutorialAnchor.statsHero,
            title: "Your Sticks index",
            body: "Worked out from your posted rounds, with each tee's rating and slope. Set a goal in Settings and it shows here.",
            icon: "dial.medium"
        ),
        TutorialStep(
            target: TutorialAnchor.statsGlance,
            title: "At a glance",
            body: "Wins, birdies and form across every round you've played.",
            icon: "square.grid.2x2",
            scrolls: true
        ),
        TutorialStep(
            target: TutorialAnchor.statsTrend,
            title: "Rounds over time",
            body: "One bar per round. Pick a baseline to see whether you're beating it.",
            icon: "chart.bar.xaxis",
            scrolls: true
        ),
        TutorialStep(
            target: TutorialAnchor.statsLogged,
            title: "Logged rounds",
            body: "Every round you've played. Use a round's menu to remove your scores or delete a round you made.",
            icon: "list.bullet",
            scrolls: true
        ),
        TutorialStep(
            target: TutorialAnchor.statsShare,
            title: "Share your stats",
            body: "Sends a link to your public profile. Anyone can open it, no account needed.",
            icon: "square.and.arrow.up",
            scrolls: true
        ),
    ]

    static let settings: [TutorialStep] = [
        TutorialStep(
            target: TutorialAnchor.settingsHandicap,
            title: "Handicap",
            body: "Your index, your GHIN number and an index goal to chase.",
            icon: "dial.medium",
            scrolls: true
        ),
        TutorialStep(
            target: TutorialAnchor.settingsPeople,
            title: "People",
            body: "Find friends, follow them and answer follow requests. Add your phone number so friends can find you.",
            icon: "person.crop.circle.badge.plus",
            scrolls: true
        ),
        TutorialStep(
            target: TutorialAnchor.settingsNotifications,
            title: "Notifications",
            body: "Pick which round alerts buzz your phone.",
            icon: "bell",
            scrolls: true
        ),
        TutorialStep(
            target: TutorialAnchor.settingsWatch,
            title: "Apple Watch & Health",
            body: "Score and see yardages from your wrist. Rounds save to Health as a golf workout.",
            icon: "applewatch",
            scrolls: true
        ),
        TutorialStep(
            target: TutorialAnchor.settingsReplay,
            title: "Replay tutorials",
            body: "Tap here any time to see these tours again.",
            icon: "arrow.counterclockwise",
            scrolls: true
        ),
    ]

    static let match: [TutorialStep] = [
        TutorialStep(
            target: TutorialAnchor.matchActions,
            title: "Round menu",
            body: "Edit the round, change its settings, mark it final or delete it.",
            icon: "ellipsis"
        ),
        TutorialStep(
            target: TutorialAnchor.matchTabs,
            title: "Scorecard, odds, recap",
            body: "Flip between the card and live win odds. Finished rounds also get a recap.",
            icon: "rectangle.split.3x1"
        ),
        TutorialStep(
            target: TutorialAnchor.matchGPS,
            title: "On-course GPS",
            body: "Distances to the front, center and back of the green, plus a 3D flyover of every hole.",
            icon: "location.fill"
        ),
        TutorialStep(
            target: TutorialAnchor.matchScorecard,
            title: "Scorecard",
            body: "Tap a hole to enter a score if you're playing. Colors show birdies, pars and bogeys at a glance.",
            icon: "tablecells",
            scrolls: true
        ),
        TutorialStep(
            target: TutorialAnchor.matchStandings,
            title: "Standings",
            body: "Who's winning each side game, updated with every score.",
            icon: "list.number",
            scrolls: true
        ),
        TutorialStep(
            target: TutorialAnchor.matchShare,
            title: "Share the round",
            body: "A live link anyone can follow, even without the app.",
            icon: "square.and.arrow.up",
            scrolls: true
        ),
    ]

    static let createRound: [TutorialStep] = [
        TutorialStep(
            target: TutorialAnchor.createSteps,
            title: "Three quick steps",
            body: "Round, Players, then Side games. Solo rounds skip the last one.",
            icon: "list.number"
        ),
        TutorialStep(
            target: TutorialAnchor.createCourse,
            title: "Find your course",
            body: "Search by name, or use courses near you. Tee, holes and format come next.",
            icon: "mappin.and.ellipse"
        ),
        TutorialStep(
            target: TutorialAnchor.createPrimary,
            title: "Next",
            body: "Lights up once a step has what it needs. You can always go back.",
            icon: "arrow.right"
        ),
    ]

    static let createSideGames: [TutorialStep] = [
        TutorialStep(
            target: TutorialAnchor.createSideGames,
            title: "Pick your games",
            body: "Tap a game to add it. Its settings, like stakes and points, open right under it. Some need 18 holes or four players.",
            icon: "flag.2.crossed"
        ),
        TutorialStep(
            target: TutorialAnchor.createPrimary,
            title: "Create the round",
            body: "That's it. You can change side games from the round later.",
            icon: "checkmark"
        ),
    ]
}
