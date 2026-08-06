//
//  Mac_OnboardingView.swift
//  School Notes
//
//  Created by Luke Titi on 8/4/26.
//
//  macOS equivalent of OnboardingView.swift's step-based onboarding flow.
//  Reuses `onboardingFeatures` and the `Color.oakwoodGreen`/`oakwoodGreenLight`
//  extension declared (non-privately) in OnboardingView.swift rather than
//  duplicating that data. Notifications and Veracross remain skippable; Google
//  sign-in is mandatory, matching the iOS behavior fixed alongside this file.

import SwiftUI
import UserNotifications

// MARK: - Reusable Mac Onboarding Components

private struct Mac_OnboardingIconCircle: View {
    let icon: String
    let style: IconStyle

    enum IconStyle {
        case gradient
        case tinted(Color)
    }

    var body: some View {
        ZStack {
            switch style {
            case .gradient:
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.oakwoodGreenLight, .oakwoodGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 110, height: 110)
                Image(systemName: icon)
                    .font(.system(size: 46))
                    .foregroundStyle(.white)
            case .tinted(let color):
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 110, height: 110)
                Image(systemName: icon)
                    .font(.system(size: 46))
                    .foregroundStyle(color)
            }
        }
    }
}

private struct Mac_OnboardingPrimaryButton: View {
    let label: String
    let icon: String?
    let style: ButtonStyle
    let action: () -> Void

    enum ButtonStyle {
        case gradient
        case solid(Color)
        case primaryColor
    }

    init(_ label: String, icon: String? = nil, style: ButtonStyle = .primaryColor, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon { Image(systemName: icon) }
                Text(label)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(backgroundView)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .gradient:
            LinearGradient(
                colors: [.oakwoodGreenLight, .oakwoodGreen],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .solid(let color):
            color
        case .primaryColor:
            Color.primary
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primaryColor:
            return Color(nsColor: .windowBackgroundColor)
        default:
            return .white
        }
    }
}

private struct Mac_OnboardingSkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Skip for now")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

// MARK: - Main Mac Onboarding Container

struct Mac_OnboardingView: View {
    @EnvironmentObject var appInfo: AppInfo
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var step = 0

    // Steps: 0 = welcome, 1–4 = feature slides, 5 = notifications, 6 = Veracross, 7 = Google, 8 = done

    var body: some View {
        Group {
            switch step {
            case 0:
                Mac_WelcomeOnboardingPage(onNext: advance)
            case 1...4:
                Mac_FeatureOnboardingPage(
                    feature: onboardingFeatures[step - 1],
                    stepIndex: step - 1,
                    totalFeatures: onboardingFeatures.count,
                    onNext: advance,
                    onSkipToSetup: { withAnimation { step = 5 } }
                )
            case 5:
                Mac_NotificationsOnboardingPage(onComplete: advance, onSkip: advance)
            case 6:
                Mac_VeracrossOnboardingPage(onComplete: advance, onSkip: advance)
            case 7:
                Mac_GoogleOnboardingPage(onComplete: advance)
            default:
                Mac_CompleteOnboardingPage {
                    withAnimation {
                        hasCompletedOnboarding = true
                    }
                }
            }
        }
        .id(step)
        .animation(.easeInOut(duration: 0.25), value: step)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 600, idealHeight: 680)
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.25)) {
            step += 1
        }
    }
}

// MARK: - Welcome Page

struct Mac_WelcomeOnboardingPage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Mac_OnboardingIconCircle(icon: "graduationcap.fill", style: .gradient)

                VStack(spacing: 10) {
                    Text("Oakwood Students")
                        .font(.largeTitle.bold())
                    Text("The all new Oakwood app")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Mac_OnboardingPrimaryButton("Get Started", style: .gradient, action: onNext)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
        }
    }
}

// MARK: - Feature Slide Page

struct Mac_FeatureOnboardingPage: View {
    let feature: OnboardingFeature
    let stepIndex: Int
    let totalFeatures: Int
    let onNext: () -> Void
    let onSkipToSetup: () -> Void

