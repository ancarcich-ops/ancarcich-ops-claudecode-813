//
//  SticksClubsMark.swift
//  Sticks
//
//  The brand mark — three golf-club silhouettes drawn as vector Paths
//  from the brand kit's exact SVG geometry (64×64 viewBox). Replaces
//  the app-icon PNG tile everywhere the mark appears in-app (splash,
//  login wordmark, home header). Each club is its own Shape so the
//  splash can pop them in individually with a per-club baseline anchor.
//

import SwiftUI

/// The three clubs of the mark, in left-to-right order.
nonisolated enum SticksClub: Int, CaseIterable, Identifiable {
    case iron
    case driver
    case wedge

    nonisolated var id: Int { rawValue }

    /// The inner vertical flip line from the brand kit:
    /// `translate(0, flipY) scale(1, -1)` → y' = flipY − y.
    nonisolated var flipY: CGFloat {
        switch self {
        case .iron: return 68
        case .driver: return 62
        case .wedge: return 72
        }
    }

    /// Raw brand-kit path in SVG coordinates (before flip and nudge).
    nonisolated var rawPath: Path {
        switch self {
        case .iron: return Self.ironGeometry
        case .driver: return Self.driverGeometry
        case .wedge: return Self.wedgeGeometry
        }
    }

    /// The club's path in the 64×64 viewBox: inner flip applied, whole
    /// group nudged +4.5 in x.
    nonisolated var viewBoxPath: Path {
        let transform = CGAffineTransform(translationX: 4.5, y: flipY)
            .scaledBy(x: 1, y: -1)
        return rawPath.applying(transform)
    }

    /// Bottom-center of this club within the mark's square frame —
    /// the transform origin for the splash's "drop onto the baseline"
    /// pop (unit coordinates of the 64×64 viewBox).
    nonisolated var baselineAnchor: UnitPoint {
        let bounds = viewBoxPath.boundingRect
        return UnitPoint(x: bounds.midX / 64, y: bounds.maxY / 64)
    }

    // MARK: - Brand kit geometry (64×64 viewBox)

    private nonisolated static let ironGeometry: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 19.57, y: 14.60))
        p.addQuadCurve(to: CGPoint(x: 18.97, y: 14.00), control: CGPoint(x: 19.57, y: 14.00))
        p.addLine(to: CGPoint(x: 15.03, y: 14.00))
        p.addQuadCurve(to: CGPoint(x: 14.43, y: 14.60), control: CGPoint(x: 14.43, y: 14.00))
        p.addLine(to: CGPoint(x: 14.43, y: 46.10))
        p.addCurve(
            to: CGPoint(x: 5.50, y: 49.19),
            control1: CGPoint(x: 14.43, y: 48.10),
            control2: CGPoint(x: 10.68, y: 46.40)
        )
        p.addCurve(
            to: CGPoint(x: 7.70, y: 54.00),
            control1: CGPoint(x: 5.50, y: 52.37),
            control2: CGPoint(x: 6.00, y: 54.00)
        )
        p.addCurve(
            to: CGPoint(x: 19.57, y: 50.67),
            control1: CGPoint(x: 12.98, y: 54.10),
            control2: CGPoint(x: 17.30, y: 53.80)
        )
        p.addCurve(
            to: CGPoint(x: 19.57, y: 45.80),
            control1: CGPoint(x: 19.57, y: 48.45),
            control2: CGPoint(x: 19.57, y: 47.10)
        )
        p.addLine(to: CGPoint(x: 19.57, y: 14.60))
        p.closeSubpath()
        return p
    }()

    private nonisolated static let driverGeometry: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 34.57, y: 6.60))
        p.addQuadCurve(to: CGPoint(x: 33.97, y: 6.00), control: CGPoint(x: 34.57, y: 6.00))
        p.addLine(to: CGPoint(x: 30.03, y: 6.00))
        p.addQuadCurve(to: CGPoint(x: 29.43, y: 6.60), control: CGPoint(x: 29.43, y: 6.00))
        p.addLine(to: CGPoint(x: 29.43, y: 47.00))
        p.addCurve(
            to: CGPoint(x: 18.50, y: 50.48),
            control1: CGPoint(x: 29.43, y: 49.00),
            control2: CGPoint(x: 24.57, y: 47.30)
        )
        p.addCurve(
            to: CGPoint(x: 20.70, y: 56.00),
            control1: CGPoint(x: 18.50, y: 54.13),
            control2: CGPoint(x: 19.00, y: 56.00)
        )
        p.addCurve(
            to: CGPoint(x: 34.57, y: 52.17),
            control1: CGPoint(x: 27.27, y: 56.10),
            control2: CGPoint(x: 32.30, y: 55.80)
        )
        p.addCurve(
            to: CGPoint(x: 34.57, y: 46.70),
            control1: CGPoint(x: 34.57, y: 49.63),
            control2: CGPoint(x: 34.57, y: 48.00)
        )
        p.addLine(to: CGPoint(x: 34.57, y: 6.60))
        p.closeSubpath()
        return p
    }()

    private nonisolated static let wedgeGeometry: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 49.57, y: 22.60))
        p.addQuadCurve(to: CGPoint(x: 48.97, y: 22.00), control: CGPoint(x: 49.57, y: 22.00))
        p.addLine(to: CGPoint(x: 45.03, y: 22.00))
        p.addQuadCurve(to: CGPoint(x: 44.43, y: 22.60), control: CGPoint(x: 44.43, y: 22.00))
        p.addLine(to: CGPoint(x: 44.43, y: 42.50))
        p.addCurve(
            to: CGPoint(x: 37.00, y: 45.45),
            control1: CGPoint(x: 44.43, y: 44.50),
            control2: CGPoint(x: 41.50, y: 42.80)
        )
        p.addCurve(
            to: CGPoint(x: 39.20, y: 50.00),
            control1: CGPoint(x: 37.00, y: 48.46),
            control2: CGPoint(x: 37.50, y: 50.00)
        )
        p.addCurve(
            to: CGPoint(x: 49.57, y: 46.85),
            control1: CGPoint(x: 43.50, y: 50.10),
            control2: CGPoint(x: 47.30, y: 49.80)
        )
        p.addCurve(
            to: CGPoint(x: 49.57, y: 42.20),
            control1: CGPoint(x: 49.57, y: 44.75),
            control2: CGPoint(x: 49.57, y: 43.50)
        )
        p.addLine(to: CGPoint(x: 49.57, y: 22.60))
        p.closeSubpath()
        return p
    }()
}

/// One club of the mark as a Shape, scaled to fit the given rect
/// (64×64 viewBox mapped uniformly, centered).
struct SticksClubShape: Shape {
    let club: SticksClub

    nonisolated func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 64
        let transform = CGAffineTransform(
            translationX: rect.midX - 32 * scale,
            y: rect.midY - 32 * scale
        )
        .scaledBy(x: scale, y: scale)
        return club.viewBoxPath.applying(transform)
    }
}

/// The complete static three-club mark, filled with the accent green
/// by default. Square — size it with `.frame(width:height:)`.
struct SticksClubsMark: View {
    var color: Color = .sticksGreen

    var body: some View {
        ZStack {
            ForEach(SticksClub.allCases) { club in
                SticksClubShape(club: club)
                    .fill(color)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Color.sticksBg.ignoresSafeArea()
        SticksClubsMark()
            .frame(width: 120, height: 120)
    }
}
