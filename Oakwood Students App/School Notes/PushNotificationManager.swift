//
//  PushNotificationManager.swift
//  School Notes
//
//  Created by Luke Titi on 3/24/26.
//

import Foundation
#if os(iOS)
import FirebaseMessaging
import FirebaseFirestore

// Manages FCM token lifecycle and persists tokens to Firestore.
// Tokens are stored at userTokens/{email} so push notifications can be
// targeted to specific users or broadcast to all users from Firebase Console.
class PushNotificationManager: NSObject, MessagingDelegate {
    static let shared = PushNotificationManager()
    private let db = Firestore.firestore()

    private override init() {
        super.init()
    }

    // Call once from AppDelegate after FirebaseApp.configure()
    func configure() {
        Messaging.messaging().delegate = self
    }

    // Call after APNs token is received — topic subscription requires APNs token to be set first
    func subscribeToTopics() {
        Messaging.messaging().subscribe(toTopic: "all-students") { error in
            if let error = error {
                print("Failed to subscribe to topic: \(error)")
            } else {
                print("Subscribed to all-students topic")
            }
        }
    }

    // MARK: - MessagingDelegate

    // Called when FCM generates or refreshes the device's registration token
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        // Always cache the latest token so it's available after sign-in
        UserDefaults.standard.set(token, forKey: "pendingFCMToken")
        saveTokenToFirestore(token)
    }

    // MARK: - Token Storage

    // Save FCM token to Firestore, keyed by the signed-in user's email.
    // Called on token refresh and after sign-in.
    func saveTokenToFirestore(_ token: String) {
        guard let data = UserDefaults.standard.data(forKey: "googleLoginSnapshot"),
              let login = try? JSONDecoder().decode(GoogleLoginSnapshot.self, from: data),
              login.isSignedIn,
              !login.userEmail.isEmpty else {
            return
        }

        let docData: [String: Any] = [
            "fcmToken": token,
            "updatedAt": Timestamp(date: Date()),
            "platform": "iOS"
        ]

        db.collection("userTokens").document(login.userEmail).setData(docData, merge: true) { error in
            if let error = error {
                print("Failed to save FCM token: \(error)")
            } else {
                print("FCM token saved for \(login.userEmail)")
                UserDefaults.standard.removeObject(forKey: "pendingFCMToken")
            }
        }
    }

    // Call this after sign-in — uses the cached token so no extra network call needed
    func refreshTokenForCurrentUser() {
        if let cached = UserDefaults.standard.string(forKey: "pendingFCMToken") {
            saveTokenToFirestore(cached)
        } else {
            Messaging.messaging().token { token, error in
                if let token = token {
                    self.saveTokenToFirestore(token)
                } else if let error = error {
                    print("Error fetching FCM token: \(error)")
                }
            }
        }
    }
}
#endif
