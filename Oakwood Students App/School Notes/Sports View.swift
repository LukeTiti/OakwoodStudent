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

// MARK: - Sports Event Row
struct SportsEventRow: View {
    let event: SportsEvent
    let score: GameScore?

    var oakwoodScore: Int { score.map { event.isAway ? $0.awayScore : $0.homeScore } ?? 0 }
    var opponentScore: Int { score.map { event.isAway ? $0.homeScore : $0.awayScore } ?? 0 }
    var scoreColor: Color { oakwoodScore > opponentScore ? .green : (oakwoodScore == opponentScore ? .secondary : .red) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Badge(text: event.sportName, color: .blue)
                Badge(text: event.teamName, color: .purple)
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
                Label(event.location, systemImage: "mappin.circle").font(.caption).foregroundColor(.secondary)
            }
            if event.isCancelled {
                Badge(text: "Cancelled", color: .red)
            }
        }
        .padding(.vertical, 4)
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
                    Badge(text: event.teamName, color: .purple)
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
        .navigationBarTitleDisplayMode(.inline)
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
                    TextField("Score", text: event.isAway ? $awayScoreInput : $homeScoreInput).keyboardType(.numberPad)
                }
                Section(event.opponent) {
                    TextField("Score", text: event.isAway ? $homeScoreInput : $awayScoreInput).keyboardType(.numberPad)
                }
            }
            .navigationTitle("Report Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { showScoreSheet = false } }
                ToolbarItem(placement: .navigationBarTrailing) {
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

// MARK: - Sport Filter View
struct SportFilterView: View {
    let allSports: [String]
    @Binding var selectedSports: Set<String>
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Show All Sports") { selectedSports.removeAll() }.foregroundColor(.blue)
                }
                Section("Select Sports") {
                    ForEach(allSports, id: \.self) { sport in
                        Button {
                            if selectedSports.contains(sport) { selectedSports.remove(sport) }
                            else { selectedSports.insert(sport) }
                        } label: {
                            HStack {
                                Text(sport).foregroundColor(.primary)
                                Spacer()
                                if selectedSports.contains(sport) {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter Sports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Sports View
struct SportsView: View {
    @State private var events: [SportsEvent] = []
    @State private var scores: [String: GameScore] = [:]
    @State private var isLoading = true
    @State private var selectedTab = 0
    @State private var showingSportFilter = false
    @State private var selectedSports: Set<String> = {
        guard let data = UserDefaults.standard.data(forKey: "selectedSports"),
              let sports = try? JSONDecoder().decode(Set<String>.self, from: data) else { return [] }
        return sports
    }()

    var allSports: [String] { Array(Set(events.map { $0.sportName })).sorted() }

    var filteredEvents: [SportsEvent] {
        let today = Calendar.current.startOfDay(for: Date())
        var filtered = selectedSports.isEmpty ? events : events.filter { selectedSports.contains($0.sportName) }
        filtered = selectedTab == 0 ? filtered.filter { $0.date >= today } : filtered.filter { $0.date < today }
        return filtered
    }

    var groupedEvents: [(String, [SportsEvent])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        let grouped = Dictionary(grouping: filteredEvents) { formatter.string(from: $0.date) }
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

                if isLoading {
                    Spacer(); ProgressView("Loading events..."); Spacer()
                } else if filteredEvents.isEmpty {
                    Spacer(); Text(selectedTab == 0 ? "No upcoming events" : "No past events").foregroundColor(.secondary); Spacer()
                } else {
                    List {
                        ForEach(groupedEvents, id: \.0) { date, events in
                            Section(date) {
                                ForEach(events) { event in
                                    NavigationLink(destination: GameDetailView(event: event)) {
                                        SportsEventRow(event: event, score: scores[event.id])
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sports")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingSportFilter = true } label: {
                        Image(systemName: selectedSports.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { isLoading = true; await loadEvents() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(isPresented: $showingSportFilter) {
                SportFilterView(allSports: allSports, selectedSports: $selectedSports)
            }
            .onChange(of: selectedSports) { _, _ in
                if let data = try? JSONEncoder().encode(selectedSports) {
                    UserDefaults.standard.set(data, forKey: "selectedSports")
                }
            }
        }
        .onAppear {
            if events.isEmpty { Task { await loadEvents() } }
            else { Task { await refreshScores() } }
        }
    }

    func loadEvents() async {
        var allEvents: [SportsEvent] = []
        await withTaskGroup(of: [SportsEvent].self) { group in
            for calendar in teamCalendars {
                group.addTask { await fetchEvents(from: calendar) }
            }
            for await events in group { allEvents.append(contentsOf: events) }
        }

        var seen = Set<String>()
        let unique = allEvents.filter { seen.insert($0.id).inserted }.sorted { $0.date < $1.date }
        let fetchedScores = (try? await FirebaseService.shared.fetchAllGameScores()) ?? [:]

        await MainActor.run {
            events = unique
            scores = fetchedScores
            isLoading = false
        }
    }

    func refreshScores() async {
        scores = (try? await FirebaseService.shared.fetchAllGameScores()) ?? [:]
    }

    func fetchEvents(from calendar: TeamCalendar) async -> [SportsEvent] {
        guard let url = URL(string: calendar.url),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let ics = String(data: data, encoding: .utf8) else { return [] }
        return parseICalEvents(ics, calendar: calendar)
    }

    func parseICalEvents(_ ics: String, calendar: TeamCalendar) -> [SportsEvent] {
        // Unfold iCal lines
        let unfolded = ics
            .replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")

        var events: [SportsEvent] = []
        var current: [String: String] = [:]
        var inEvent = false

        for line in unfolded.components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if l == "BEGIN:VEVENT" { inEvent = true; current = [:] }
            else if l == "END:VEVENT" {
                if let event = createEvent(from: current, calendar: calendar) { events.append(event) }
                inEvent = false
            } else if inEvent, let idx = l.firstIndex(of: ":") {
                let key = String(l[..<idx]).components(separatedBy: ";").first ?? ""
                current[key] = String(l[l.index(after: idx)...])
            }
        }
        return events
    }

    func createEvent(from data: [String: String], calendar: TeamCalendar) -> SportsEvent? {
        guard let uid = data["UID"], let summary = data["SUMMARY"], let dtstart = data["DTSTART"] else { return nil }

        let date = parseDate(dtstart)
        let endDate = data["DTEND"].flatMap { parseDate($0) }
        let location = data["LOCATION"]?.replacingOccurrences(of: "\\,", with: ",") ?? ""

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        let isCancelled = summary.contains("CANCELLED") || data["STATUS"] == "CANCELLED"
        let isAway = summary.contains("(Away)") ? true : (summary.contains("(Home)") || location.lowercased().contains("oakwood")) ? false : true

        var teamName = calendar.name
            .replacingOccurrences(of: " \(calendar.sport)", with: "")
            .replacingOccurrences(of: calendar.sport, with: "")
            .trimmingCharacters(in: .whitespaces)

        return SportsEvent(
            id: uid, title: summary, date: date,
            startTime: timeFormatter.string(from: date),
            endTime: endDate.map { timeFormatter.string(from: $0) } ?? "",
            location: location, isAway: isAway, isCancelled: isCancelled,
            sportName: calendar.sport, teamName: teamName
        )
    }

    func parseDate(_ str: String) -> Date {
        let formats = [("yyyyMMdd'T'HHmmss'Z'", TimeZone(identifier: "UTC")), ("yyyyMMdd'T'HHmmss", nil), ("yyyyMMdd", nil)]
        for (format, tz) in formats {
            let f = DateFormatter()
            f.dateFormat = format
            if let tz = tz { f.timeZone = tz }
            if let d = f.date(from: str) { return d }
        }
        return Date()
    }
}
