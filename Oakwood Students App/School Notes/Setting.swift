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

    // Local per-platform flag (not synced between iOS/Mac, or across reinstalls of the
    // same platform) — see ContentView.swift / Mac_ContentView.swift's top-level gate.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    // Manual Veracross login trigger — lets users establish a real session on demand
    // (e.g. after a cookie expires) independent of any specific view's own auth flow.
    @State private var showVeracrossLogin = false

    @State private var showResetCloudSyncConfirm = false

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

                // Class Colors Section — optional per-class color, shown as a border on Mac
                // assignment cards and a tint on class name headers in Grades (see AppInfo.classColor).
                if !appInfo.courses.isEmpty {
                    Section {
                        ForEach(appInfo.courses) { course in
                            HStack {
                                Text(course.class_name)
                                    .lineLimit(1)
                                Spacer()
                                if appInfo.classColor(for: course) != nil {
                                    Button {
                                        appInfo.setClassColor(nil, for: course)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                ColorPicker("", selection: classColorBinding(for: course), supportsOpacity: false)
                                    .labelsHidden()
                            }
                        }
                        if !appInfo.classColors.isEmpty {
                            Button(role: .destructive) {
                                appInfo.classColors = [:]
                            } label: {
                                Text("Reset All Class Colors")
                            }
                        }
                    } header: {
                        Text("Class Colors")
                    } footer: {
                        Text("Optional — pick a color to highlight a class throughout the app.")
                    }
                }

                // To Do default view — a synced preference (see AppInfo.todoDefaultShowAll) that
                // seeds ToDoPage/Mac_ToDoView's own "Show All"/"Hide Done" toggle on first appear.
                Section {
                    Toggle("Show All Assignments by Default", isOn: $appInfo.todoDefaultShowAll)
                } header: {
                    Text("To Do")
                } footer: {
                    Text("When off, the To Do page starts hiding completed assignments. You can still toggle Show All/Hide Done per visit.")
                }

                // App Info Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersionString)
                            .foregroundColor(.secondary)
                    }
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Text("Privacy")
                    }
                }

                Section("Onboarding (Debug)") {
                    Button("Reset Onboarding") {
                        hasCompletedOnboarding = false
                    }
                    .foregroundColor(.red)
                }

                // Wipes assignment completion/notes, followed clubs, calendar links, and
                // community service entries — both locally and from iCloud. Must be tapped on
                // EVERY device to actually converge; one device alone will just get overwritten
                // by whatever the other device still has on the next sync.
                Section("iCloud Sync (Debug)") {
                    Button("Reset All Synced Data") {
                        showResetCloudSyncConfirm = true
                    }
                    .foregroundColor(.red)
                }
                .confirmationDialog(
                    "Reset all synced data?",
                    isPresented: $showResetCloudSyncConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Reset Everything", role: .destructive) {
                        Task { await appInfo.resetCloudSyncedData() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This clears assignment completion, notes, followed clubs, calendar links, and community service entries — locally and in iCloud. Run this on every device to truly start fresh.")
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
            #if os(iOS)
            .fullScreenCover(isPresented: $showVeracrossLogin) {
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
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showVeracrossLogin = false }
                        }
                    }
                }
            }
            #elseif os(macOS)
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
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showVeracrossLogin = false }
                        }
                    }
                }
                .frame(minWidth: 480, minHeight: 600)
            }
            #endif
        }
    }

    /// Binding used by each Class Colors row's ColorPicker. Falls back to `.gray` when no
    /// custom color is set yet — purely the picker's initial swatch, not a stored value; nothing
    /// is written to `appInfo.classColors` until the student actually picks a color.
    private func classColorBinding(for course: Course) -> Binding<Color> {
        Binding(
            get: { appInfo.classColor(for: course) ?? .gray },
            set: { appInfo.setClassColor($0, for: course) }
        )
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
