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
import FirebaseAuth
import FirebaseMessaging
import CloudKit

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

        // Nothing in this app ever sets the app icon's badge number (no subscription here
        // uses shouldBadge, no notification content sets .badge) — so a stuck badge count
        // can only be a stale leftover from earlier testing. Clear it on every launch.
        UNUserNotificationCenter.current().setBadgeCount(0)

        // Configure FCM token manager
        PushNotificationManager.shared.configure()

        // Only request notification permission if onboarding is complete —
        // new users are prompted during the onboarding flow instead
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            GradeNotificationService.shared.requestNotificationPermission()
        }
        application.registerForRemoteNotifications()

        // Register background task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: GradeNotificationService.backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }

        return true
    }

    // Pass the APNs device token to Firebase so it can generate an FCM token
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        // Now that APNs token is set, retry topic subscription
        PushNotificationManager.shared.subscribeToTopics()
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }

    // Handles the silent CKQuerySubscription push from subscribeToClubActivity (Models.swift).
    // That push carries no alert text of its own — it just wakes the app so it can fetch the
    // real ClubActivity record and fire a local notification with the actual club/announcement
    // text via checkForNewClubAnnouncements(), rather than depending on CloudKit's own alert
    // templating (which needs Xcode localization infrastructure this project doesn't have).
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        Task {
            await checkForNewClubAnnouncements()
            await scheduleFollowedClubEventReminders()
            completionHandler(.newData)
        }
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
            await checkForNewClubAnnouncements()
            await scheduleFollowedClubEventReminders()
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
    /// Set when a sign-in attempt succeeds with Google but is rejected because the
    /// account isn't part of the school's Google Workspace domain. Cleared on any
    /// successful, accepted sign-in. UI can observe this to surface an error message.
    @Published var signInError: String? = nil

    private let clientID = "566131280116-vl10j0masc2tme0m06rqr8f8b0j8lsb3.apps.googleusercontent.com"

    /// The school's Google Workspace domain. Only accounts on this domain are permitted
    /// to sign in (do not confuse with oakwoodway.org, the public marketing site domain).
    private let allowedDomain = "@oakwoodstudent.org"

    /// Validates a completed Google Sign-In result against the school's Workspace domain
    /// and updates published state accordingly. Shared by both the iOS and macOS sign-in
    /// code paths so the enforcement logic lives in exactly one place.
    private func handleSignInResult(_ result: GIDSignInResult) {
        let user = result.user
        let email = user.profile?.email ?? ""
        guard email.lowercased().hasSuffix(allowedDomain.lowercased()) else {
            GIDSignIn.sharedInstance.signOut()
            self.signInError = "Please sign in with your Oakwood Google account (@oakwoodstudent.org), not a personal Google account."
            return
        }
        bridgeToFirebaseAuth(user: user, email: email, name: user.profile?.name ?? "")
    }

    /// Exchanges the Google ID token for a real Firebase Auth session so Firestore security
    /// rules can trust request.auth.token.email instead of taking the app's word for who's
    /// signed in. isSignedIn only flips to true once this succeeds, since features backed by
    /// Firestore (Community Service) need a live server-verified identity, not just a local flag.
    private func bridgeToFirebaseAuth(user: GIDGoogleUser, email: String, name: String) {
        guard let idToken = user.idToken?.tokenString else {
            self.signInError = "Sign-in failed (missing token). Please try again."
            return
        }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: user.accessToken.tokenString)
        Auth.auth().signIn(with: credential) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.signInError = "Sign-in failed: \(error.localizedDescription)"
                return
            }
            self.signInError = nil
            self.userName = name
            self.userEmail = email
            self.isSignedIn = true
        }
    }

    /// Silently re-establishes the Firebase Auth session on app launch from a cached Google
    /// sign-in, so Firestore rules keep working without prompting the user again every launch.
    /// Failures here are intentionally quiet and don't touch isSignedIn — the rest of the app's
    /// "signed in" state is restored separately from AppInfo's own local snapshot, and only
    /// Firestore-backed features (Community Service) actually need this session to be live.
    func restoreFirebaseSessionIfNeeded() {
        guard Auth.auth().currentUser == nil else { return }
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            guard let self, let user else { return }
            let email = user.profile?.email ?? ""
            guard email.lowercased().hasSuffix(self.allowedDomain.lowercased()) else { return }
            self.bridgeToFirebaseAuth(user: user, email: email, name: user.profile?.name ?? "")
        }
    }

    func signIn() {
        #if os(iOS)
        guard let rootViewController = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first?.rootViewController else { return }

        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
                self.handleSignInResult(result)
            } catch { }
        }
        #elseif os(macOS)
        guard let window = NSApplication.shared.keyWindow else { return }

        Task {
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
                self.handleSignInResult(result)
            } catch { }
        }
        #endif
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
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

                if let signInError = appInfo.googleVM.signInError {
                    Text(signInError)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
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
