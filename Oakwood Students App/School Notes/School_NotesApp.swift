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

@main
struct School_NotesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "661195592928-e56dd9keruoftlpcbf7s07h3fn22s7vn.apps.googleusercontent.com"
        )
    }

    @StateObject private var appInfo = AppInfo()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appInfo)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // Schedule background refresh when app goes to background
                GradeNotificationService.shared.scheduleBackgroundRefresh()
            }
        }
    }
}

//@main
//struct School_NotesApp: App {
//    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
//    init() {
//            // ✅ Set clientID here (no Info.plist needed)
//            GIDSignIn.sharedInstance.configuration = GIDConfiguration(
//                clientID: "661195592928-e56dd9keruoftlpcbf7s07h3fn22s7vn.apps.googleusercontent.com"
//            )
//        }
//    var body: some Scene {
//        WindowGroup {
//            
//            SignInView()
//        }
//    }
//}

