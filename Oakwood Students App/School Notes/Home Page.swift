//
//  Home Page.swift
//  School Notes
//
//  Created by Luke Titi on 9/7/25.
//
import SwiftUI
import SwiftSoup
import Combine
import WebKit

struct ScoopItem: Identifiable {
    let id = UUID()
    let title: String
    let date: String
    let link: String
    var image: String
}

// Decodes items inside the HTML data-image-sizes attribute
// Example element: { "url": "https://...", "width": 640 }
private struct ImageSizeEntry: Decodable {
    let url: String
    let width: Int?
}

class ScoopViewModel: ObservableObject {
    @Published var items: [ScoopItem] = []
    
    func fetchScoop(tag: String) {
        guard let url = URL(string: "https://www.oakwoodway.org/inside-scoop?tag_id=\(tag)") else { return }
        
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
                    
                    // Extract image URL from data-image-sizes JSON (HTML-entity encoded)
                    let imageURL: String = {
                        guard let div = div else { return "" }
                        let raw = (try? div.attr("data-image-sizes")) ?? ""
                        guard !raw.isEmpty else { return "" }
                        
                        // Unescape HTML entities: &quot; -> "
                        let unescaped = raw.replacingOccurrences(of: "&quot;", with: "\"")
                        
                        // Decode JSON array of { "url": "...", "width": N }
                        if let data = unescaped.data(using: .utf8),
                           let entries = try? JSONDecoder().decode([ImageSizeEntry].self, from: data) {
                            // Prefer the largest width image; fallback to first entry
                            let best = entries.max(by: { ($0.width ?? 0) < ($1.width ?? 0) }) ?? entries.first
                            return best?.url ?? ""
                        }
                        // As a fallback, try to find an https URL after the marker :&quot;
                        let marker = ":&quot;"
                        if let markerRange = raw.range(of: marker),
                           let httpsRange = raw.range(of: "https:"),
                           httpsRange.lowerBound > markerRange.upperBound {
                            // Try to extract a URL-like token from the unescaped string
                            // Find the next quote after https to bound the URL
                            let start = unescaped.range(of: "https:", range: unescaped.index(after: unescaped.startIndex)..<unescaped.endIndex)?.lowerBound
                            if let s = start {
                                // URL likely ends at the next " character
                                let tail = unescaped[s...]
                                if let endQuote = tail.firstIndex(of: "\"") {
                                    return String(tail[..<endQuote])
                                } else {
                                    return String(tail)
                                }
                            }
                        }
                        return ""
                    }()
                    
                    let item = ScoopItem(
                        title: title,
                        date: "", // Date not available in this snippet
                        link: link.starts(with: "http") ? link : "https://www.oakwoodway.org\(link)",
                        image: imageURL
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
    // Use a valid default that matches a Picker tag. "" can represent "All".
    @State private var tag: String = ""
    
    var body: some View {
        NavigationStack {
            List(viewModel.items) { item in
                NavigationLink(destination: EventView(events: item)) {
                    HStack() {
                        AsyncImage(url: URL(string: item.image)) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            ProgressView() // spinner while loading
                        }
                            .frame(width: 100, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(item.title)
                            .font(.headline)
                        if !item.date.isEmpty {
                            Text(item.date)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Inside Scoop")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Picker("", selection: $tag) {
                        Text("All School").tag("")        // no tag filter
                        Text("Lower School").tag("174")   // Lower School
                        Text("Middle School").tag("175")  // Middle School
                        Text("High School").tag("176")
                    }
                    .pickerStyle(.menu)
                    .frame(width: tag == "" ? 110 : tag == "176" ? 125 : 140) // keep it tight; width is mostly from label
                }
            }
            .onChange(of: tag) { newValue in
                // Refetch whenever the filter changes
                viewModel.fetchScoop(tag: newValue)
            }
            .onAppear {
                // Initial load (matches default tag "")
                viewModel.fetchScoop(tag: tag)
            }
        }
    }
}


struct EventView: View {
    @State var events: ScoopItem?
    var body: some View {
        WebView(url: URL(string: events?.link ?? "")!)
            .navigationTitle(events?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
    }
}

