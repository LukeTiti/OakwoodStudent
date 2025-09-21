//
//  Class Notes.swift
//  School Notes
//
//  Created by Luke Titi on 9/3/25.
//
import SwiftUI
import SwiftSoup

struct Subject: Identifiable {
    var name: String
    var id = UUID()
    var webName: String
}

struct ClassNotes: View {
    @State var classes: [Subject] = [
        Subject(name: "Precalc", webName: "Precalc%20"),
        Subject(name: "AP EURO", webName: "AP%20Euro%20"),
        Subject(name: "Spanish II", webName: "Spanish%20II%20"),
        Subject(name: "Algebra II", webName: "Algebra%202%20")
    ]
    @EnvironmentObject var appInfo: AppInfo
    @State var loggedInAlert = false
    var body: some View {
        NavigationView {
            List {
                ForEach(classes) { clas in
                    NavigationLink(destination: appInfo.googleVM.isSignedIn && appInfo.approvedEmails.contains(appInfo.googleVM.userEmail) ? AnyView(SubjectView(curentClass: clas)) : AnyView(sorryPage())) {
                        Text(clas.name)
                    }
                }
            }
            .navigationTitle("Subjects")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        appInfo.fetchedString.removeAll()
                        Task {
                            try? await loadWebsite()
                        }
                    }){
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        appInfo.googleVM.signIn()
                    }){
                        if !appInfo.googleVM.isSignedIn {
                            Text("Sign In")
                        } else {
                            Text("\(appInfo.googleVM.userName)")
                        }
                    }
                }
            }
        }
            .onAppear {
                Task {
                    try? await loadWebsite()
                    try? await loadEmails()
                }
            }
    }
    func loadEmails() async {
        guard let url = URL(string: "http://on.aesd.ch/Gmail.html") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let html = String(data: data, encoding: .utf8) {
                let document = try SwiftSoup.parse(html)
                // Get the body element
                let body = try document.body()!
                // Get all nodes in the body
                let nodes = body.getChildNodes()
                appInfo.approvedEmails = [] // clear old data
                for node in nodes {
                    if let textNode = node as? SwiftSoup.TextNode {
                        let trimmed = textNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            appInfo.approvedEmails.append(trimmed)
                        }
                    }
                }
            }
        } catch {
            print("Error loading: \(error)")
        }
    }
    
    func loadWebsite() async {
        guard let url = URL(string: "http://on.aesd.ch/Secret.html") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let html = String(data: data, encoding: .utf8) {
                let document = try SwiftSoup.parse(html)
                // Get the body element
                let body = try document.body()!
                // Get all nodes in the body
                let nodes = body.getChildNodes()
                appInfo.fetchedString = [] // clear old data
                for node in nodes {
                    if let textNode = node as? SwiftSoup.TextNode {
                        let trimmed = textNode.text().trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            appInfo.fetchedString.append(trimmed)
                        }
                    }
                }
            }
        } catch {
            print("Error loading: \(error)")
        }
    }
}

struct SubjectView: View {
    @State var curentClass: Subject?
    @EnvironmentObject var appInfo: AppInfo
    var body: some View {
        List {
            ForEach(appInfo.fetchedString, id: \.self) { string in
                if string.contains(curentClass?.webName ?? "") || (curentClass?.name == "AP EURO" && string.contains("AP%20Euro%20Notes%20")) {
                    let currentSection = (textBetween(text: string, start: curentClass?.webName ?? "", end: "%20") ?? "")
                    NavigationLink(destination: ImageView(url: URL(string: "http://on.aesd.ch/\(string)"), section: string.contains("https") ? "Practice" : currentSection, note: string.contains("https") ? false : true)) {
                        HStack {
                            if currentSection == "Notes" {
                                Text("Class Notes")
                            } else {
                                if string.contains("https") {
                                    Text("Practice")
                                } else {
                                    Text("Section \(currentSection)")
                                }
                            }
                            Spacer()
                            if !string.contains("https") {
                                Text((findCharacters(in: string) ?? ""))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(curentClass?.name ?? "Unknown")
    }
    func findCharacters(in string: String) -> String? {
        guard string.count >= 6 else { return nil }
        let chars = Array(string)
        let sevenToLast = chars[string.count - 7]
        let sixToLast = chars[string.count -  6]
        let fiveToLast = chars[string.count - 5]
        if sevenToLast.description.contains("0") {
            return String([sixToLast, fiveToLast])
        } else {
            return String([sevenToLast, sixToLast, fiveToLast])
        }
    }
    func textBetween(text: String, start: String, end: String) -> String? {
        guard
            let startRange = text.range(of: start),
            let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex)
        else { return nil }
        
        let range = startRange.upperBound..<endRange.lowerBound
        return String(text[range])
    }

}

import WebKit

struct ImageView: View {
    @State var url: URL?
    @State var section: String?
    @State var note: Bool?
    @State private var currentZoom = 0.0
    @State private var totalZoom = 1.0
    @State private var page = WebPage()
    var body: some View {
        if section == "Notes" {
            Text("Class Notes")
                .font(.title)
                .frame(alignment: .top)
        } else {
            if section == "Practice" {
                Text("Practice")
                    .font(.title)
                    .frame(alignment: .top)
                
            } else {
                Text("Section \(section ?? "")")
                    .font(.title)
                    .frame(alignment: .top)
            }
        }
        if note ?? true {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 350, height: 500)
                    .cornerRadius(12)
                    .shadow(radius: 5)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                currentZoom = value - 1
                            }
                            .onEnded { value in
                                totalZoom += currentZoom
                                currentZoom = 0
                            }
                    )
            } placeholder: {
                ProgressView()
            }
        } else {
            WebView(page)
                .onAppear {
                    page.load(URLRequest(url: URL(string: deleteBeforePhrase(text: url?.absoluteString ?? "" , phrase: "https"))!))
            }
        }
    }
    func deleteBeforePhrase(text: String, phrase: String) -> String {
        if let range = text.range(of: phrase) {
            return String(text[range.lowerBound...]) // keep phrase and after
        }
        return text // unchanged if phrase not found
    }
}


struct sorryPage: View {
    var body: some View {
        Text("Sorry, You do not have access to view this page \n Try logging in or contacting Luke")
    }
}
