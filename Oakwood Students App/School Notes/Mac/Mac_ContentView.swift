//
//  Mac_ContentView.swift
//  School Notes
//
//  Created by Luke Titi on 6/18/26.
//
import SwiftUI

struct Mac_ContentView: View {
    @EnvironmentObject var appInfo: AppInfo
    @State private var loginState: GradesLoginState = .checking

    var body: some View {
        switch loginState {
        case .checking:
            ProgressView("Connecting to Veracross…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await checkLogin() }
        case .needsLogin:
            VeracrossLoginView(
                url: URL(string: "https://portals.veracross.com/oakwood/student")!,
                onLogin: {
                    Task {
                        await syncCookies()
                        await appInfo.captureCurrentCookies()
                        loginState = .loggedIn
                    }
                }
            )
        case .loggedIn:
            sidebar
        }
    }

    private var sidebar: some View {
        NavigationSplitView {
            List {
                NavigationLink(destination: HomeView()) {
                    Label("Inside Scoop", systemImage: "newspaper")
                }
                NavigationLink(destination: Mac_ToDoView()) {
                    Label("To Do", systemImage: "list.bullet")
                }
                NavigationLink(destination: Mac_GradesView()) {
                    Label("Grades", systemImage: "list.bullet.rectangle.portrait")
                }
                NavigationLink(destination: Mac_CalendarView()) {
                    Label("Calendar", systemImage: "calendar")
                }
                NavigationLink(destination: Mac_ServiceView()) {
                    Label("Service", systemImage: "heart.fill")
                }
                NavigationLink(destination: Mac_DirectoryView()) {
                    Label("Directory", systemImage: "person.2")
                }
                NavigationLink(destination: Mac_ClubsView()) {
                    Label("Clubs", systemImage: "person.3")
                }
                NavigationLink(destination: Mac_QuickLinksView()) {
                    Label("Quick Links", systemImage: "link")
                }
            }
        } detail: {
            Text("Select an item")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Oakwood Students")
    }

    /// Directory and Service always scrape live Veracross pages — unlike Grades/To Do,
    /// they were never part of the bundled-JSON summer data, so they need a real
    /// session regardless of `isBundledMode`. `loadCourses()` doubles as the auth
    /// probe here since it always hits the live endpoint and reports back whether
    /// the session is valid.
    private func checkLogin() async {
        await appInfo.restorePersistedCookiesIntoStores()
        await syncCookies()
        let err = await appInfo.loadCourses()
        loginState = (err == nil) ? .loggedIn : .needsLogin
    }
}
