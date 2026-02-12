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
}

enum AppSection: String, CaseIterable, Identifiable {
    case insideScoop = "Inside Scoop"
    case toDo = "To Do"
    case grades = "Grades"
    case sports = "Sports"
    case service = "Service"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .insideScoop: return "newspaper"
        case .toDo: return "list.bullet"
        case .grades: return "list.bullet.rectangle.portrait"
        case .sports: return "trophy.fill"
        case .service: return "heart.fill"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .insideScoop: HomeView()
        case .toDo: ToDoPage()
        case .grades: VeracrossGradesView()
        case .sports: SportsView()
        case .service: ServiceView()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var appInfo: AppInfo

    #if os(macOS)
    @State private var selectedSection: AppSection? = .insideScoop
    #endif

    var body: some View {
        #if os(iOS)
        TabView {
            Tab("Inside Scoop", systemImage: "newspaper") {
                HomeView()
            }
            Tab("To Do", systemImage: "list.bullet") {
                ToDoPage()
            }
            Tab("Grades", systemImage: "list.bullet.rectangle.portrait") {
                VeracrossGradesView()
            }
            Tab("Sports", systemImage: "trophy.fill") {
                SportsView()
            }
            Tab("Service", systemImage: "heart.fill") {
                ServiceView()
            }
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
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
