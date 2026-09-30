//
//  PrivacyView.swift
//  School Notes
//

import SwiftUI

/// Static privacy statement shown from Settings. Deliberately plain text (not fetched from
/// anywhere) so it can't silently go stale or fail to load — update this file directly when
/// the app's data handling changes.
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your Privacy")
                    .font(.title2.bold())

                Text("This app is built for Oakwood students and only works with your Oakwood school account. Here's what it does with your information.")

                group("What this app collects") {
                    bullet("Your name and email, from signing in with your Oakwood Google account (@oakwoodstudent.org). Personal Google accounts can't sign in.")
                    bullet("Your grades and assignments, pulled from Veracross only while you're logged into it — this data stays on your device and in your own iCloud account.")
                    bullet("Community service hours you submit: the hours, your reflections, and your supervisor's name, title, email, and signature.")
                }

                group("How your community service data is protected") {
                    bullet("Every form is tied to your verified Oakwood sign-in — the database itself checks this, not just the app, so no one can view, submit, or delete someone else's form by guessing a link or an ID.")
                    bullet("Your supervisor signs on a private, one-time link sent to their email. Only they can sign it, and only for that one form.")
                    bullet("Forms can't be created, edited into a fake \"approved\" state, or deleted by anyone outside the app's own submit/approve process.")
                }

                group("Who sees it") {
                    bullet("Your advisor, to review and approve your hours.")
                    bullet("Veracross, once a form is approved, so your official hours record is updated.")
                    bullet("No one else. Your information is never sold or shared outside of approving your service hours.")
                }

                Text("Questions or concerns?")
                    .font(.headline)
                    .padding(.top, 8)
                Text("Email lukti28@oakwoodstudent.org.")
            }
            .padding()
        }
        .navigationTitle("Privacy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

#Preview {
    NavigationStack { PrivacyView() }
}
