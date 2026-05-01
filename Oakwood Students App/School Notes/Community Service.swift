//
//  Community Service.swift
//  School Notes
//

import SwiftUI
import PDFKit
import SwiftSoup
import FirebaseFirestore
import MessageUI

private let signingBaseURL = "https://oakwoodstudents-d9495.web.app/sign"

// MARK: - ServiceView

struct ServiceView: View {
    @EnvironmentObject var appInfo: AppInfo
    @State private var servicesByYear: [String: [Service]] = [:]
    @State private var toSubmit: [LocalService] = []
    @State private var forms: [SubmittedForm] = []
    @State private var totalHours: Double = 0
    @State private var showPDF = false
    @State private var showAddSheet = false
    @State private var showCreateForm = false
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var listener: ListenerRegistration?

    var pdfURL: URL? { appInfo.personPK.flatMap { URL(string: "https://documents.veracross.com/oakwood/volunteer_hours/\($0).pdf") } }
    var htmlURL: URL? { appInfo.personPK.flatMap { URL(string: "https://documents.veracross.com/oakwood/volunteer_hours/\($0).html") } }
    var selectedTotalHours: Double { toSubmit.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.hours } }
    var sortedYears: [String] { servicesByYear.keys.sorted().reversed() }

    var body: some View {
        List {
                // Logged (pending) hours
                if !toSubmit.isEmpty {
                    Section {
                        ForEach(toSubmit) { service in
                            HStack {
                                if isSelecting {
                                    Image(systemName: selectedIDs.contains(service.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedIDs.contains(service.id) ? .accentColor : .secondary)
                                        .onTapGesture { toggleSelection(service) }
                                }
                                LocalServiceRow(service: service)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { if isSelecting { toggleSelection(service) } }
                            .swipeActions(edge: .trailing) {
                                if !isSelecting {
                                    Button(role: .destructive) { deleteEntry(service) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Logged Hours")
                            Spacer()
                            Button(isSelecting ? "Done" : "Select") {
                                if isSelecting { selectedIDs.removeAll() }
                                isSelecting.toggle()
                            }
                            .font(.caption).textCase(.none)
                        }
                    } footer: {
                        if isSelecting && !selectedIDs.isEmpty {
                            Button { showCreateForm = true } label: {
                                Label("Create Form (\(selectedIDs.count) entries · \(selectedTotalHours, specifier: "%.1f") hrs)", systemImage: "doc.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                        }
                    }
                }

                // Forms
                if !forms.isEmpty {
                    Section("Forms") {
                        ForEach(forms) { form in
                            NavigationLink(destination: ServiceFormDetailView(form: form)) {
                                ServiceFormRow(form: form)
                            }
                        }
                    }
                }

                // Completed hours from Veracross
                ForEach(sortedYears, id: \.self) { year in
                    Section(year) {
                        ForEach(servicesByYear[year] ?? []) { service in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(service.notes)
                                    Spacer()
                                    Text("\(service.hours, specifier: "%.1f") hrs").foregroundColor(.secondary)
                                }
                                HStack {
                                    Text(service.date).font(.caption).foregroundColor(.secondary)
                                    Text("·").foregroundColor(.secondary)
                                    Text(service.description).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Community Service")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if totalHours > 0 { Text("\(totalHours, specifier: "%.1f") hrs").font(.headline) }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button { showAddSheet = true } label: { Image(systemName: "plus") }
                    Button { showPDF = true } label: { Image(systemName: "doc.text") }
                        .disabled(appInfo.personPK == nil)
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddServiceSheet(toSubmit: $toSubmit, onSave: saveLocalData)
            }
            .sheet(isPresented: $showCreateForm) {
                CreateFormSheet(
                    selectedServices: toSubmit.filter { selectedIDs.contains($0.id) },
                    studentId: appInfo.googleVM.userEmail,
                    studentName: appInfo.googleVM.userName
                ) { newForm in
                    toSubmit.removeAll { selectedIDs.contains($0.id) }
                    selectedIDs.removeAll(); isSelecting = false
                    saveLocalData()
                    forms.insert(newForm, at: 0)
                }
            }
            .sheet(isPresented: $showPDF) {
                NavigationStack {
                    PDFViewer(url: pdfURL ?? URL(string: "about:blank")!, appInfo: appInfo)
                        .navigationTitle("Service Record")
                        .inlineNavigationBarTitle()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPDF = false } } }
                }
            }
            .onAppear {
                loadLocalData()
                Task { await loadServiceHours() }
                startListening()
            }
            .onDisappear { listener?.remove() }
    }

    private func toggleSelection(_ s: LocalService) {
        if selectedIDs.contains(s.id) { selectedIDs.remove(s.id) } else { selectedIDs.insert(s.id) }
    }

    private func deleteEntry(_ s: LocalService) {
        toSubmit.removeAll { $0.id == s.id }; saveLocalData()
    }

    private func saveLocalData() {
        if let data = try? JSONEncoder().encode(toSubmit) { UserDefaults.standard.set(data, forKey: "serviceToSubmit") }
    }

    private func loadLocalData() {
        if let data = UserDefaults.standard.data(forKey: "serviceToSubmit"),
           let decoded = try? JSONDecoder().decode([LocalService].self, from: data) { toSubmit = decoded }
    }

    private func startListening() {
        guard !appInfo.googleVM.userEmail.isEmpty else { return }
        listener = FirebaseService.shared.listenForFormUpdates(studentId: appInfo.googleVM.userEmail) { updated in
            forms = updated
        }
    }
}

// MARK: - ServiceFormRow

struct ServiceFormRow: View {
    let form: SubmittedForm
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(form.title).font(.body.weight(.semibold))
                HStack(spacing: 4) {
                    Text("\(form.totalHours, specifier: "%.1f") hrs")
                    Text("·")
                    Text(form.submittedAt, style: .date)
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            ServiceStatusBadge(status: form.status)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ServiceFormDetailView

struct ServiceFormDetailView: View {
    @State var form: SubmittedForm
    @State private var isSubmitting = false
    @State private var showMail = false

    var signingURL: String { "\(signingBaseURL)/\(form.id)" }
    var mailData: MailData { makeSigningMailData(to: form.supervisorEmail, supervisorName: form.supervisorName, studentName: "", title: form.title, totalHours: form.totalHours, signingURL: signingURL) }

    var body: some View {
        List {
            Section {
                HStack { Text("Status"); Spacer(); ServiceStatusBadge(status: form.status) }
                HStack { Text("Total Hours"); Spacer(); Text("\(form.totalHours, specifier: "%.1f")").foregroundColor(.secondary) }
                HStack { Text("Supervisor"); Spacer(); Text(form.supervisorName).foregroundColor(.secondary) }
                if !form.supervisorSignature.isEmpty {
                    HStack { Text("Signed by"); Spacer(); Text(form.supervisorSignature).foregroundColor(.secondary) }
                }
                if let signedAt = form.signedAt {
                    HStack { Text("Signed"); Spacer(); Text(signedAt, style: .date).foregroundColor(.secondary) }
                }
            }

            // Action buttons based on status
            Section {
                switch form.status {
                case "pending_signature":
                    Button { showMail = true } label: {
                        Label("Resend Signing Email", systemImage: "envelope.arrow.triangle.branch")
                    }
                    .disabled(!MFMailComposeViewController.canSendMail())
                case "signed":
                    Button {
                        isSubmitting = true
                        Task {
                            try? await FirebaseService.shared.submitFormToAdvisor(formId: form.id)
                            await MainActor.run { form.status = "submitted"; isSubmitting = false }
                        }
                    } label: {
                        if isSubmitting { ProgressView() }
                        else { Label("Submit to Advisor", systemImage: "paperplane.fill") }
                    }
                    .disabled(isSubmitting)
                case "approved":
                    Button { } label: {
                        Label("Upload to Veracross", systemImage: "arrow.up.doc")
                    }
                    .foregroundColor(.secondary)
                default:
                    EmptyView()
                }
            }

            Section("Service Entries") {
                ForEach(form.services) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(s.notes); Spacer(); Text("\(s.hours, specifier: "%.1f") hrs").foregroundColor(.secondary) }
                        HStack { Text(s.date); Text("·"); Text(s.description) }.font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            if !form.reflection1.isEmpty || !form.reflection2.isEmpty || !form.reflection3.isEmpty {
                Section("Reflections") {
                    if !form.reflection1.isEmpty { reflectionRow("Reflection 1", form.reflection1) }
                    if !form.reflection2.isEmpty { reflectionRow("Reflection 2", form.reflection2) }
                    if !form.reflection3.isEmpty { reflectionRow("Reflection 3", form.reflection3) }
                }
            }
        }
        .navigationTitle(form.title)
        .largeNavigationBarTitle()
        .sheet(isPresented: $showMail) {
            MailComposerView(data: mailData, isPresented: $showMail)
        }
    }

    @ViewBuilder private func reflectionRow(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(text)
        }
    }
}

// MARK: - CreateFormSheet

struct CreateFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedServices: [LocalService]
    let studentId: String
    let studentName: String
    var onSuccess: (SubmittedForm) -> Void

    @State private var title = ""
    @State private var supervisorName = ""
    @State private var supervisorEmail = ""
    @State private var reflection1 = ""
    @State private var reflection2 = ""
    @State private var reflection3 = ""
    @State private var taxID = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showMail = false
    @State private var pendingMailData: MailData? = nil

    var hasOutsideService: Bool { selectedServices.contains { $0.description == "Outside Community Service" } }
    var totalHours: Double { selectedServices.reduce(0) { $0 + $1.hours } }
    var canSubmit: Bool { !title.isEmpty && !supervisorName.isEmpty && !supervisorEmail.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Form Details") {
                    TextField("Title (e.g. Food Bank Volunteering)", text: $title)
                    HStack {
                        Text("Entries"); Spacer()
                        Text("\(selectedServices.count)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Total Hours"); Spacer()
                        Text("\(totalHours, specifier: "%.1f")").foregroundColor(.secondary)
                    }
                }

                Section {
                    TextField("Supervisor Full Name", text: $supervisorName)
                    TextField("Supervisor Email", text: $supervisorEmail)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                } header: { Text("Supervisor") } footer: {
                    Text("They'll receive an email with a link to review and sign the form.")
                }

                Section("Reflections") {
                    TextField("Reflection 1", text: $reflection1, axis: .vertical).lineLimit(3...6)
                    TextField("Reflection 2", text: $reflection2, axis: .vertical).lineLimit(3...6)
                    TextField("Reflection 3", text: $reflection3, axis: .vertical).lineLimit(3...6)
                }

                if hasOutsideService {
                    Section {
                        TextField("Tax ID Number", text: $taxID)
                    } header: { Text("Organization Tax ID") }
                    footer: { Text("Required for outside community service hours") }
                }

                if let error = errorMessage {
                    Section { Text(error).foregroundColor(.red) }
                }
            }
            .navigationTitle("Create Form")
            .inlineNavigationBarTitle()
            .sheet(isPresented: $showMail, onDismiss: { dismiss() }) {
                if let data = pendingMailData { MailComposerView(data: data, isPresented: $showMail) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await submit() } } label: {
                        if isSubmitting { ProgressView() } else { Text("Send for Signature") }
                    }
                    .disabled(!canSubmit || isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true; errorMessage = nil
        let form = ServiceForm(title: title, dateCreated: Date(), services: selectedServices,
                               reflection1: reflection1, reflection2: reflection2, reflection3: reflection3,
                               taxID: hasOutsideService ? taxID : nil)
        do {
            let docId = try await FirebaseService.shared.submitServiceForm(
                form, studentId: studentId, studentName: studentName,
                supervisorName: supervisorName, supervisorEmail: supervisorEmail)

            let submittedForm = SubmittedForm(
                id: docId, title: title, status: "pending_signature", submittedAt: Date(),
                totalHours: totalHours, reflection1: reflection1, reflection2: reflection2,
                reflection3: reflection3, taxID: hasOutsideService ? taxID : "",
                services: selectedServices, supervisorName: supervisorName,
                supervisorEmail: supervisorEmail, supervisorSignature: "", signedAt: nil)

            let mailData = makeSigningMailData(to: supervisorEmail, supervisorName: supervisorName,
                studentName: studentName, title: title, totalHours: totalHours,
                signingURL: "\(signingBaseURL)/\(docId)")

            await MainActor.run {
                onSuccess(submittedForm)
                if MFMailComposeViewController.canSendMail() {
                    pendingMailData = mailData
                    showMail = true
                } else {
                    dismiss()
                }
            }
        } catch {
            await MainActor.run { errorMessage = "Failed to create form: \(error.localizedDescription)"; isSubmitting = false }
        }
    }

}

// MARK: - ServiceStatusBadge

struct ServiceStatusBadge: View {
    let status: String
    private var label: String {
        switch status {
        case "pending_signature": return "Awaiting Signature"
        case "signed": return "Signed"
        case "submitted": return "Submitted"
        case "approved": return "Approved"
        default: return status.capitalized
        }
    }
    private var color: Color {
        switch status {
        case "signed": return .blue
        case "submitted": return .orange
        case "approved": return .green
        default: return .secondary
        }
    }
    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - Mail Composer

struct MailData {
    let to: String
    let subject: String
    let body: String
}

func makeSigningMailData(to email: String, supervisorName: String, studentName: String, title: String, totalHours: Double, signingURL: String) -> MailData {
    MailData(
        to: email,
        subject: "Please sign: \(title) — Service Hours Form",
        body: """
Hi \(supervisorName),

I'm requesting your signature for my community service hours form.

Activity: \(title)
Total Hours: \(String(format: "%.1f", totalHours))

Please click the link below to review the details and sign electronically:

\(signingURL)

Thank you,
\(studentName.isEmpty ? "Your Student" : studentName)
"""
    )
}

struct MailComposerView: UIViewControllerRepresentable {
    let data: MailData
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([data.to])
        vc.setSubject(data.subject)
        vc.setMessageBody(data.body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        @Binding var isPresented: Bool
        init(isPresented: Binding<Bool>) { _isPresented = isPresented }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            isPresented = false
        }
    }
}

// MARK: - AddServiceSheet

struct AddServiceSheet: View {
    @Environment(\.dismiss) private var dismiss
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
                Section {
                    TextField("Activity (e.g. Food Bank)", text: $notes)
                    TextField("Hours", text: $hours).keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Type", selection: $description) {
                        ForEach(descriptions, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .navigationTitle("Log Hours")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let f = DateFormatter(); f.dateFormat = "MM/dd/yyyy"
                        toSubmit.append(LocalService(date: f.string(from: date), description: description,
                                                      notes: notes, hours: Double(hours) ?? 0))
                        onSave(); dismiss()
                    }
                    .disabled(notes.isEmpty || hours.isEmpty)
                }
            }
        }
    }
}

// MARK: - LocalServiceRow

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
                Text("·").foregroundColor(.secondary)
                Text(service.description).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - PDFViewer

#if os(iOS)
struct PDFViewer: UIViewRepresentable {
    let url: URL
    let appInfo: AppInfo
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true
        Task {
            await appInfo.restorePersistedCookiesIntoStores()
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let doc = PDFDocument(data: data) { await MainActor.run { v.document = doc } }
        }
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}
#elseif os(macOS)
struct PDFViewer: NSViewRepresentable {
    let url: URL
    let appInfo: AppInfo
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true
        Task {
            await appInfo.restorePersistedCookiesIntoStores()
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let doc = PDFDocument(data: data) { await MainActor.run { v.document = doc } }
        }
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {}
}
#endif

// MARK: - Data Models

struct Service: Identifiable {
    var id = UUID()
    var date: String
    var description: String
    var notes: String
    var hours: Double
    var schoolYear: String
}

struct LocalService: Identifiable, Codable {
    var id = UUID()
    var date: String
    var description: String
    var notes: String
    var hours: Double
}

struct ServiceForm: Identifiable, Codable {
    var id = UUID()
    var title: String
    var dateCreated: Date
    var services: [LocalService]
    var reflection1: String
    var reflection2: String
    var reflection3: String
    var taxID: String?
}

// MARK: - Veracross Scraping

extension ServiceView {
    func loadServiceHours() async {
        await appInfo.restorePersistedCookiesIntoStores()
        if appInfo.personPK == nil { await appInfo.fetchPersonPK() }
        guard let htmlURL else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: htmlURL),
              let html = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(html) else { return }

        if let totalText = try? doc.select("p.total_hours strong").first()?.text(),
           let total = Double(totalText) { await MainActor.run { totalHours = total } }

        var grouped: [String: [Service]] = [:]
        for tbody in (try? doc.select("table tbody").array()) ?? [] {
            let cls = (try? tbody.className()) ?? ""
            let year = cls.hasPrefix("school_year_")
                ? cls.replacingOccurrences(of: "school_year_", with: "").replacingOccurrences(of: "_", with: "-")
                : "Unknown"
            for row in ((try? tbody.select("tr").array()) ?? []).filter({ (try? $0.className().contains("row_")) == true }) {
                let s = Service(
                    date: (try? row.select("td.volunteer_date").text()) ?? "",
                    description: (try? row.select("td.description").text()) ?? "",
                    notes: (try? row.select("td.notes").text()) ?? "",
                    hours: Double((try? row.select("td.volunteer_hours").text()) ?? "") ?? 0,
                    schoolYear: year)
                grouped[year, default: []].append(s)
            }
        }
        await MainActor.run { servicesByYear = grouped }
    }
}
