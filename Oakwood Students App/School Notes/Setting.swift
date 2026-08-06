//
//  Setting.swift
//  School Notes
//
//  Created by Luke Titi on 9/5/25.
//

import SwiftUI

/// Reads the version/build straight from the app's own bundle (set in Xcode's target "General"
/// tab under Version/Build) so this never drifts out of sync with a manually-typed string.
private var appVersionString: String {
    let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    return "\(shortVersion) (\(build))"
}

// MARK: - SettingsView (Account settings and sign-in)
struct SettingsView: View {
    @EnvironmentObject var appInfo: AppInfo
    #if os(iOS)
    @AppStorage("gradeNotificationsEnabled") private var gradeNotificationsEnabled = true
    #endif

    // CloudKit Notification Lab diagnostics — see Models.swift "CloudKit Notification Lab"
    // section for the actual test functions. This is pure UI wiring for those tests.
    @State private var labStatus: String = ""
    @State private var isRunningLabTest = false

    // Manual Veracross login trigger — independent of `isBundledMode`. Directory and
    // Community Service always hit live Veracross endpoints (never part of the bundled
    // summer JSON), so users need a way to establish a real session even while Grades/To Do
    // are running off bundled data. See root CLAUDE.md "Bundled Summer Mode" section.
    @State private var showVeracrossLogin = false

    var body: some View {
        NavigationStack {
            List {
                #if os(iOS)
                // Notifications Section
                Section {
                    Toggle(isOn: $gradeNotificationsEnabled) {
                        HStack {
                            Image(systemName: "bell.badge")
                                .foregroundColor(.red)
                            Text("Grade Notifications")
                        }
                    }
                    .onChange(of: gradeNotificationsEnabled) { _, enabled in
                        if enabled {
                            GradeNotificationService.shared.requestNotificationPermission()
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get notified when your grades change. Requires logging into Grades tab first.")
                }
                #endif

                // Account Section
                Section("Account") {
                    if appInfo.googleVM.isSignedIn {
                        // Signed in - show user info
                        HStack(spacing: 15) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(appInfo.googleVM.userName)
                                    .font(.headline)
                                Text(appInfo.googleVM.userEmail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)

                        Button(role: .destructive) {
                            appInfo.googleVM.signOut()
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                            }
                        }
                    } else {
                        // Not signed in - show sign in button
                        VStack(spacing: 12) {
                            Image(systemName: "person.circle")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("Sign in to submit service hours and sync your data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)

                        Button {
                            appInfo.googleVM.signIn()
                        } label: {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                Text("Sign in with Google")
                            }
                        }
                    }

                    Button {
                        showVeracrossLogin = true
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                            Text("Log in to Veracross")
                        }
                    }
                }

                // App Info Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersionString)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Please report any suggestions or issues to Luke Titi, Big thanks to everyone who is testing this app!")
                    }
                }

                // CloudKit Notification Lab (Debug) — experimental diagnostics for tracking
                // down why CKQuerySubscription push notifications aren't firing. Each button
                // runs a different configuration variation; results print to Xcode's console
                // with a "[CloudKitLab]" prefix and are also shown inline below.
                Section("CloudKit Notification Lab (Debug)") {
                    Button {
                        runLabTest { await testFullyExplicitSubscription() }
                    } label: {
                        Text("Test: Fully Explicit Subscription")
                    }
                    .disabled(isRunningLabTest)

                    Button {
                        runLabTest { await testWildcardPredicateSubscription() }
                    } label: {
                        Text("Test: Wildcard Predicate (per Apple's QA1917)")
                    }
                    .disabled(isRunningLabTest)

                    Button {
                        runLabTest { await testRecordZoneSubscription() }
                    } label: {
                        Text("Test: Record Zone Subscription")
                    }
                    .disabled(isRunningLabTest)

                    Button {
                        runLabTest { await fetchAllMySubscriptions() }
                    } label: {
                        Text("List My Subscriptions")
                    }
                    .disabled(isRunningLabTest)

                    Button {
                        runLabTest { await testOperationBasedSubscription() }
                    } label: {
                        Text("Test: Operation-Based API (CKModifySubscriptionsOperation)")
                    }
                    .disabled(isRunningLabTest)

                    Button {
                        runLabTest { await cleanUpLabSubscriptions() }
                    } label: {
                        Text("Clean Up Lab Subscriptions")
                    }
                    .disabled(isRunningLabTest)

                    Button {
                        runLabTest { await resetClubSubscriptions(followedClubIDs: appInfo.followedClubIDs) }
                    } label: {
                        Text("Reset Club Subscriptions")
                    }
                    .disabled(isRunningLabTest)

                    if isRunningLabTest {
                        HStack {
                            ProgressView()
                            Text("Running test…")
                                .foregroundColor(.secondary)
                        }
                    }

                    if !labStatus.isEmpty {
                        Text(labStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showVeracrossLogin) {
                NavigationStack {
                    VeracrossLoginView(
                        url: URL(string: "https://portals.veracross.com/oakwood/student")!,
                        onLogin: {
                            Task {
                                await syncCookies()
                                await appInfo.captureCurrentCookies()
                            }
                            showVeracrossLogin = false
                        }
                    )
                    .navigationTitle("Login to Veracross")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showVeracrossLogin = false }
                        }
                    }
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 600)
                #endif
            }
        }
    }

    /// Runs a CloudKit Notification Lab diagnostic test on a background Task and reflects its
    /// result string in `labStatus`. Kept generic over the async closure so each of the lab
    /// buttons (including the cleanup button) can share the same run/disable/status wiring.
    private func runLabTest(_ test: @escaping () async -> String) {
        isRunningLabTest = true
        labStatus = ""
        Task {
            let result = await test()
            await MainActor.run {
                labStatus = result
                isRunningLabTest = false
            }
        }
    }
}
