//
//  CalendarWidgetShared.swift
//  School Notes + CalendarWidget
//
//  This file must belong to BOTH the main app target and the CalendarWidget target.
//
import Foundation

let appGroupID = "group.com.luketiti.oakwoodStudent"
let widgetEventsKey = "widgetCalendarEvents"
let widgetAssignmentsKey = "widgetTodoAssignments"

struct WidgetCalendarEvent: Codable, Identifiable {
    let id: String
    let title: String
    let date: Date
    let timeText: String
    let badgeLabel: String
    let colorName: String   // "blue", "teal", "indigo", "red", "orange", "green", "purple"
    let location: String
}

