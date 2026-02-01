//
//  Setting.swift
//  School Notes
//
//  Created by Luke Titi on 9/5/25.
//

import SwiftUI

// MARK: - SettingsView (Account settings and sign-in)
struct SettingsView: View {
    @EnvironmentObject var appInfo: AppInfo

    var body: some View {
        NavigationStack {
            List {
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
                }

                // App Info Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
