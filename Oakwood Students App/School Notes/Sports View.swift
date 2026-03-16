//
//  Sports View.swift
//  School Notes
//
//  Created by Luke Titi on 10/5/25.
//
import SwiftUI

// MARK: - Badge View
struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Sports Event
struct SportsEvent: Identifiable {
    let id: String
    let title: String
    let date: Date
    let startTime: String
    let endTime: String
    let location: String
    let isAway: Bool
    let isCancelled: Bool
    let sportName: String
    let teamName: String

    var opponent: String {
        var opp = title
        opp = opp.replacingOccurrences(of: "\\s*\\((?:Away|Home|CANCELLED)\\)", with: "", options: .regularExpression)

        let colonComponents = opp.components(separatedBy: ": ")
        if colonComponents.count > 1 {
            opp = colonComponents.last ?? opp
        }

        if let vsRange = opp.range(of: "\\s+vs\\s+", options: .regularExpression) {
            opp = String(opp[vsRange.upperBound...])
        }

        return opp.trimmingCharacters(in: .whitespaces)
    }

    var timeText: String {
        endTime.isEmpty ? startTime : "\(startTime) - \(endTime)"
    }
}

// MARK: - School Event
struct SchoolEvent: Identifiable {
    let id: String
    let title: String
    let date: Date
    let startTime: String
    let endTime: String
    let location: String
    let description: String

    var timeText: String {
        endTime.isEmpty ? startTime : "\(startTime) - \(endTime)"
    }
}

// MARK: - Calendar Item (unified wrapper)
enum CalendarItem: Identifiable {
    case sports(SportsEvent)
    case school(SchoolEvent)

    var id: String {
        switch self {
        case .sports(let e): return e.id
        case .school(let e): return e.id
        }
    }

    var date: Date {
        switch self {
        case .sports(let e): return e.date
        case .school(let e): return e.date
        }
    }

    var category: String {
        switch self {
        case .sports(let e): return e.sportName
        case .school: return "School Events"
        }
    }
}

// MARK: - Sports Event Row
struct SportsEventRow: View {
    let event: SportsEvent
    let score: GameScore?
    var mySignups: [ScoreboardSignup] = []

    var oakwoodScore: Int { score.map { event.isAway ? $0.awayScore : $0.homeScore } ?? 0 }
    var opponentScore: Int { score.map { event.isAway ? $0.homeScore : $0.awayScore } ?? 0 }
    var scoreColor: Color { oakwoodScore > opponentScore ? .green : (oakwoodScore == opponentScore ? .secondary : .red) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Badge(text: event.sportName, color: .blue)
                if !event.teamName.isEmpty {
                    Badge(text: event.teamName, color: .purple)
                }
                Spacer()
                Badge(text: event.isAway ? "Away" : "Home", color: event.isAway ? .orange : .green)
            }
            HStack {
                Text(event.opponent).fontWeight(.semibold)
                Spacer()
                if score != nil {
                    Text("\(oakwoodScore) - \(opponentScore)")
                        .font(.headline).fontWeight(.bold).foregroundColor(scoreColor)
                }
            }
            Label(event.timeText, systemImage: "clock").font(.caption).foregroundColor(.secondary)
            if !event.location.isEmpty {
                HStack(spacing: 4) {
                    Label(event.location, systemImage: "mappin.circle").font(.caption).foregroundColor(.secondary)
                    if let job = mySignups.first?.job {
                        Text("· Working: \(job)")
                            .font(.caption2)
                            .foregroundColor(.indigo)
                    }
                }
            } else if let job = mySignups.first?.job {
                Text("Working: \(job)")
                    .font(.caption2)
                    .foregroundColor(.indigo)
            }
            if event.isCancelled {
                Badge(text: "Cancelled", color: .red)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - School Event Row
struct SchoolEventRow: View {
    let event: SchoolEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Badge(text: "School Event", color: .teal)
                Spacer()
            }
            Text(event.title).fontWeight(.semibold)
            Label(event.timeText, systemImage: "clock").font(.caption).foregroundColor(.secondary)
            if !event.location.isEmpty {
                Label(event.location, systemImage: "mappin.circle").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - School Event Detail View
struct SchoolEventDetailView: View {
    let event: SchoolEvent

    var body: some View {
        List {
            Section {
                Badge(text: "School Event", color: .teal)
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.title).font(.title2).fontWeight(.bold)
                    Label(event.date.formatted(date: .complete, time: .omitted), systemImage: "calendar").foregroundColor(.secondary)
                    Label(event.timeText, systemImage: "clock").foregroundColor(.secondary)
                    if !event.location.isEmpty {
                        Label(event.location, systemImage: "mappin.circle").foregroundColor(.secondary)
                    }
                }
            }
            if !event.description.isEmpty {
                Section("Details") {
                    Text(event.description)
                }
            }
        }
        .navigationTitle("Event Details")
        .inlineNavigationBarTitle()
    }
}

// MARK: - Game Detail View
struct GameDetailView: View {
    let event: SportsEvent
    @EnvironmentObject var appInfo: AppInfo

