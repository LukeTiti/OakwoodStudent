//
//  ContentView.swift
//  School Notes
//
//  Created by Luke Titi on 9/3/25.
//

import SwiftUI

// MARK: - Cross-Platform View Helpers
extension View {
    @ViewBuilder
    func inlineNavigationBarTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func largeNavigationBarTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    @ViewBuilder
    func macInsetListStyle() -> some View {
        #if os(macOS)
        self.listStyle(.inset(alternatesRowBackgrounds: true))
        #else
        self
        #endif
    }

    @ViewBuilder
    func macRowPadding() -> some View {
        #if os(macOS)
        self.padding(.vertical, 8)
            .padding(.horizontal, 4)
        #else
        self
        #endif
    }

    @ViewBuilder
    func unreadRowBackground(_ isUnread: Int?) -> some View {
        if isUnread == 1 {
            self.listRowBackground(Color.yellow.opacity(0.15))
        } else {
            self
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case insideScoop = "Inside Scoop"
    case toDo = "To Do"
    case grades = "Grades"
    case calendar = "Calendar"
    case service = "Service"
    case directory = "Directory"
    case clubs = "Clubs"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .insideScoop: return "newspaper"
        case .toDo: return "list.bullet"
        case .grades: return "list.bullet.rectangle.portrait"
        case .calendar: return "calendar"
        case .service: return "heart.fill"
        case .directory: return "person.2"
        case .clubs: return "person.3"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .insideScoop: HomeView()
        case .toDo: ToDoPage()
        case .grades: VeracrossGradesView()
        case .calendar: CalendarView()
        case .service: ServiceView()
        case .directory: DirectoryView()
        case .clubs: ClubsView()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appInfo: AppInfo
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var selectedTab = "Grades"

    #if os(macOS)
    @State private var selectedSection: AppSection? = .insideScoop
    #endif

    var body: some View {
        #if os(iOS)
        if !hasCompletedOnboarding {
            OnboardingView()
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        } else {
        TabView(selection: $selectedTab) {
            Tab("Inside Scoop", systemImage: "newspaper", value: "Inside Scoop") {
                HomeView()
            }
            Tab("To Do", systemImage: "list.bullet", value: "To Do") {
                ToDoPage()
            }
            Tab("Grades", systemImage: "list.bullet.rectangle.portrait", value: "Grades") {
                VeracrossGradesView()
                    .onAppear { appInfo.preloadAll() }
            }
            Tab("Calendar", systemImage: "calendar", value: "Calendar") {
                CalendarView()
            }
            Tab("Service", systemImage: "heart.fill", value: "Service") {
                ServiceView()
            }
            Tab("Directory", systemImage: "person.2", value: "Directory") {
                DirectoryView()
            }
            Tab("Clubs", systemImage: "person.3", value: "Clubs") {
                ClubsView()
            }
            Tab("Quick Links", systemImage: "link", value: "Quick Links") {
                QuickLinks()
            }
            Tab("Settings", systemImage: "gear", value: "Settings") {
                SettingsView()
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .opacity
        ))
        } // end else (hasCompletedOnboarding)
        #elseif os(macOS)
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("OW Students")
        } detail: {
            if let section = selectedSection {
                section.destination
                    .dynamicTypeSize(.xxxLarge)
            } else {
                Text("Select a section")
                    .foregroundColor(.secondary)
            }
        }
        #endif
    }
}
