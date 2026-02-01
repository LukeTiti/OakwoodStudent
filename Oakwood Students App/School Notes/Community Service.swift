//
//  Community Service.swift
//  School Notes
//
//  Created by Luke Titi on 11/18/25.
//

import SwiftUI
import PDFKit
import SwiftSoup

// MARK: - ServiceView (Main view with To Submit, Pending, Submitted, and Completed sections)
struct ServiceView: View {
    @EnvironmentObject var appInfo: AppInfo
    @State var servicesByYear: [String: [Service]] = [:]
    @State var toSubmit: [LocalService] = []
    @State var submittedForms: [SubmittedForm] = []
    @State var totalHours: Double = 0
    @State var showPDF = false
    @State var showAddSheet = false
    @State var isSelecting = false
    @State var selectedIDs: Set<UUID> = []
    @State var showCreateFormSheet = false

    let pdfURL = URL(string: "https://documents.veracross.com/oakwood/volunteer_hours/39950.pdf")!
    let htmlURL = URL(string: "https://documents.veracross.com/oakwood/volunteer_hours/39950.html")!

    var sortedYears: [String] { servicesByYear.keys.sorted().reversed() }
    var selectedTotalHours: Double { toSubmit.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.hours } }

    var body: some View {
        List {
                // To Submit Section
                if !toSubmit.isEmpty {
                    Section {
                        ForEach(toSubmit) { service in
                            HStack {
                                if isSelecting {
                                    Image(systemName: selectedIDs.contains(service.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedIDs.contains(service.id) ? .blue : .gray)
                                        .onTapGesture { toggleSelection(service) }
                                }
                                LocalServiceRow(service: service)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: !isSelecting) {
                                if !isSelecting {
                                    Button("Delete", role: .destructive) { deleteToSubmit(service) }
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { if isSelecting { toggleSelection(service) } }
                        }
                    } header: {
                        HStack {
                            Text("To Submit")
                            Spacer()
                            Button(isSelecting ? "Done" : "Select") {
                                if isSelecting { selectedIDs.removeAll() }
                                isSelecting.toggle()
                            }
                            .font(.caption)
                            .textCase(.none)
                        }
                    } footer: {
                        if isSelecting && !selectedIDs.isEmpty {
                            Button(action: { showCreateFormSheet = true }) {
                                HStack {
                                    Image(systemName: "doc.badge.plus")
                                    Text("Create Form (\(selectedIDs.count) items, \(selectedTotalHours, specifier: "%.1f") hrs)")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                // Submitted to Advisor Section (from Firebase)
                if !submittedForms.isEmpty {
                    Section("Submitted to Advisor") {
                        ForEach(submittedForms) { form in
                            NavigationLink(destination: SubmittedFormDetailView(form: form)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(form.title)
                                            .fontWeight(.medium)
                                        HStack(spacing: 4) {
                                            Text("\(form.totalHours, specifier: "%.1f") hrs")
                                            Text("•")
                                            Text(form.submittedAt, style: .date)
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    StatusBadge(status: form.status)
                                }
                            }
                        }
                    }
                }

                // Completed Sections (by Year)
                ForEach(sortedYears, id: \.self) { year in
                    Section {
                        ForEach(servicesByYear[year] ?? []) { service in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(service.notes)
                                    Spacer()
                                    Text("\(service.hours, specifier: "%.1f") hrs").foregroundColor(.secondary)
                                }
                                HStack {
                                    Text(service.date).font(.caption).foregroundColor(.secondary)
                                    Text("•").foregroundColor(.secondary)
                                    Text(service.description).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    } header: { Text(year) }
                }
            }
            .navigationTitle("Community Service")
            .onAppear {
                loadLocalData()
                Task {
                    await loadServiceHours()
                    await fetchSubmittedForms()
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if totalHours > 0 {
                        Text("\(totalHours, specifier: "%.1f") hrs")
                            .font(.headline)
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { showAddSheet = true }) { Image(systemName: "plus") }
                    Button(action: { showPDF = true }) { Image(systemName: "doc.text") }
                }
            }
            .sheet(isPresented: $showPDF) {
                NavigationStack {
                    PDFViewer(url: pdfURL, appInfo: appInfo)
                        .navigationTitle("Service Form")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { showPDF = false } }
                        }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddServiceSheet(toSubmit: $toSubmit, onSave: saveLocalData)
            }
            .sheet(isPresented: $showCreateFormSheet) {
                CreateFormSheet(
                    selectedServices: toSubmit.filter { selectedIDs.contains($0.id) },
                    studentId: appInfo.googleVM.userEmail.isEmpty ? "unknown" : appInfo.googleVM.userEmail,
                    studentName: appInfo.googleVM.userName.isEmpty ? "Unknown" : appInfo.googleVM.userName,
                    onSuccess: {
                        toSubmit.removeAll { selectedIDs.contains($0.id) }
                        selectedIDs.removeAll()
                        isSelecting = false
                        saveLocalData()
                        Task { await fetchSubmittedForms() }
                    }
                )
            }
    }

    func toggleSelection(_ service: LocalService) {
        if selectedIDs.contains(service.id) { selectedIDs.remove(service.id) }
        else { selectedIDs.insert(service.id) }
    }

    func deleteToSubmit(_ service: LocalService) {
        toSubmit.removeAll { $0.id == service.id }
        saveLocalData()
    }

    func fetchSubmittedForms() async {
        let studentId = appInfo.googleVM.userEmail.isEmpty ? "unknown" : appInfo.googleVM.userEmail
        do {
            let forms = try await FirebaseService.shared.fetchMyServiceForms(studentId: studentId)
            await MainActor.run { submittedForms = forms }
        } catch {
            print("Failed to fetch submitted forms: \(error)")
        }
    }

    func saveLocalData() {
        if let data = try? JSONEncoder().encode(toSubmit) { UserDefaults.standard.set(data, forKey: "serviceToSubmit") }
    }

    func loadLocalData() {
        if let data = UserDefaults.standard.data(forKey: "serviceToSubmit"),
           let decoded = try? JSONDecoder().decode([LocalService].self, from: data) { toSubmit = decoded }
    }
}

// MARK: - LocalServiceRow (Displays a single service entry with notes, hours, date, type)
struct LocalServiceRow: View {
    let service: LocalService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(service.notes)
                Spacer()
                Text("\(service.hours, specifier: "%.1f") hrs").foregroundColor(.secondary)
            }
            HStack {
                Text(service.date).font(.caption).foregroundColor(.secondary)
                Text("•").foregroundColor(.secondary)
                Text(service.description).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - StatusBadge (Shows pending/approved/rejected status)
struct StatusBadge: View {
    let status: String
    var color: Color {
        switch status {
        case "approved": return .green
        case "rejected": return .red
        default: return .orange
        }
    }
    var body: some View {
        Text(status.capitalized)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }
}

// MARK: - SubmittedFormDetailView (Shows full details of a submitted form)
struct SubmittedFormDetailView: View {
    let form: SubmittedForm

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    StatusBadge(status: form.status)
                }
                HStack {
                    Text("Total Hours")
                    Spacer()
                    Text("\(form.totalHours, specifier: "%.1f")")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Submitted")
                    Spacer()
                    Text(form.submittedAt, style: .date)
                        .foregroundColor(.secondary)
                }
                if !form.taxID.isEmpty {
                    HStack {
                        Text("Tax ID")
                        Spacer()
                        Text(form.taxID)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Service Entries") {
                ForEach(form.services) { service in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(service.notes)
                            Spacer()
                            Text("\(service.hours, specifier: "%.1f") hrs")
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text(service.date)
                            Text("•")
                            Text(service.description)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }

            if !form.reflection1.isEmpty || !form.reflection2.isEmpty || !form.reflection3.isEmpty {
                Section("Reflections") {
                    if !form.reflection1.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reflection 1").font(.caption).foregroundColor(.secondary)
                            Text(form.reflection1)
                        }
                    }
                    if !form.reflection2.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reflection 2").font(.caption).foregroundColor(.secondary)
                            Text(form.reflection2)
                        }
                    }
                    if !form.reflection3.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reflection 3").font(.caption).foregroundColor(.secondary)
                            Text(form.reflection3)
                        }
                    }
                }
            }
        }
        .navigationTitle(form.title)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - AddServiceSheet (Form to add a new service entry to To Submit)
struct AddServiceSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var toSubmit: [LocalService]
    var onSave: () -> Void

    @State private var notes = ""
    @State private var hours = ""
    @State private var date = Date()
    @State private var description = "Outside Community Service"
    let descriptions = ["Outside Community Service", "Oakwood Service"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Activity", text: $notes)
                TextField("Hours", text: $hours).keyboardType(.decimalPad)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Type", selection: $description) {
                    ForEach(descriptions, id: \.self) { Text($0).tag($0) }
                }
            }
            .navigationTitle("Add Service Hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "MM/dd/yyyy"
                        let newService = LocalService(date: formatter.string(from: date), description: description, notes: notes, hours: Double(hours) ?? 0)
                        toSubmit.append(newService)
                        onSave()
                        dismiss()
                    }
                    .disabled(notes.isEmpty || hours.isEmpty)
                }
            }
        }
    }
}

