//
//  Mac_ServiceView.swift
//  School Notes
//
import SwiftUI
import SwiftSoup
import FirebaseFirestore

private let macSigningBaseURL = "https://oakwoodstudents-d9495.web.app/sign"

struct Mac_ServiceView: View {
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

    private var pdfURL: URL? { appInfo.personPK.flatMap { URL(string: "https://documents.veracross.com/oakwood/volunteer_hours/\($0).pdf") } }
    private var htmlURL: URL? { appInfo.personPK.flatMap { URL(string: "https://documents.veracross.com/oakwood/volunteer_hours/\($0).html") } }
    private var selectedTotalHours: Double { toSubmit.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.hours } }
    private var sortedYears: [String] { servicesByYear.keys.sorted().reversed() }

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(totalHours, specifier: "%.1f")")
                        .font(.system(size: 40, weight: .bold))
                    Text("hours completed")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            }

            if !toSubmit.isEmpty {
                Section {
                    ForEach(toSubmit) { service in
                        HStack {
                            if isSelecting {
                                Image(systemName: selectedIDs.contains(service.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(service.id) ? Color.accentColor : Color.secondary)
                                    .onTapGesture { toggleSelection(service) }
                            }
                            Mac_LocalServiceRow(service: service)
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
                        .font(.caption)
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

            if !forms.isEmpty {
                Section("Forms") {
                    ForEach(forms) { form in
                        NavigationLink {
                            Mac_ServiceFormDetailView(form: form)
                        } label: {
                            ServiceFormRow(form: form)
                        }
                    }
                }
            }

            ForEach(sortedYears, id: \.self) { year in
                Section(year) {
                    ForEach(servicesByYear[year] ?? []) { service in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(service.notes)
                                Spacer()
                                Text("\(service.hours, specifier: "%.1f") hrs").foregroundStyle(.secondary)
                            }
                            HStack {
                                Text(service.date).font(.caption).foregroundStyle(.secondary)
                                Text("·").foregroundStyle(.secondary)
                                Text(service.description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity, alignment: .center)
        .navigationTitle("Community Service")
        .toolbar {
            ToolbarItemGroup(placement: .confirmationAction) {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
                Button { showPDF = true } label: { Image(systemName: "doc.text") }
                    .disabled(appInfo.personPK == nil)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            Mac_AddServiceSheet(toSubmit: $toSubmit, onSave: saveLocalData)
                .frame(minWidth: 420, minHeight: 340)
        }
        .sheet(isPresented: $showCreateForm) {
            Mac_CreateFormSheet(
                selectedServices: toSubmit.filter { selectedIDs.contains($0.id) },
                studentId: appInfo.googleVM.userEmail,
                studentName: appInfo.googleVM.userName
            ) { newForm in
                toSubmit.removeAll { selectedIDs.contains($0.id) }
                selectedIDs.removeAll(); isSelecting = false
                saveLocalData()
                forms.insert(newForm, at: 0)
            }
            .frame(minWidth: 480, minHeight: 560)
        }
        .sheet(isPresented: $showPDF) {
            NavigationStack {
                PDFViewer(url: pdfURL ?? URL(string: "about:blank")!, appInfo: appInfo)
                    .navigationTitle("Service Record")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPDF = false } } }
            }
            .frame(minWidth: 500, minHeight: 600)
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

    private func loadServiceHours() async {
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

// MARK: - Form Detail

private struct Mac_ServiceFormDetailView: View {
    @State var form: SubmittedForm
    @State private var isSubmitting = false

    private var signingURL: String { "\(macSigningBaseURL)/\(form.id)" }
    private var mailData: MailData { makeSigningMailData(to: form.supervisorEmail, supervisorName: form.supervisorName, studentName: "", title: form.title, totalHours: form.totalHours, signingURL: signingURL) }

    var body: some View {
        List {
            Section {
                HStack { Text("Status"); Spacer(); ServiceStatusBadge(status: form.status) }
                HStack { Text("Total Hours"); Spacer(); Text("\(form.totalHours, specifier: "%.1f")").foregroundStyle(.secondary) }
                HStack { Text("Supervisor"); Spacer(); Text(form.supervisorName).foregroundStyle(.secondary) }
                if !form.supervisorSignature.isEmpty {
                    HStack { Text("Signed by"); Spacer(); Text(form.supervisorSignature).foregroundStyle(.secondary) }
                }
                if let signedAt = form.signedAt {
                    HStack { Text("Signed"); Spacer(); Text(signedAt, style: .date).foregroundStyle(.secondary) }
                }
            }

            Section {
                switch form.status {
                case "pending_signature":
                    Button {
                        if let url = mailtoURL(mailData) { openExternalURL(url.absoluteString) }
                    } label: {
                        Label("Resend Signing Email", systemImage: "envelope.arrow.triangle.branch")
                    }
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
                    Label("Upload to Veracross", systemImage: "arrow.up.doc")
                        .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }

            Section("Service Entries") {
                ForEach(form.services) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(s.notes); Spacer(); Text("\(s.hours, specifier: "%.1f") hrs").foregroundStyle(.secondary) }
                        HStack { Text(s.date); Text("·"); Text(s.description) }.font(.caption).foregroundStyle(.secondary)
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
    }

    @ViewBuilder private func reflectionRow(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(text)
        }
    }
}

// MARK: - Create Form Sheet

private struct Mac_CreateFormSheet: View {
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

    private var hasOutsideService: Bool { selectedServices.contains { $0.description == "Outside Community Service" } }
    private var totalHours: Double { selectedServices.reduce(0) { $0 + $1.hours } }
    private var canSubmit: Bool { !title.isEmpty && !supervisorName.isEmpty && !supervisorEmail.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Form Details") {
                    TextField("Title (e.g. Food Bank Volunteering)", text: $title)
                    HStack {
                        Text("Entries"); Spacer()
                        Text("\(selectedServices.count)").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Total Hours"); Spacer()
                        Text("\(totalHours, specifier: "%.1f")").foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("Supervisor Full Name", text: $supervisorName)
                    TextField("Supervisor Email", text: $supervisorEmail)
                        .autocorrectionDisabled()
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
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Create Form")
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
                signingURL: "\(macSigningBaseURL)/\(docId)")

            await MainActor.run {
                onSuccess(submittedForm)
                if let url = mailtoURL(mailData) { openExternalURL(url.absoluteString) }
                dismiss()
            }
        } catch {
            await MainActor.run { errorMessage = "Failed to create form: \(error.localizedDescription)"; isSubmitting = false }
        }
    }
}

// MARK: - Add Service Sheet

private struct Mac_AddServiceSheet: View {
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
                    TextField("Hours", text: $hours)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Type", selection: $description) {
                        ForEach(descriptions, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .navigationTitle("Log Hours")
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

// MARK: - Local Service Row

private struct Mac_LocalServiceRow: View {
    let service: LocalService
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(service.notes)
                Spacer()
                Text("\(service.hours, specifier: "%.1f") hrs").foregroundStyle(.secondary)
            }
            HStack {
                Text(service.date).font(.caption).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text(service.description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