    @State private var gameScore: GameScore?
    @State private var signups: [ScoreboardSignup] = []
    @State private var isLoading = true
    @State private var showScoreSheet = false
    @State private var homeScoreInput = ""
    @State private var awayScoreInput = ""
    @State private var errorMessage: String?

    var isSignedIn: Bool { !appInfo.googleVM.userEmail.isEmpty }
    var userEmail: String { appInfo.googleVM.userEmail }
    var userName: String { appInfo.googleVM.userName }
    var jobs: [JobDefinition] { jobsForSport(event.sportName) }
    var isPastGame: Bool { event.date < Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        List {
            Section {
                HStack {
                    Badge(text: event.sportName, color: .blue)
                    if !event.teamName.isEmpty {
                        Badge(text: event.teamName, color: .purple)
                    }
                    Spacer()
                    Badge(text: event.isAway ? "Away" : "Home", color: event.isAway ? .orange : .green)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.opponent).font(.title2).fontWeight(.bold)
                    Label(event.date.formatted(date: .complete, time: .omitted), systemImage: "calendar").foregroundColor(.secondary)
                    Label(event.timeText, systemImage: "clock").foregroundColor(.secondary)
                    if !event.location.isEmpty {
                        Label(event.location, systemImage: "mappin.circle").foregroundColor(.secondary)
                    }
                }
            }

            Section("Score") {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let score = gameScore {
                    scoreDisplay(score)
                    if isSignedIn {
                        Button("Update Score") {
                            homeScoreInput = "\(score.homeScore)"
                            awayScoreInput = "\(score.awayScore)"
                            showScoreSheet = true
                        }
                    }
                } else {
                    Text("No score reported yet").foregroundColor(.secondary)
                    if isSignedIn {
                        Button("Report Score") { showScoreSheet = true }
                    } else {
                        Text("Sign in to report scores").font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            if !event.isAway && !jobs.isEmpty {
                Section("Scoreboard Jobs") {
                    ForEach(jobs, id: \.name) { job in
                        ForEach(0..<job.slots, id: \.self) { slot in
                            jobSlotRow(job: job, slot: slot)
                        }
                    }
                    if isPastGame {
                        Text("Signups closed for past games").font(.caption).foregroundColor(.secondary)
                    } else if !isSignedIn {
                        Text("Sign in to sign up for jobs").font(.caption).foregroundColor(.secondary)
                    }
                    if let error = errorMessage { Text(error).font(.caption).foregroundColor(.red) }
                }
            }
        }
        .navigationTitle("Game Details")
        .inlineNavigationBarTitle()
        .onAppear { Task { await loadData() } }
        .sheet(isPresented: $showScoreSheet) { scoreSheet }
    }

    @ViewBuilder
    func scoreDisplay(_ score: GameScore) -> some View {
        let (leftTeam, leftScore, rightTeam, rightScore) = event.isAway
            ? (event.opponent, score.awayScore, "Oakwood", score.homeScore)
            : ("Oakwood", score.homeScore, event.opponent, score.awayScore)

        VStack(spacing: 12) {
            HStack {
                VStack {
                    Text(leftTeam).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    Text("\(leftScore)").font(.largeTitle).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                Text("-").font(.title).foregroundColor(.secondary)
                VStack {
                    Text(rightTeam).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    Text("\(rightScore)").font(.largeTitle).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
            }
            Text("Reported by \(score.submittedByName)").font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    func jobSlotRow(job: JobDefinition, slot: Int) -> some View {
        let displayName = job.slots > 1 ? "\(job.name) \(slot + 1)" : job.name
        let signup = signups.first { $0.job == job.name && $0.slot == slot }

        HStack {
            Text(displayName)
            Spacer()
            if let signup = signup {
                if signup.userEmail == userEmail {
                    Text("You").foregroundColor(.green)
                    if !isPastGame {
                        Button("Cancel") { cancelSignup(signup) }.foregroundColor(.red).buttonStyle(.borderless)
                    }
                } else {
                    Text(signup.userName).foregroundColor(.secondary)
                }
            } else if isPastGame {
                Text("Unfilled").foregroundColor(.secondary)
            } else if isSignedIn {
                Button("Sign Up") { signUp(job: job.name, slot: slot) }.buttonStyle(.borderedProminent).controlSize(.small)
            } else {
                Text("Available").foregroundColor(.secondary)
            }
        }
    }

    var scoreSheet: some View {
        NavigationStack {
            Form {
                Section("Oakwood") {
                    TextField("Score", text: event.isAway ? $awayScoreInput : $homeScoreInput)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                Section(event.opponent) {
                    TextField("Score", text: event.isAway ? $homeScoreInput : $awayScoreInput)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            }
            .navigationTitle("Report Score")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showScoreSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await submitScore() } }
                        .disabled(homeScoreInput.isEmpty || awayScoreInput.isEmpty)
                }
            }
        }
    }

    func loadData() async {
        async let scoreTask: () = loadScore()
        async let signupsTask: () = loadSignups()
        await scoreTask; await signupsTask
        await MainActor.run { isLoading = false }
    }

    func loadScore() async {
        gameScore = try? await FirebaseService.shared.fetchGameScore(eventId: event.id)
    }

    func loadSignups() async {
        signups = (try? await FirebaseService.shared.fetchSignups(eventId: event.id)) ?? []
    }

    func submitScore() async {
        guard let home = Int(homeScoreInput), let away = Int(awayScoreInput) else { return }
        try? await FirebaseService.shared.submitGameScore(eventId: event.id, homeScore: home, awayScore: away, userEmail: userEmail, userName: userName)
        await loadScore()
        await MainActor.run { showScoreSheet = false }
    }

    func signUp(job: String, slot: Int) {
        let desc = "\(event.sportName) - \(event.teamName) vs \(event.opponent)"
        Task {
            do {
                try await FirebaseService.shared.signUpForJob(eventId: event.id, job: job, slot: slot, userEmail: userEmail, userName: userName, eventDate: event.date, eventDescription: desc)
                await loadSignups()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelSignup(_ signup: ScoreboardSignup) {
        Task {
            try? await FirebaseService.shared.cancelSignup(signupId: signup.id)
            await loadSignups()
        }
    }
}

// MARK: - Calendar Filter View
struct CalendarFilterView: View {
    let allCategories: [String]
    @Binding var selectedCategories: Set<String>
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Show All") { selectedCategories.removeAll() }.foregroundColor(.blue)
                }
                Section("Filter Events") {
                    ForEach(allCategories, id: \.self) { category in
                        Button {
                            if selectedCategories.contains(category) { selectedCategories.remove(category) }
                            else { selectedCategories.insert(category) }
                        } label: {
                            HStack {
                                Text(category).foregroundColor(.primary)
                                Spacer()
                                if selectedCategories.contains(category) {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter Events")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Calendar View
struct CalendarView: View {
    @EnvironmentObject var appInfo: AppInfo
    @State private var selectedTab = 0
    @State private var showingFilter = false
    @State private var selectedCategories: Set<String> = {
        guard let data = UserDefaults.standard.data(forKey: "selectedCategories"),
              let cats = try? JSONDecoder().decode(Set<String>.self, from: data) else { return [] }
        return cats
    }()

    var allCategories: [String] {
        Array(Set(appInfo.calendarItems.map { $0.category })).sorted()
    }

    var filteredItems: [CalendarItem] {
        let today = Calendar.current.startOfDay(for: Date())
        var filtered = selectedCategories.isEmpty ? appInfo.calendarItems : appInfo.calendarItems.filter { selectedCategories.contains($0.category) }
        filtered = selectedTab == 0 ? filtered.filter { $0.date >= today } : filtered.filter { $0.date < today }
        return filtered
    }

    var groupedItems: [(String, [CalendarItem])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        let grouped = Dictionary(grouping: filteredItems) { formatter.string(from: $0.date) }
        let sorted = grouped.sorted { ($0.value.first?.date ?? .distantPast) < ($1.value.first?.date ?? .distantPast) }
        return selectedTab == 1 ? sorted.reversed() : sorted
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    Text("Upcoming").tag(0)
                    Text("Past").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if appInfo.calendarIsLoading {
                    Spacer(); ProgressView("Loading events..."); Spacer()
                } else if filteredItems.isEmpty {
                    Spacer(); Text(selectedTab == 0 ? "No upcoming events" : "No past events").foregroundColor(.secondary); Spacer()
                } else {
                    List {
                        ForEach(groupedItems, id: \.0) { date, items in
                            Section(date) {
                                ForEach(items) { item in
                                    switch item {
                                    case .sports(let event):
                                        NavigationLink(destination: GameDetailView(event: event)) {
                                            SportsEventRow(event: event, score: appInfo.calendarScores[event.id], mySignups: appInfo.calendarMySignups[event.id] ?? [])
                                        }
                                    case .school(let event):
                                        NavigationLink(destination: SchoolEventDetailView(event: event)) {
                                            SchoolEventRow(event: event)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Calendar")
            .macInsetListStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showingFilter = true } label: {
                        Image(systemName: selectedCategories.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await appInfo.loadAllCalendarEvents() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingFilter) {
                CalendarFilterView(allCategories: allCategories, selectedCategories: $selectedCategories)
            }
            .onChange(of: selectedCategories) { _, _ in
                if let data = try? JSONEncoder().encode(selectedCategories) {
                    UserDefaults.standard.set(data, forKey: "selectedCategories")
                }
            }
        }
        .onAppear {
            if appInfo.calendarItems.isEmpty { Task { await appInfo.loadAllCalendarEvents() } }
            else { Task { await appInfo.refreshCalendarData() } }
        }
    }
}