// MARK: - CreateFormSheet (Form to enter reflections and tax ID, submits directly to Firebase)
struct CreateFormSheet: View {
    @Environment(\.dismiss) var dismiss
    let selectedServices: [LocalService]
    let studentId: String
    let studentName: String
    var onSuccess: () -> Void

    @State private var title = ""
    @State private var reflection1 = ""
    @State private var reflection2 = ""
    @State private var reflection3 = ""
    @State private var taxID = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var hasOutsideService: Bool { selectedServices.contains { $0.description == "Outside Community Service" } }
    var totalHours: Double { selectedServices.reduce(0) { $0 + $1.hours } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Form Title") {
                    TextField("e.g. Basketball Scorekeeping", text: $title)
                }
                Section("Form Summary") {
                    HStack { Text("Entries"); Spacer(); Text("\(selectedServices.count)").foregroundColor(.secondary) }
                    HStack { Text("Total Hours"); Spacer(); Text("\(totalHours, specifier: "%.1f")").foregroundColor(.secondary) }
                }
                Section("Reflection Questions") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reflection 1").font(.caption).foregroundColor(.secondary)
                        TextField("Enter response...", text: $reflection1, axis: .vertical).lineLimit(3...6)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reflection 2").font(.caption).foregroundColor(.secondary)
                        TextField("Enter response...", text: $reflection2, axis: .vertical).lineLimit(3...6)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reflection 3").font(.caption).foregroundColor(.secondary)
                        TextField("Enter response...", text: $reflection3, axis: .vertical).lineLimit(3...6)
                    }
                }
                if hasOutsideService {
                    Section {
                        TextField("Tax ID Number", text: $taxID)
                    } header: { Text("Organization Tax ID") }
                    footer: { Text("Required for outside community service hours").font(.caption) }
                }
                if let error = errorMessage {
                    Section { Text(error).foregroundColor(.red) }
                }
            }
            .navigationTitle("Submit Form")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: submitForm) {
                        if isSubmitting { ProgressView() }
                        else { Text("Submit") }
                    }
                    .disabled(isSubmitting || title.isEmpty)
                }
            }
        }
    }

    func submitForm() {
        isSubmitting = true
        errorMessage = nil
        let form = ServiceForm(
            title: title,
            dateCreated: Date(),
            services: selectedServices,
            reflection1: reflection1,
            reflection2: reflection2,
            reflection3: reflection3,
            taxID: hasOutsideService ? taxID : nil
        )
        Task {
            do {
                try await FirebaseService.shared.submitServiceForm(form, studentId: studentId, studentName: studentName)
                await MainActor.run {
                    onSuccess()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to submit: \(error.localizedDescription)"
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - PDFViewer (Displays PDF from URL with Veracross auth cookies)
struct PDFViewer: UIViewRepresentable {
    let url: URL
    let appInfo: AppInfo

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        Task {
            await appInfo.restorePersistedCookiesIntoStores()
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let document = PDFDocument(data: data) {
                    await MainActor.run { pdfView.document = document }
                }
            } catch { print("Failed to load PDF: \(error)") }
        }
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - Data Models

struct Service: Identifiable { // Completed service from Veracross
    var id = UUID()
    var date: String
    var description: String
    var notes: String
    var hours: Double
    var schoolYear: String
}

struct LocalService: Identifiable, Codable { // Local service entry (To Submit or in Form)
    var id = UUID()
    var date: String
    var description: String
    var notes: String
    var hours: Double
}

struct ServiceForm: Identifiable, Codable { // Physical form with multiple entries, reflections, and tax ID
    var id = UUID()
    var title: String
    var dateCreated: Date
    var services: [LocalService]
    var reflection1: String
    var reflection2: String
    var reflection3: String
    var taxID: String?
}

// MARK: - Network Extension

extension ServiceView {
    func loadServiceHours() async { // Fetches and parses service hours from Veracross HTML
        await appInfo.restorePersistedCookiesIntoStores()
        do {
            let (data, _) = try await URLSession.shared.data(from: htmlURL)
            guard let html = String(data: data, encoding: .utf8) else { return }
            let doc = try SwiftSoup.parse(html)

            if let totalText = try doc.select("p.total_hours strong").first()?.text(),
               let total = Double(totalText) {
                await MainActor.run { totalHours = total }
            }

            var grouped: [String: [Service]] = [:]
            let tbodies = try doc.select("table tbody")

            for tbody in tbodies {
                let tbodyClass = try tbody.className()
                let yearString: String
                if tbodyClass.hasPrefix("school_year_") {
                    yearString = tbodyClass.replacingOccurrences(of: "school_year_", with: "").replacingOccurrences(of: "_", with: "-")
                } else { yearString = "Unknown" }

                let rows = try tbody.select("tr").filter { row in
                    let className = try? row.className()
                    return className?.contains("row_") == true
                }

                for row in rows {
                    let service = Service(
                        date: try row.select("td.volunteer_date").text(),
                        description: try row.select("td.description").text(),
                        notes: try row.select("td.notes").text(),
                        hours: Double(try row.select("td.volunteer_hours").text()) ?? 0,
                        schoolYear: yearString
                    )
                    if grouped[yearString] != nil { grouped[yearString]?.append(service) }
                    else { grouped[yearString] = [service] }
                }
            }

            await MainActor.run { servicesByYear = grouped }
        } catch { print("Failed to load service hours: \(error)") }
    }
}
