//
//  Home Page.swift
//  School Notes
//
//  Created by Luke Titi on 9/7/25.
//
import SwiftUI
import SwiftSoup
import Combine

struct ScoopItem: Identifiable {
    let id = UUID()
    let title: String
    let date: String
    let link: String
}

class ScoopViewModel: ObservableObject {
    @Published var items: [ScoopItem] = []
    
    func fetchScoop() {
        guard let url = URL(string: "https://www.oakwoodway.org/inside-scoop") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Request error:", error)
                return
            }
            
            guard let data = data,
                  let html = String(data: data, encoding: .utf8) else {
                print("Failed to decode HTML")
                return
            }
            
            do {
                let doc: Document = try SwiftSoup.parse(html)
                
                let posts = try doc.select("a.fsThumbnail.fsPostLink")
                var newItems: [ScoopItem] = []
                
                for post in posts {
                    let link = try post.attr("href")
                    
                    let div = try post.select("div.fsCroppedImage").first()
                    let title = try div?.attr("title") ?? "No Title"
                    
                    let item = ScoopItem(
                        title: title,
                        date: "", // Date not available in this snippet
                        link: link.starts(with: "http") ? link : "https://www.oakwoodway.org\(link)"
                    )
                    
                    newItems.append(item)
                }
                
                DispatchQueue.main.async {
                    self.items = newItems
                }
            } catch {
                print("SwiftSoup parse error:", error)
            }
        }.resume()
    }


}

struct HomeView: View {
    @StateObject private var viewModel = ScoopViewModel()
    
    var body: some View {
        NavigationStack {
            List(viewModel.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                    if !item.date.isEmpty {
                        Text(item.date)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Text(item.link)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Inside Scoop")
            .onAppear {
                viewModel.fetchScoop()
            }
        }
    }
}
