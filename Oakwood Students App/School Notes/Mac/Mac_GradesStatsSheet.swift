//
//  Mac_GradesStatsSheet.swift
//  School Notes
//
import SwiftUI

// MARK: - Mac Stats Sheet

struct Mac_StatsSheet: View {
    @EnvironmentObject var appInfo: AppInfo
    @Environment(\.dismiss) private var dismiss

    private func letterToPoints(_ letter: String) -> Double? {
        switch letter.trimmingCharacters(in: .whitespaces) {
        case "A":   return 4.0
        case "A-":  return 3.7
        case "B+":  return 3.3
        case "B":   return 3.0
        case "B-":  return 2.7
        case "C+":  return 2.3
        case "C":   return 2.0
        case "C-":  return 1.7
        case "D+":  return 1.3
        case "D":   return 1.0
        case "D-":  return 0.7
        case "F":   return 0.0
        default:    return nil
        }
    }

    private func gpaColor(_ points: Double) -> Color {
        if points >= 3.7 { return .green }
        if points >= 3.0 { return .yellow }
        if points >= 2.0 { return .orange }
        return .red
    }

    private func isWeighted(_ courseName: String) -> Bool {
        let lower = courseName.lowercased()
        return lower.contains("honors") || lower.contains("ap ")
    }

    private struct CourseGPAEntry {
        let name: String
        let letter: String
        let percent: String?
        let points: Double
        let weighted: Bool
    }

    private var entries: [CourseGPAEntry] {
        appInfo.courses.compactMap { course in
            let nameLower = course.class_name.lowercased()
            let sportsAndNonAcademic = ["independent pe", "community meeting", "assembly",
                "study period", "volleyball", "basketball", "tennis", "badminton",
                "soccer", "swimming", "track", "cross country"]
            guard !sportsAndNonAcademic.contains(where: { nameLower.contains($0) }),
                  !(nameLower.contains("hs") && nameLower.contains("team")) else { return nil }
            let weighted = isWeighted(course.class_name)
            let hasAssignments = !(course.assignments ?? []).isEmpty

            let letter: String
            var pts: Double

            if let l = course.ptd_letter_grade,
               !l.trimmingCharacters(in: .whitespaces).isEmpty,
               let p = letterToPoints(l) {
                // Has a real grade — use it
                letter = l.trimmingCharacters(in: .whitespaces)
                pts = p
            } else if !hasAssignments {
                // No assignments yet — assume A (100%)
                letter = "A"
                pts = 4.0
            } else {
                // Has assignments but no letter grade yet — skip
                return nil
            }

            if weighted { pts += 1 }
            return CourseGPAEntry(name: course.class_name, letter: letter, percent: course.ptd_grade, points: pts, weighted: weighted)
        }
    }

    private var weightedGPA: Double? {
        guard !entries.isEmpty else { return nil }
        return entries.map(\.points).reduce(0, +) / Double(entries.count)
    }

    private var unweightedGPA: Double? {
        guard !entries.isEmpty else { return nil }
        let unweightedPoints = entries.map { $0.weighted ? $0.points - 1 : $0.points }
        return unweightedPoints.reduce(0, +) / Double(entries.count)
    }

    var body: some View {
        NavigationStack {
            List {
                if let weighted = weightedGPA, let unweighted = unweightedGPA {
                    Section {
                        HStack(spacing: 0) {
                            Spacer()
                            VStack(spacing: 4) {
                                Text(weighted, format: .number.precision(.fractionLength(2)))
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundColor(gpaColor(weighted))
                                Text("Weighted")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Divider()
                            Spacer()
                            VStack(spacing: 4) {
                                Text(unweighted, format: .number.precision(.fractionLength(2)))
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundColor(gpaColor(unweighted))
                                Text("Unweighted")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                } else {
                    Section {
                        Text("No grade data yet. Grades load from Veracross.")
                            .foregroundColor(.secondary)
                            .macRowPadding()
                    }
                }

                Section("Documents") {
                    let pk = appInfo.personPK ?? 39950
                    NavigationLink(destination: PDFViewer(url: URL(string: "https://documents.veracross.com/oakwood/attendance/\(pk)?grading_period=2&key=_")!, appInfo: appInfo)
                        .navigationTitle("Attendance – Sem 1")) {
                        Label("Attendance – Semester 1", systemImage: "doc.text")
                    }
                    .macRowPadding()
                    NavigationLink(destination: PDFViewer(url: URL(string: "https://documents.veracross.com/oakwood/attendance/\(pk)?grading_period=6&key=_")!, appInfo: appInfo)
                        .navigationTitle("Attendance – Sem 2")) {
                        Label("Attendance – Semester 2", systemImage: "doc.text")
                    }
                    .macRowPadding()
                    NavigationLink(destination: PDFViewer(url: URL(string: "https://documents.veracross.com/oakwood/report_card/8231?grading_period=2&pad=32941")!, appInfo: appInfo)
                        .navigationTitle("Report Card – Sem 1")) {
                        Label("Report Card – Semester 1", systemImage: "doc.richtext")
                    }
                    .macRowPadding()
                    NavigationLink(destination: PDFViewer(url: URL(string: "https://documents.veracross.com/oakwood/report_card/8231?grading_period=6&pad=32941")!, appInfo: appInfo)
                        .navigationTitle("Report Card – Sem 2")) {
                        Label("Report Card – Semester 2", systemImage: "doc.richtext")
                    }
                    .macRowPadding()
                }
                .onAppear {
                    if appInfo.personPK == nil { Task { await appInfo.fetchPersonPK() } }
                }

                if !entries.isEmpty {
                    Section("Courses") {
                        ForEach(entries, id: \.name) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .font(.body)
                                    if entry.weighted {
                                        Text("Weighted")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(entry.letter)
                                        .fontWeight(.semibold)
                                        .foregroundColor(gpaColor(entry.points))
                                    let unweightedPts = entry.weighted ? entry.points - 1 : entry.points
                                    if entry.weighted {
                                        HStack(spacing: 8) {
                                            Text("W: \(entry.points, format: .number.precision(.fractionLength(1)))")
                                                .foregroundColor(gpaColor(entry.points))
                                            Text("UW: \(unweightedPts, format: .number.precision(.fractionLength(1)))")
                                                .foregroundColor(gpaColor(unweightedPts))
                                        }
                                        .font(.subheadline)
                                    } else {
                                        Text(entry.points, format: .number.precision(.fractionLength(1)))
                                            .font(.subheadline)
                                            .foregroundColor(gpaColor(entry.points))
                                    }
                                }
                            }
                            .macRowPadding()
                        }
                    }
                }
            }
            .macInsetListStyle()
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
