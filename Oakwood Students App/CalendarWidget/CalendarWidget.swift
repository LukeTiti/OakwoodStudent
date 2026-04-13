//
//  CalendarWidget.swift
//  CalendarWidget
//
import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct CalendarEntry: TimelineEntry {
    let date: Date
    let events: [WidgetCalendarEvent]
}

// MARK: - Provider

struct CalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry {
        CalendarEntry(date: Date(), events: sampleEvents)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        completion(CalendarEntry(date: Date(), events: loadEvents()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        let entry = CalendarEntry(date: Date(), events: loadEvents())
        let nextMidnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    private func loadEvents() -> [WidgetCalendarEvent] {
        let today = Calendar.current.startOfDay(for: Date())
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: widgetAssignmentsKey),
              let events = try? JSONDecoder().decode([WidgetCalendarEvent].self, from: data) else { return [] }
        return events.filter { $0.date >= today }
    }
}

// MARK: - Color Helper

func widgetColor(_ name: String) -> Color {
    switch name {
    case "teal":   return .teal
    case "indigo": return .indigo
    case "red":    return .red
    case "orange": return .orange
    case "green":  return .green
    case "purple": return .purple
    default:       return .blue
    }
}

// MARK: - Relative Date Label

func relativeDateLabel(for date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date)    { return "Today" }
    if cal.isDateInTomorrow(date) { return "Tomorrow" }
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE, MMM d"
    return formatter.string(from: date)
}

// MARK: - Shared Event Row

struct WidgetEventRow: View {
    let event: WidgetCalendarEvent
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(widgetColor(event.colorName))
                .frame(width: 4)
                .frame(maxHeight: compact ? 36 : 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(event.badgeLabel)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(widgetColor(event.colorName).opacity(0.15))
                        .foregroundColor(widgetColor(event.colorName))
                        .clipShape(Capsule())
                    if !event.timeText.isEmpty {
                        Text("·").font(.caption2).foregroundColor(.secondary)
                        Text(event.timeText).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if !compact {
                Text(relativeDateLabel(for: event.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

// MARK: - Small Widget Row

struct SmallWidgetRow: View {
    let event: WidgetCalendarEvent

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(widgetColor(event.colorName))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(event.badgeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget View

struct CalendarWidgetEntryView: View {
    var entry: CalendarEntry
    @Environment(\.widgetFamily) var family

    private var isSmall: Bool { family == .systemSmall }

    private var maxEvents: Int {
        switch family {
        case .systemSmall:  return 4
        case .systemMedium: return 3
        default:            return 6
        }
    }

    private var visibleEvents: [WidgetCalendarEvent] {
        Array(entry.events.prefix(maxEvents))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Upcoming")
                    .font(isSmall ? .caption2 : .headline)
                    .foregroundStyle(isSmall ? .secondary : .primary)
                    .textCase(isSmall ? .uppercase : nil)
                Spacer()
                if !isSmall {
                    Text(Date(), style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, isSmall ? 4 : 8)

            if visibleEvents.isEmpty {
                Spacer()
                Text("No upcoming events")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: isSmall ? 5 : 6) {
                    ForEach(visibleEvents) { event in
                        if isSmall {
                            SmallWidgetRow(event: event)
                        } else {
                            WidgetEventRow(event: event, compact: false)
                            if event.id != visibleEvents.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isSmall ? 11 : 16)
        .containerBackground(.background, for: .widget)
    }
}

// MARK: - Widget Definition

struct CalendarWidget: Widget {
    let kind: String = "CalendarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarProvider()) { entry in
            CalendarWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Oakwood Calendar")
        .description("See upcoming school events, sports, and your schedule.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Sample Data (Previews)

private let sampleEvents: [WidgetCalendarEvent] = [
    WidgetCalendarEvent(id: "1", title: "Varsity Soccer vs. Hillcrest", date: Date(), timeText: "4:00 PM", badgeLabel: "Varsity Soccer", colorName: "blue", location: "Home Field"),
    WidgetCalendarEvent(id: "2", title: "AP Biology", date: Date(), timeText: "8:00 AM - 9:00 AM", badgeLabel: "My Schedule", colorName: "indigo", location: "Room 204"),
    WidgetCalendarEvent(id: "3", title: "Spring Concert", date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!, timeText: "7:00 PM", badgeLabel: "School Event", colorName: "teal", location: "Auditorium"),
]

#Preview(as: .systemSmall) {
    CalendarWidget()
} timeline: {
    CalendarEntry(date: .now, events: sampleEvents)
}

#Preview(as: .systemMedium) {
    CalendarWidget()
} timeline: {
    CalendarEntry(date: .now, events: sampleEvents)
}

#Preview(as: .systemLarge) {
    CalendarWidget()
} timeline: {
    CalendarEntry(date: .now, events: sampleEvents)
}
