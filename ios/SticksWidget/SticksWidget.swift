//
//  SticksWidget.swift
//  SticksWidget
//
//  Simple branded home screen widget. The real on-course experience is
//  the RoundLiveActivity — this widget points people at it.
//

import WidgetKit
import SwiftUI

nonisolated struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
    }
}

nonisolated struct SimpleEntry: TimelineEntry {
    let date: Date
}

struct WidgetView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "flag.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color.sticksGreen)
            Text("Sticks")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Color.sticksInk)
            Text("Live yardages appear on your lock screen during a round")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.sticksMuted)
                .multilineTextAlignment(.center)
        }
        .containerBackground(Color.sticksCream, for: .widget)
    }
}

struct SticksWidget: Widget {
    let kind: String = "SticksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Sticks")
        .description("On-course yardages go live during a round.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
