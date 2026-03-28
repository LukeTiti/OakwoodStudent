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

// MARK: - Image Cache

private class ImageDataCache {
    static let shared = ImageDataCache()
    private let cache = NSCache<NSString, NSData>()
    func data(for url: String) -> Data? { cache.object(forKey: url as NSString) as Data? }
    func store(_ data: Data, for url: String) { cache.setObject(data as NSData, forKey: url as NSString) }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var imageData: Data?

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
        if let url = url, let cached = ImageDataCache.shared.data(for: url.absoluteString) {
            _imageData = State(initialValue: cached)
        }
    }

    var body: some View {
        Group {
            if let data = imageData, let image = makeImage(from: data) {
                content(image)
            } else {
                placeholder()
                    .task { await load() }
            }
        }
    }

    private func makeImage(from data: Data) -> Image? {
        #if os(iOS)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #else
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #endif
    }

    private func load() async {
        guard let url = url else { return }
        let key = url.absoluteString
        if let cached = ImageDataCache.shared.data(for: key) {
            imageData = cached; return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        ImageDataCache.shared.store(data, for: key)
        await MainActor.run { imageData = data }
    }
}

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

// MARK: - Banner View

struct BannerView: View {
    let banner: AppBanner
    let onDismiss: () -> Void

    var bannerColor: Color {
        switch banner.type {
        case "warning": return .orange
        case "urgent":  return .red
        default:        return .blue
        }
    }

    var bannerIcon: String {
        switch banner.type {
        case "warning": return "exclamationmark.triangle.fill"
        case "urgent":  return "exclamationmark.circle.fill"
        default:        return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: bannerIcon)
                .foregroundColor(.white)
                .font(.footnote.weight(.semibold))
                .frame(width: 22, height: 22)
                .background(bannerColor)
                .clipShape(Circle())
            Text(banner.message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(bannerColor.opacity(0.4), lineWidth: 1.5))
        .shadow(color: bannerColor.opacity(0.15), radius: 6, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

struct ScoopRow: View {
    let item: ScoopItem
    var showBadge: Bool = false

    var body: some View {
        HStack {
            CachedAsyncImage(url: URL(string: item.image)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                if showBadge {
                    Text("Happening Today")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct HomeView: View {
    @StateObject private var viewModel = ScoopViewModel()
    @State private var tag: String = ""
    @State private var banners: [AppBanner] = []
    @State private var dismissedBanners: Set<String> = []

    /// The most recent Wednesday at 5 PM — when the Inside Scoop publishes each week.
    /// "Today" and "tomorrow" in article titles are relative to this date, not the current date.
    private var articlePublicationDate: Date {
        let calendar = Calendar.current
        let now = Date()
        // weekday: Sun=1, Mon=2, Tue=3, Wed=4, Thu=5, Fri=6, Sat=7
        let daysSinceWed = (calendar.component(.weekday, from: now) - 4 + 7) % 7
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.day! -= daysSinceWed
        comps.hour = 17; comps.minute = 0; comps.second = 0
        let thisWednesday = calendar.date(from: comps)!
        // If we haven't hit 5 PM Wednesday yet this week, use the previous Wednesday
        return now >= thisWednesday ? thisWednesday : calendar.date(byAdding: .weekOfYear, value: -1, to: thisWednesday)!
    }

    /// Replaces relative words "today"/"tomorrow" with explicit dates anchored to the publication Wednesday.
    private func resolveRelativeDates(in title: String) -> String {
        let ref = articlePublicationDate
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        let todayStr = formatter.string(from: ref)
        let tomorrowStr = formatter.string(from: Calendar.current.date(byAdding: .day, value: 1, to: ref)!)
        return title
            .replacingOccurrences(of: "today", with: todayStr, options: .caseInsensitive)
            .replacingOccurrences(of: "tonight", with: todayStr, options: .caseInsensitive)
            .replacingOccurrences(of: "tomorrow", with: tomorrowStr, options: .caseInsensitive)
    }

    private func hasTodayDate(in title: String) -> Bool {
        let resolved = resolveRelativeDates(in: title)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return false }
        let matches = detector.matches(in: resolved, range: NSRange(resolved.startIndex..., in: resolved))
        let now = Date()
        return matches.contains { match in
            guard let start = match.date else { return false }
            if match.duration > 0 {
                let startOfToday = Calendar.current.startOfDay(for: now)
                let startOfEvent = Calendar.current.startOfDay(for: start)
                return startOfToday >= startOfEvent && now <= start.addingTimeInterval(match.duration)
            }
            return Calendar.current.isDateInToday(start)
        }
    }

    private var todayItems: [ScoopItem] { viewModel.items.filter { hasTodayDate(in: $0.title) } }
    private var otherItems: [ScoopItem] { viewModel.items.filter { !hasTodayDate(in: $0.title) } }

    @ToolbarContentBuilder
    var scoopToolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Picker("", selection: $tag) {
                Text("All School").tag("")
                Text("Lower School").tag("174")
                Text("Middle School").tag("175")
                Text("High School").tag("176")
            }
            .pickerStyle(.menu)
            .frame(width: tag == "" ? 110 : tag == "176" ? 125 : 140)
        }
    }

    @ViewBuilder
    var bannerOverlay: some View {
        let visible = banners.filter { !dismissedBanners.contains($0.message) }
        if !visible.isEmpty {
            VStack(spacing: 0) {
                ForEach(visible, id: \.message) { banner in
                    BannerView(banner: banner) { dismissedBanners.insert(banner.message) }
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            #if os(macOS)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 350), spacing: 16)], spacing: 16) {
                    ForEach(viewModel.items) { item in
                        NavigationLink(destination: EventView(events: item)) {
                            VStack(alignment: .leading, spacing: 0) {
                                CachedAsyncImage(url: URL(string: item.image)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.2))
                                        .overlay(ProgressView())
                                }
                                .frame(height: 160)
                                .clipped()

                                Text(item.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .padding(12)
                            }
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Inside Scoop")
            .toolbar { scoopToolbar }
            .onChange(of: tag) { newValue in viewModel.fetchScoop(tag: newValue) }
            .onAppear {
                viewModel.fetchScoop(tag: tag)
                Task {
                    banners = (try? await FirebaseService.shared.fetchBanners()) ?? []
                    dismissedBanners = []
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { bannerOverlay }
            #else
            List {
                let visible = banners.filter { !dismissedBanners.contains($0.message) }
                if !visible.isEmpty {
                    Section {
                        ForEach(visible, id: \.message) { banner in
                            BannerView(banner: banner) { dismissedBanners.insert(banner.message) }
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }
                ForEach(todayItems + otherItems) { item in
                    NavigationLink(destination: EventView(events: item)) {
                        ScoopRow(item: item, showBadge: hasTodayDate(in: item.title))
                    }
                }
            }
            .navigationTitle("Inside Scoop")
            .toolbar { scoopToolbar }
            .onChange(of: tag) { newValue in viewModel.fetchScoop(tag: newValue) }
            .onAppear {
                viewModel.fetchScoop(tag: tag)
                Task {
                    banners = (try? await FirebaseService.shared.fetchBanners()) ?? []
                    dismissedBanners = []
                }
            }
            #endif
        }
    }
}


struct EventView: View {
    @State var events: ScoopItem?
    var body: some View {
        WebView(url: URL(string: events?.link ?? "")!)
            .navigationTitle(events?.title ?? "")
            .inlineNavigationBarTitle()
    }
}

