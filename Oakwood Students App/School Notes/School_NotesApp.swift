//
//  School_NotesApp.swift
//  School Notes
//
//  Created by Luke Titi on 9/3/25.
//

import SwiftUI
import SwiftData
import Combine
import GoogleSignIn
import FirebaseCore

@main
struct School_NotesApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must run before anything touches Auth.auth() (the Google Sign-In -> Firebase Auth
        // bridge in AppDelegate.swift fires from .onAppear below). Lives here instead of the
        // platform AppDelegates' launch callbacks because App.init() is the one place both
        // platforms guarantee runs first — macOS's applicationDidFinishLaunching isn't reliably
        // early enough relative to SwiftUI's .onAppear.
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "566131280116-vl10j0masc2tme0m06rqr8f8b0j8lsb3.apps.googleusercontent.com"
        )
    }

    @StateObject private var appInfo = AppInfo()

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            Mac_ContentView()
                .environmentObject(appInfo)
                .frame(minWidth: 600, idealWidth: 900, minHeight: 550, idealHeight: 700)
                .onAppear {
                    appInfo.startCloudSyncPolling()
                    appInfo.googleVM.restoreFirebaseSessionIfNeeded()
                }
            #else
            ContentView()
                .environmentObject(appInfo)
                .onAppear {
                    appInfo.startCloudSyncPolling()
                    appInfo.googleVM.restoreFirebaseSessionIfNeeded()
                }
                .onOpenURL { url in
                    guard url.scheme == "oakwood" else { return }
                    if url.host() == "assignment",
                       let idStr = url.pathComponents.dropFirst().first,
                       let id = Int(idStr) {
                        appInfo.pendingAssignmentId = id
                        appInfo.selectedTab = "Grades"
                    }
                }
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appInfo.startCloudSyncPolling()
            } else {
                appInfo.stopCloudSyncPolling()
            }
            #if os(iOS)
            if newPhase == .background {
                GradeNotificationService.shared.scheduleBackgroundRefresh()
            }
            #endif
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appInfo)
        }
        #endif
    }
}

//@main
//struct School_NotesApp: App {
//    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
//    init() {
//            // ✅ Set clientID here (no Info.plist needed)
//            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
//                clientID: "566131280116-vl10j0masc2tme0m06rqr8f8b0j8lsb3.apps.googleusercontent.com"
//            )
//        }
//    var body: some Scene {
//        WindowGroup {
//            
//            SignInView()
//        }
//    }
//}

