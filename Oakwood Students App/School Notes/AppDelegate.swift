//
//  AppDelegate.swift
//  School Notes
//
//  Created by Luke Titi on 9/10/25.
//

import SwiftUI
import Combine
import GoogleSignIn
import FirebaseCore

#if os(iOS)
import BackgroundTasks
import UserNotifications

// MARK: - AppDelegate for Firebase, Google Sign-In, and Background Tasks
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()

        // Set notification delegate to show alerts while app is open
        UNUserNotificationCenter.current().delegate = self

        // Request notification permission
        GradeNotificationService.shared.requestNotificationPermission()

        // Register background task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: GradeNotificationService.backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }

        return true
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }

    // Handle background refresh task
    private func handleBackgroundRefresh(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            await GradeNotificationService.shared.checkForNewGradesBackground()
            task.setTaskCompleted(success: true)
            GradeNotificationService.shared.scheduleBackgroundRefresh()
        }
    }
}

#elseif os(macOS)
import AppKit

// MARK: - macOS AppDelegate
class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FirebaseApp.configure()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            _ = GIDSignIn.sharedInstance.handle(url)
        }
    }
}
#endif

// MARK: - ViewModel for Google Sign-In
class GoogleSignInViewModel: ObservableObject {
    @Published var isSignedIn = false
    @Published var userName = ""
    @Published var userEmail = ""

    private let clientID = "661195592928-e56dd9keruoftlpcbf7s07h3fn22s7vn.apps.googleusercontent.com"

    func signIn() {
        #if os(iOS)
        guard let rootViewController = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first?.rootViewController else { return }

        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
                let user = result.user
                self.userName = user.profile?.name ?? ""
                self.userEmail = user.profile?.email ?? ""
                self.isSignedIn = true
            } catch { }
        }
        #elseif os(macOS)
        guard let window = NSApplication.shared.keyWindow else { return }

        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
                let user = result.user
                self.userName = user.profile?.name ?? ""
                self.userEmail = user.profile?.email ?? ""
                self.isSignedIn = true
            } catch { }
        }
        #endif
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
        userName = ""
        userEmail = ""
    }
}

// MARK: - Main Sign In View
struct SignInView: View {
    @EnvironmentObject var appInfo: AppInfo

    var body: some View {
        Text("Please Sign in:")
        VStack(spacing: 20) {
            if appInfo.googleVM.isSignedIn {
                Text("Welcome, \(appInfo.googleVM.userName)")
                Text("Email: \(appInfo.googleVM.userEmail)")
                Button("Sign Out") {
                    appInfo.googleVM.signOut()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Sign in with Google") {
                    appInfo.googleVM.signIn()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .onChange(of: appInfo.googleVM.isSignedIn) { newValue in
            if newValue {
                appInfo.reloadID = UUID()
                appInfo.signInSheet = false
            }
        }
    }
}