    private var isLastFeature: Bool { stepIndex == totalFeatures - 1 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Mac_OnboardingIconCircle(icon: feature.icon, style: .tinted(feature.color))

                VStack(spacing: 10) {
                    Text(feature.title)
                        .font(.largeTitle.bold())
                    Text(feature.description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<totalFeatures, id: \.self) { i in
                    Capsule()
                        .fill(i == stepIndex ? Color.primary : Color.secondary.opacity(0.25))
                        .frame(width: i == stepIndex ? 20 : 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: stepIndex)
                }
            }
            .padding(.bottom, 28)

            VStack(spacing: 12) {
                Mac_OnboardingPrimaryButton(isLastFeature ? "Get Started" : "Next", action: onNext)

                Button(action: onSkipToSetup) {
                    Text("Skip Intro")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Notifications Permission Page

struct Mac_NotificationsOnboardingPage: View {
    let onComplete: () -> Void
    let onSkip: () -> Void
    @State private var requested = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Mac_OnboardingIconCircle(icon: "bell.badge.fill", style: .tinted(.oakwoodGreen))

                VStack(spacing: 10) {
                    Text("Stay in the Loop")
                        .font(.largeTitle.bold())
                    Text("Get notified when your grades are updated so you're never caught off guard.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Mac_OnboardingPrimaryButton("Enable Notifications", icon: "bell.fill", style: .solid(.oakwoodGreen)) {
                    requested = true
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                        if let error {
                            print("Notification permission error: \(error)")
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onComplete()
                        }
                    }
                }
                .disabled(requested)

                Mac_OnboardingSkipButton(action: onSkip)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Veracross Login Page

struct Mac_VeracrossOnboardingPage: View {
    let onComplete: () -> Void
    let onSkip: () -> Void
    @EnvironmentObject var appInfo: AppInfo
    @State private var showingWebView = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 84, height: 84)
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                }
                .padding(.top, 44)

                VStack(spacing: 6) {
                    Text("Connect Veracross")
                        .font(.title.bold())
                    Text("Sign in to load your grades and assignments.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            if showingWebView {
                VeracrossLoginView(
                    url: URL(string: "https://portals.veracross.com/oakwood/student")!,
                    onLogin: {
                        Task {
                            await syncCookies()
                            await appInfo.captureCurrentCookies()
                            appInfo.preloadAll()
                        }
                        onComplete()
                    }
                )
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .padding(.top, 20)
            } else {
                Spacer()
            }

            Spacer()

            VStack(spacing: 12) {
                if !showingWebView {
                    Mac_OnboardingPrimaryButton("Sign In to Veracross", icon: "safari.fill", style: .solid(.green)) {
                        withAnimation { showingWebView = true }
                    }
                }

                Mac_OnboardingSkipButton(action: onSkip)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Google Sign-In Page

struct Mac_GoogleOnboardingPage: View {
    let onComplete: () -> Void
    @EnvironmentObject var appInfo: AppInfo
    // Local state bridged from googleVM so the view re-renders when sign-in completes
    @State private var isSignedIn = false
    @State private var userName = ""
    @State private var userEmail = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Mac_OnboardingIconCircle(icon: "person.circle.fill", style: .tinted(.oakwoodGreen))

                VStack(spacing: 10) {
                    Text("Sign In with Google")
                        .font(.largeTitle.bold())
                    Text("Use your Oakwood Google account to sign up for sports events and report scores.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                if isSignedIn {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.oakwoodGreen)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(userName)
                                .font(.headline)
                            Text(userEmail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Mac_OnboardingPrimaryButton("Continue", style: .solid(.oakwoodGreen), action: onComplete)
                } else {
                    Mac_OnboardingPrimaryButton("Sign In with Google", icon: "person.badge.plus", style: .solid(.oakwoodGreen)) {
                        appInfo.googleVM.signIn()
                    }
                    // Mandatory — no skip option, matching the iOS onboarding fix.
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .onReceive(appInfo.googleVM.$isSignedIn) { value in
            isSignedIn = value
            if value {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    onComplete()
                }
            }
        }
        .onReceive(appInfo.googleVM.$userName) { userName = $0 }
        .onReceive(appInfo.googleVM.$userEmail) { userEmail = $0 }
    }
}

// MARK: - Complete Page

struct Mac_CompleteOnboardingPage: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.oakwoodGreenLight, .oakwoodGreen],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 110, height: 110)
                    Image(systemName: "checkmark")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 10) {
                    Text("You're all set!")
                        .font(.largeTitle.bold())
                    Text("Welcome to Oakwood Students. Dive in and explore.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Mac_OnboardingPrimaryButton("Get Started", style: .gradient, action: onDone)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
        }
    }
}
