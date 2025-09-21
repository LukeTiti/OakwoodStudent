//
//  Vercross Calander.swift
//  School Notes
//
//  Created by Luke Titi on 9/5/25.
//
import SwiftUI

struct ICSEvent: Identifiable {
    let id = UUID()
    let summary: String
    let start: Date
    let end: Date
}

struct ICSView: View {
    @State private var events: [ICSEvent] = []
    @State var string: String?
    @EnvironmentObject var appInfo: AppInfo
    
    var body: some View {
        List(events) { event in
            VStack(alignment: .leading) {
                Text(event.summary)
                    .font(.headline)
                if Calendar.current.isDate(event.start, inSameDayAs: event.end) && Calendar.current.isDateInToday(event.start) == false {
                    // For all-day events, show "All Day"
                    Text("All Day")
                        .font(.subheadline)
                } else {
                    Text("Start: \(event.start.formatted())")
                        .font(.subheadline)
                    Text("End: \(event.end.formatted())")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            fetchICS()
        }
    }

    func fetchICS() {
        guard let url = URL(string: string ?? "") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                print("Error fetching ICS: \(error)")
                return
            }
            
            guard let data = data,
                  let content = String(data: data, encoding: .utf8) else { return }
            
            var currentSummary: String?
            var currentStart: Date?
            var currentEnd: Date?
            
            let dateTimeFormatter = DateFormatter()
            dateTimeFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            dateTimeFormatter.timeZone = TimeZone(secondsFromGMT: 0)

            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyyMMdd"
            dateOnlyFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            
            var parsedEvents: [ICSEvent] = []
            
            for line in content.components(separatedBy: .newlines) {
                if line.hasPrefix("SUMMARY:") {
                    currentSummary = String(line.dropFirst(8))
                } else if line.hasPrefix("DTSTART") {
                    if line.contains("VALUE=DATE:") {
                        if let range = line.range(of: "VALUE=DATE:") {
                            let dateString = String(line[range.upperBound...])
                            currentStart = dateOnlyFormatter.date(from: dateString)
                        }
                    } else {
                        let dateString = String(line.dropFirst(8))
                        currentStart = dateTimeFormatter.date(from: dateString)
                    }
                } else if line.hasPrefix("DTEND") {
                    if line.contains("VALUE=DATE:") {
                        if let range = line.range(of: "VALUE=DATE:") {
                            let dateString = String(line[range.upperBound...])
                            if let endDate = dateOnlyFormatter.date(from: dateString) {
                                // Subtract 1 second to make all-day event inclusive
                                currentEnd = Calendar.current.date(byAdding: .second, value: -1, to: endDate)
                            }
                        }
                    } else {
                        let dateString = String(line.dropFirst(6))
                        currentEnd = dateTimeFormatter.date(from: dateString)
                    }
                } else if line == "END:VEVENT" {
                    if let summary = currentSummary,
                       let start = currentStart,
                       let end = currentEnd {
                        parsedEvents.append(ICSEvent(summary: summary, start: start, end: end))
                    }
                    currentSummary = nil
                    currentStart = nil
                    currentEnd = nil
                }
            }
            
            DispatchQueue.main.async {
                self.events = parsedEvents
            }
        }.resume()
    }
}
