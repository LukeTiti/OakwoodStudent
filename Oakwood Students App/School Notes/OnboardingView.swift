//
//  OnboardingView.swift
//  School Notes
//
//  Created by Luke Titi on 3/26/26.
//

import SwiftUI

// MARK: - Feature Data

struct OnboardingFeature {
    let icon: String
    let color: Color
    let title: String
    let description: String
}

private let onboardingFeatures: [OnboardingFeature] = [
    OnboardingFeature(
        icon: "newspaper.fill",
        color: .oakwoodGreen,
        title: "Inside Scoop",
        description: "Stay up to date with Oakwood news, campus announcements, and what's happening today."
    ),
    OnboardingFeature(
        icon: "list.bullet.rectangle.portrait.fill",
        color: .oakwoodGreen,
        title: "Grades & Assignments",
        description: "View your grades and upcoming assignments from Veracross — all in one place."
    ),
    OnboardingFeature(
        icon: "figure.run",
        color: .oakwoodGreen,
        title: "Sports",
        description: "Follow Oakwood sports schedules, live scores, and sign up to work games."
    ),
    OnboardingFeature(
        icon: "heart.fill",
        color: .oakwoodGreen,
        title: "Service & More",
        description: "Track your community service hours and access links and resources."
    ),
]

private extension Color {
    static let oakwoodGreen = Color(red: 0.13, green: 0.55, blue: 0.27)
    static let oakwoodGreenLight = Color(red: 0.22, green: 0.78, blue: 0.40)
}

// MARK: - Reusable Onboarding Components

private struct OnboardingIconCircle: View {
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
                    .frame(width: 130, height: 130)
                Image(systemName: icon)
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
            case .tinted(let color):
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 130, height: 130)
                Image(systemName: icon)
                    .font(.system(size: 56))
                    .foregroundStyle(color)
            }
        }
    }
}

private struct OnboardingPrimaryButton: View {
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
            .padding(.vertical, 16)
            .background(backgroundView)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
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
            return Color(.systemBackground)
        default:
            return .white
        }
    }
}

private struct OnboardingSkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Skip for now")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Main Onboarding Container

struct OnboardingView: View {
    @EnvironmentObject var appInfo: AppInfo
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var step = 0

    // Steps: 0 = welcome, 1–4 = feature slides, 5 = notifications, 6 = Veracross, 7 = Google, 8 = done

    var body: some View {
        Group {
            switch step {
            case 0:
                WelcomeOnboardingPage(onNext: advance)
            case 1...4:
                FeatureOnboardingPage(
                    feature: onboardingFeatures[step - 1],
                    stepIndex: step - 1,
                    totalFeatures: onboardingFeatures.count,
                    onNext: advance,
                    onSkipToSetup: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { step = 5 } }
                )
            case 5:
                NotificationsOnboardingPage(onComplete: advance, onSkip: advance)
            case 6:
                VeracrossOnboardingPage(onComplete: advance, onSkip: advance)
            case 7:
                GoogleOnboardingPage(onComplete: advance, onSkip: advance)
            default:
                CompleteOnboardingPage {
                    appInfo.markPastAssignmentsCompleted()
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        hasCompletedOnboarding = true
                    }
                }
            }
        }
        .id(step)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
    }

    private func advance() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            step += 1
        }
    }
}

// MARK: - Welcome Page

struct WelcomeOnboardingPage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                OnboardingIconCircle(icon: "graduationcap.fill", style: .gradient)

                VStack(spacing: 12) {
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

            OnboardingPrimaryButton("Get Started", style: .gradient, action: onNext)
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
        }
    }
}

// MARK: - Feature Slide Page

struct FeatureOnboardingPage: View {
    let feature: OnboardingFeature
    let stepIndex: Int
    let totalFeatures: Int
    let onNext: () -> Void
    let onSkipToSetup: () -> Void

    private var isLastFeature: Bool { stepIndex == totalFeatures - 1 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                OnboardingIconCircle(icon: feature.icon, style: .tinted(feature.color))

                VStack(spacing: 12) {
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
                        .animation(.spring(response: 0.3), value: stepIndex)
                }
            }
            .padding(.bottom, 32)

            VStack(spacing: 14) {
                OnboardingPrimaryButton(isLastFeature ? "Get Started" : "Next", action: onNext)

                Button(action: onSkipToSetup) {
                    Text("Skip Intro")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }
}

// MARK: - Notifications Permission Page

struct NotificationsOnboardingPage: View {
    let onComplete: () -> Void
    let onSkip: () -> Void
    @State private var requested = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                OnboardingIconCircle(icon: "bell.badge.fill", style: .tinted(.oakwoodGreen))

                VStack(spacing: 12) {
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

            VStack(spacing: 14) {
                OnboardingPrimaryButton("Enable Notifications", icon: "bell.fill", style: .solid(.oakwoodGreen)) {
                    requested = true
                    GradeNotificationService.shared.requestNotificationPermission()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onComplete()
                    }
                }
                .disabled(requested)

                OnboardingSkipButton(action: onSkip)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }
}

// MARK: - Veracross Login Page

struct VeracrossOnboardingPage: View {
    let onComplete: () -> Void
    let onSkip: () -> Void
    @EnvironmentObject var appInfo: AppInfo
    @State private var showingWebView = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 100, height: 100)
                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.green)
                }
                .padding(.top, 64)

                VStack(spacing: 8) {
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
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.top, 24)
            } else {
                Spacer()
            }

            Spacer()

            VStack(spacing: 14) {
                if !showingWebView {
                    OnboardingPrimaryButton("Sign In to Veracross", icon: "safari.fill", style: .solid(.green)) {
                        withAnimation { showingWebView = true }
                    }
                }

                OnboardingSkipButton(action: onSkip)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
        }
    }
}

// MARK: - Google Sign-In Page

struct GoogleOnboardingPage: View {
    let onComplete: () -> Void
    let onSkip: () -> Void
    @EnvironmentObject var appInfo: AppInfo
    // Local state bridged from googleVM so the view re-renders when sign-in completes
    @State private var isSignedIn = false
    @State private var userName = ""
    @State private var userEmail = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                OnboardingIconCircle(icon: "person.circle.fill", style: .tinted(.oakwoodGreen))

                VStack(spacing: 12) {
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

            VStack(spacing: 14) {
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
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    OnboardingPrimaryButton("Continue", style: .solid(.oakwoodGreen), action: onComplete)
                } else {
                    OnboardingPrimaryButton("Sign In with Google", icon: "person.badge.plus", style: .solid(.oakwoodGreen)) {
                        appInfo.googleVM.signIn()
                    }

                    OnboardingSkipButton(action: onSkip)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
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

struct CompleteOnboardingPage: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.oakwoodGreenLight, .oakwoodGreen],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 130, height: 130)
                    Image(systemName: "checkmark")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 12) {
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

            OnboardingPrimaryButton("Get Started", style: .gradient, action: onDone)
                .padding(.horizontal, 32)
                .padding(.bottom, 52)
        }
    }
}
