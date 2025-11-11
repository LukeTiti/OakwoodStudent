//
//  Sports View.swift
//  School Notes
//
//  Created by Luke Titi on 10/5/25.
//
import SwiftUI
import SwiftSoup

struct Game: Codable, Identifiable {
    var sport: Int
    var home: Bool
    var team: String
    var opponent: String
    var time: String
    var date: String
    var completed: Bool
    var active: Bool
    var setsWon: Int
    var setsLost: Int
    var scores: [Sets]
    var articles: [Article]
    
    
    var id: String { "\(sport)-\(home)-\(team)-\(opponent)-\(time)" }
}
struct Sets: Codable, Identifiable {
    var set: Int
    var teamScore: Int
    var oppScore: Int
    
    var id: String { "\(set)-\(teamScore)-\(oppScore)" }
}

struct Article: Codable, Identifiable {
    var author: String
    var title: String
    var date: String
    var content: String
    
    var id: String { content }
}

struct GameResponse: Codable {
    let games: [Game]
}
struct SportsView: View {
    @State var games: [Game] = []
    @State var errorMessage = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(games) { game in
                    NavigationLink(destination: GameDetailView(game: game)) {
                        VStack {
                            HStack {
                                Text("\(game.team) \(game.sport == 1 ? "Volleyball" : "Basketball")")
                                    .font(.caption)
                                Text("\(game.date)")
                                    .font(.caption)
                            }
                            HStack {
                                Text("Oakwood")
                                Spacer()
                                Text("\(game.time) PM")
                                Spacer()
                                Text("\(game.opponent)")
                            }
                            .padding(.horizontal)
                            HStack {
                                if game.completed {
                                    Spacer()
                                    Text("\(game.setsWon)")
                                        .font(.title)
                                    Spacer()
                                    VStack {
                                        Text("Home")
                                        Text("Away")
                                    }
                                    ForEach(game.scores) { score in
                                        VStack {
                                            if score.teamScore > score.oppScore {
                                                Text("\(score.teamScore)")
                                                    .bold()
                                                    .foregroundStyle(Color.blue)
                                                Text("\(score.oppScore)")
                                            } else {
                                                Text("\(score.teamScore)")
                                                Text("\(score.oppScore)")
                                                    .bold()
                                                    .foregroundStyle(Color.blue)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Text("\(game.setsLost)")
                                        .font(.title)
                                    Spacer()
                                }
                            }
                        }
                    }
                    
                }
            }
            .navigationTitle("Sports")
        }
        Text(errorMessage)
            .onAppear() {
                Task {
                    await loadGames()
                }
            }
    }
    func loadGames() async {
        guard let url = URL(string: "https://raw.githubusercontent.com/LukeTiti/OakwoodStudent/refs/heads/Sport-Data-Branch/SportData") else {
            await MainActor.run {
                errorMessage = "Invalid URL"
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = true
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            
            guard status == 200 else {
                await MainActor.run {
                    errorMessage = "Server returned status \(status)"
                }
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode([Game].self, from: data)
                await MainActor.run {
                    self.games = decoded
                }
            } catch {
                let textPreview = String(data: data, encoding: .utf8) ?? "Unable to decode"
                await MainActor.run {
                    errorMessage = "Decoding error: \(error.localizedDescription)\nPreview: \(textPreview.prefix(200))"
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Network error: \(error.localizedDescription)"
            }
        }
    }
    private func isJSONResponse(_ response: URLResponse?, data: Data) -> Bool {
        if let http = response as? HTTPURLResponse,
           let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           contentType.contains("application/json") {
            return true
        }
        // Fallback sniffing
        if let prefix = String(data: data.prefix(1), encoding: .utf8) {
            return prefix == "{" || prefix == "["
        }
        return false
    }
}


struct GameDetailView: View {
    let game: Game
    var body: some View {
        // TODO: add stats to this page
        NavigationStack {
            List {
                ForEach(game.articles) { article in
                    NavigationLink(destination: ArticleView(article: article)){
                        HStack {
                            Text("\(article.author)")
                            Text("\(article.date)")
                        }
                    }
                }
            }
            .navigationTitle("Articles")
        }
    }
}


struct ArticleView: View {
    @State var article: Article?
    var body: some View {
        ScrollView {
            Text(.init(article?.content ?? "No Content"))
        }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(article?.title ?? "")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(article?.author ?? "")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
    }
}
