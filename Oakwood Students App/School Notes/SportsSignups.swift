//
//  SportsSignups.swift
//  School Notes
//
//  Home volleyball/basketball game jobs (scoreboard, line judge, etc.) — governed entirely by
//  a Google Sheet an AD edits directly, not Firestore. See google-apps-script/sports-signups.gs
//  for the backend (an Apps Script Web App bound to the sheet, not a Firebase Cloud Function —
//  deliberately avoids needing the Blaze plan or managing a service account key at all).
//

import Foundation

// NOTE: this is Luke's personal test sheet, not yet shared with the ADs. Swap this URL once the
// real AD-managed sheet has its own Apps Script deployment — everything else stays the same.
private let sportsSignupSheetURL = "https://script.google.com/macros/s/AKfycbwALb1hRHZ5uMuwfXxc7mMQPoxItjWWPOq3jYTZi4VrrlIgFcTHMd1HrtV1S8srzQdbJw/exec"

struct GameJobSlot: Identifiable {
    var id: String { name }
    var name: String
    var filledBy: String
    var isOpen: Bool { filledBy.isEmpty }
}

struct GameJobSignups: Identifiable {
    var id: String { "\(gameTime.timeIntervalSince1970)-\(opponent)" }
    var gameTime: Date
    var team: String
    var opponent: String
    var jobs: [GameJobSlot]
}

enum SportsSignupError: Error, CustomLocalizedStringResourceConvertible {
    case server(String)
    case malformedResponse

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .server(let message): return "\(message)"
        case .malformedResponse: return "Couldn't read the signup sheet's response."
        }
    }
}

enum SportsSignupService {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func fetchSignups() async throws -> [GameJobSignups] {
        guard let url = URL(string: sportsSignupSheetURL) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(SignupsResponse.self, from: data)
        return decoded.games.compactMap { raw in
            guard let date = isoFormatter.date(from: raw.gameTime) else { return nil }
            return GameJobSignups(
                gameTime: date, team: raw.team, opponent: raw.opponent,
                jobs: raw.jobs.map { GameJobSlot(name: $0.name, filledBy: $0.filledBy) }
            )
        }
    }

    /// Signs up for (or cancels) one job on one game. `name` is always the acting student's own
    /// name — the sheet script refuses a cancel where the cell's current value doesn't match it,
    /// so one student can't clear someone else's signup.
    static func setJob(game: GameJobSignups, job: String, name: String, action: String) async throws {
        guard let url = URL(string: sportsSignupSheetURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "gameTime": isoFormatter.string(from: game.gameTime),
            "team": game.team,
            "opponent": game.opponent,
            "job": job,
            "name": name,
            "action": action
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode(SignupActionResult.self, from: data)
        if !result.ok {
            throw SportsSignupError.server(result.error ?? "That didn't work. Try refreshing.")
        }
    }

    private struct SignupsResponse: Decodable {
        struct RawGame: Decodable {
            struct RawJob: Decodable { var name: String; var filledBy: String }
            var gameTime: String
            var team: String
            var opponent: String
            var jobs: [RawJob]
        }
        var games: [RawGame]
    }

    private struct SignupActionResult: Decodable {
        var ok: Bool
        var error: String?
    }
}

/// Matches a scraped SportsEvent (from the GitHub sports schedule) to its job-signup row from
/// the sheet, by exact time (within a minute, to tolerate rounding) and a loose, bidirectional
/// opponent-name match — same fuzzy-matching convention as GradeStore.classTime. Team name
/// ("Oakwood JV" etc.) isn't used as a match key since the sheet's format for it isn't
/// guaranteed to match SportsEvent.teamName's own format; time + opponent alone is already
/// specific enough in practice (two different games don't start at the same minute).
func matchingSignups(for event: SportsEvent, in signups: [GameJobSignups]) -> GameJobSignups? {
    signups.first { signup in
        abs(signup.gameTime.timeIntervalSince(event.date)) < 60 &&
        (signup.opponent.localizedCaseInsensitiveContains(event.opponent) ||
         event.opponent.localizedCaseInsensitiveContains(signup.opponent))
    }
}

/// The job name the current user is signed up for on this event, if any — used for the
/// "Working: X" badge on sports list rows. nil whenever there's no match or no signed-in user.
func myJobName(for event: SportsEvent, in signups: [GameJobSignups], userName: String) -> String? {
    guard !userName.isEmpty, let match = matchingSignups(for: event, in: signups) else { return nil }
    return match.jobs.first { $0.filledBy == userName }?.name
}
