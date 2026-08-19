//
//  Community Service.swift
//  School Notes
//

import SwiftUI
import SwiftSoup
import FirebaseFirestore
import MessageUI

private let signingBaseURL = "https://oakwoodstudents-d9495.web.app/sign"

// MARK: - ServiceView

struct ServiceView: View {
    @EnvironmentObject var appInfo: AppInfo
    @State private var servicesByYear: [String: [Service]] = [:]
    @State private var forms: [SubmittedForm] = []
    @State private var totalHours: Double = 0
    @State private var showPDF = false
    @State private var showPDFShare = false
    @State private var pdfShareFileURL: URL? = nil
    @State private var isPreparingPDFShare = false
    @State private var showAddSheet = false
    @State private var showCreateForm = false
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var listener: ListenerRegistration?

    var pdfURL: URL? { appInfo.personPK.flatMap { URL(string: "https://documents.veracross.com/oakwood/volunteer_hours/\($0).pdf") } }
    var htmlURL: URL? { appInfo.personPK.flatMap { URL(string: "https://documents.veracross.com/oakwood/volunteer_hours/\($0).html") } }
    var selectedTotalHours: Double { appInfo.localServices.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.hours } }
    var sortedYears: [String] { servicesByYear.keys.sorted().reversed() }

    /// Maps a scraped Veracross row's real id back to the rich submitted-form entry that created it
    /// (if it came through our app at all — pre-existing/manually-entered Veracross hours won't match).
    var veracrossIdToFormService: [Int: (form: SubmittedForm, service: LocalService)] {
        var map: [Int: (form: SubmittedForm, service: LocalService)] = [:]
        for form in forms {
            for service in form.services {
                if let id = service.veracrossRecordId { map[id] = (form, service) }
            }
        }
        return map
    }

    /// Every veracrossId actually present in the scraped Veracross data right now.
    private var scrapedVeracrossIds: Set<Int> {
        Set(servicesByYear.values.flatMap { $0 }.compactMap { $0.veracrossId })
    }

    /// Once an approved form's hours actually show up for real in Veracross (via the
    /// veracrossRecordId the advisor extension writes back on approval), it's redundant to
    /// keep showing the tracking form separately — the year-grouped Veracross section below
    /// already surfaces it (still linked back to this same form via veracrossIdToFormService).
    private var visibleForms: [SubmittedForm] {
        forms.filter { form in
            !(form.status == "approved" && form.services.contains { $0.veracrossRecordId.map(scrapedVeracrossIds.contains) ?? false })
        }
    }

    /// Past outside-service (title, organization, tax ID) combos, most recent first —
    /// tax IDs are the actual pain point to retype/remember, and this is where they're
    /// entered (once per form, only for outside service), so suggestions live here.
    var outsideServiceSuggestions: [OutsideServiceSuggestion] {
        var seen = Set<String>()
        var results: [OutsideServiceSuggestion] = []
        for form in forms.sorted(by: { $0.submittedAt > $1.submittedAt }) where !form.taxID.isEmpty {
            let suggestion = OutsideServiceSuggestion(title: form.title, organization: form.organization, taxID: form.taxID)
            guard seen.insert(suggestion.id).inserted else { continue }
            results.append(suggestion)
        }
        return Array(results.prefix(6))
    }

    var body: some View {
        List {
                // Logged (pending) hours
                if !appInfo.localServices.isEmpty {
                    Section {
                        ForEach(appInfo.localServices) { service in
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
                if !visibleForms.isEmpty {
                    Section("Forms") {
                        ForEach(visibleForms) { form in
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
                            if let match = veracrossIdToFormService[service.veracrossId ?? -1] {
                                NavigationLink(destination: ServiceFormDetailView(form: match.form)) {
                                    VeracrossServiceRow(service: service)
                                }
                            } else {
                                VeracrossServiceRow(service: service)
                            }
                        }
                    }
                }
            }
            .refreshable { await loadServiceHours() }
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
                AddServiceSheet()
            }
            .sheet(isPresented: $showCreateForm) {
                CreateFormSheet(
                    selectedServices: appInfo.localServices.filter { selectedIDs.contains($0.id) },
                    studentId: appInfo.googleVM.userEmail,
                    studentName: appInfo.googleVM.userName,
                    personPK: appInfo.personPK,
                    outsideServiceSuggestions: outsideServiceSuggestions
                ) { newForm in
                    appInfo.localServices.removeAll { selectedIDs.contains($0.id) }
                    selectedIDs.removeAll(); isSelecting = false
                    forms.insert(newForm, at: 0)
                }
            }
            .sheet(isPresented: $showPDF) {
                NavigationStack {
                    PDFViewer(url: pdfURL ?? URL(string: "about:blank")!, appInfo: appInfo)
                        .navigationTitle("Service Record")
                        .inlineNavigationBarTitle()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    guard let pdfURL else { return }
                                    isPreparingPDFShare = true
                                    Task {
                                        pdfShareFileURL = await downloadPDFForSharing(url: pdfURL, appInfo: appInfo)
                                        isPreparingPDFShare = false
                                        if pdfShareFileURL != nil { showPDFShare = true }
                                    }
                                } label: {
                                    if isPreparingPDFShare { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
                                }
                                .disabled(pdfURL == nil || isPreparingPDFShare)
                            }
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showPDF = false } }
                        }
                        .sheet(isPresented: $showPDFShare) {
                            if let pdfShareFileURL { ShareSheet(items: [pdfShareFileURL]) }
                        }
                }
            }
            .onAppear {
                Task { await loadServiceHours() }
                startListening()
            }
            .onDisappear { listener?.remove() }
            .onChange(of: appInfo.googleVM.userEmail) { _, _ in
                // Google sign-in restores asynchronously on cold launch (see loadGoogleLogin()),
                // so userEmail can still be empty when onAppear's startListening() first runs —
                // re-attach once it actually becomes available instead of listening forever.
                startListening()
            }
    }

    private func toggleSelection(_ s: LocalService) {
        if selectedIDs.contains(s.id) { selectedIDs.remove(s.id) } else { selectedIDs.insert(s.id) }
    }

    private func deleteEntry(_ s: LocalService) {
        appInfo.localServices.removeAll { $0.id == s.id }
    }

    private func startListening() {
        guard !appInfo.googleVM.userEmail.isEmpty else { return }
        listener?.remove()
        listener = FirebaseService.shared.listenForFormUpdates(studentId: appInfo.googleVM.userEmail) { updated in
            forms = updated
        }
    }
}

// MARK: - ServiceFormDetailView

struct ServiceFormDetailView: View {
    @State var form: SubmittedForm
    @State private var isSubmitting = false
    @State private var showMail = false
    @State private var showEditResubmit = false

    var signingURL: String { "\(signingBaseURL)/\(form.id)" }
    var mailData: MailData { makeSigningMailData(to: form.supervisorEmail, supervisorName: form.supervisorName, studentName: "", title: form.title, totalHours: form.totalHours, signingURL: signingURL) }

    var body: some View {
        List {
            Section {
                HStack { Text("Status"); Spacer(); ServiceStatusBadge(status: form.status) }
                HStack { Text("Total Hours"); Spacer(); Text("\(form.totalHours, specifier: "%.1f")").foregroundColor(.secondary) }
                HStack { Text("Supervisor"); Spacer(); Text(form.supervisorName).foregroundColor(.secondary) }
                HStack { Text("Supervisor Email"); Spacer(); Text(form.supervisorEmail).foregroundColor(.secondary) }
                if !form.supervisorSignature.isEmpty {
                    HStack {
                        Text("Signed by"); Spacer()
                        Text(form.supervisorSignature).foregroundColor(.secondary)
                        MatchIndicator(matches: looselyMatches(form.supervisorSignature, form.supervisorName))
                    }
                }
                if !form.signerEmail.isEmpty {
                    HStack {
                        Text("Signer Email"); Spacer()
                        Text(form.signerEmail).foregroundColor(.secondary)
                        MatchIndicator(matches: looselyMatches(form.signerEmail, form.supervisorEmail))
                    }
                }
                if let signedAt = form.signedAt {
                    HStack { Text("Signed"); Spacer(); Text(signedAt, style: .date).foregroundColor(.secondary) }
                }
                if form.signatureImageBase64 != nil {
                    SignatureImageView(base64: form.signatureImageBase64)
                        .frame(height: 80)
                        .frame(maxWidth: .infinity)
                }
                if form.status == "rejected" && !form.rejectionReason.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reason").font(.caption).foregroundColor(.secondary)
                        Text(form.rejectionReason)
                    }
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
                            await MainActor.run { form.status = "pending"; isSubmitting = false }
                        }
                    } label: {
                        if isSubmitting { ProgressView() }
                        else { Label("Submit to Advisor", systemImage: "paperplane.fill") }
                    }
                    .disabled(isSubmitting)
                case "approved":
                    Label("Approved by your advisor", systemImage: "checkmark.seal.fill")
                        .foregroundColor(.secondary)
                case "rejected":
                    Button { showEditResubmit = true } label: {
                        Label("Edit & Resubmit", systemImage: "pencil.circle")
                    }
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

            if !form.slos.isEmpty || !form.reflection1.isEmpty || !form.reflection2.isEmpty || !form.reflection3.isEmpty {
                Section("Reflections") {
                    if !form.slos.isEmpty { reflectionRow("Schoolwide Learner Objectives", form.slos.joined(separator: ", ")) }
                    if !form.reflection1.isEmpty { reflectionRow("How did your service incorporate the SLO(s) noted above?", form.reflection1) }
                    if !form.reflection2.isEmpty { reflectionRow("How did your service contribute to your community?", form.reflection2) }
                    if !form.reflection3.isEmpty { reflectionRow("Did this service connect to or enhance your academic goals or interests?", form.reflection3) }
                }
            }
        }
        .navigationTitle(form.title)
        .largeNavigationBarTitle()
        .sheet(isPresented: $showMail) {
            MailComposerView(data: mailData, isPresented: $showMail)
        }
        .sheet(isPresented: $showEditResubmit) {
            EditAndResubmitSheet(form: form) { updated in
                form = updated
            }
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
    let personPK: Int?
    var outsideServiceSuggestions: [OutsideServiceSuggestion] = []
    var onSuccess: (SubmittedForm) -> Void

    @State private var title = ""
    @State private var supervisorName = ""
    @State private var supervisorEmail = ""
    @State private var advisorName = ""
    @State private var selectedSLOs: Set<String> = []
    @State private var reflection1 = ""
    @State private var reflection2 = ""
    @State private var reflection3 = ""
    @State private var taxID = ""
    @State private var organization = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showMail = false
    @State private var pendingMailData: MailData? = nil

    var hasOutsideService: Bool { selectedServices.contains { $0.description == "Outside Community Service" } }
    var totalHours: Double { selectedServices.reduce(0) { $0 + $1.hours } }
    var canSubmit: Bool {
        !title.isEmpty && !supervisorName.isEmpty && !supervisorEmail.isEmpty &&
        !advisorName.isEmpty &&
        !selectedSLOs.isEmpty &&
        !reflection1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !reflection2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !reflection3.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!hasOutsideService || (!taxID.isEmpty && !organization.isEmpty))
    }

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

                Section("Advisor") {
                    if advisorList.isEmpty {
                        TextField("Advisor Name", text: $advisorName)
                    } else {
                        Picker("Advisor", selection: $advisorName) {
                            Text("Select…").tag("")
                            ForEach(advisorList, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }

                Section {
                    Text("How did your service recorded on this form incorporate the Schoolwide Learner Objectives (SLOs) of Oakwood High School?")
                        .font(.subheadline)
                    ForEach(slOptions, id: \.self) { slo in
                        Button {
                            if selectedSLOs.contains(slo) { selectedSLOs.remove(slo) } else { selectedSLOs.insert(slo) }
                        } label: {
                            HStack {
                                Image(systemName: selectedSLOs.contains(slo) ? "checkmark.square.fill" : "square")
                                Text(slo)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary)
                    }
                    TextField("How did your service incorporate the SLO(s) noted above?", text: $reflection1, axis: .vertical).lineLimit(3...6)
                } header: { Text("Student Reflection") }

                Section {
                    TextField("How did your service contribute to your community?", text: $reflection2, axis: .vertical).lineLimit(3...6)
                } header: { Text("Community Contribution") }

                Section {
                    TextField("Did this service connect to or enhance your academic goals or interests? If so, how?", text: $reflection3, axis: .vertical).lineLimit(3...6)
                } header: { Text("Academic Connection") }

                if hasOutsideService {
                    if !outsideServiceSuggestions.isEmpty {
                        Section("Use a Previous Entry") {
                            ForEach(outsideServiceSuggestions) { suggestion in
                                Button {
                                    title = suggestion.title
                                    organization = suggestion.organization
                                    taxID = suggestion.taxID
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.organization.isEmpty ? suggestion.title : suggestion.organization)
                                            .foregroundColor(.primary)
                                        Text("\(suggestion.title) · Tax ID \(suggestion.taxID)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        TextField("Organization Name", text: $organization)
                        TextField("Tax ID Number", text: $taxID)
                    } header: { Text("Organization Tax ID") }
                    footer: { Text("Required for outside community service hours. Tap a previous entry above to fill all three, or type your own.") }
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
                               slos: Array(selectedSLOs),
                               reflection1: reflection1, reflection2: reflection2, reflection3: reflection3,
                               taxID: hasOutsideService ? taxID : nil,
                               organization: hasOutsideService ? organization : nil)
        do {
            let docId = try await FirebaseService.shared.submitServiceForm(
                form, studentId: studentId, studentName: studentName, personPK: personPK,
                supervisorName: supervisorName, supervisorEmail: supervisorEmail, advisorName: advisorName)

            let submittedForm = SubmittedForm(
                id: docId, title: title, personPK: personPK, status: "pending_signature", submittedAt: Date(),
                totalHours: totalHours, slos: Array(selectedSLOs), reflection1: reflection1, reflection2: reflection2,
                reflection3: reflection3, taxID: hasOutsideService ? taxID : "",
                organization: hasOutsideService ? organization : "",
                services: selectedServices, supervisorName: supervisorName,
                supervisorEmail: supervisorEmail, advisorName: advisorName, supervisorSignature: "", signerEmail: "", signatureImageBase64: nil,
                signedAt: nil, rejectionReason: "")

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

// MARK: - EditAndResubmitSheet

/// Lets a student fix a rejected form's fields (including individual service entries) and
/// resubmit it. Resubmitting restarts the signing cycle — the same Firestore doc is reset to
/// "pending_signature" and a fresh signing email goes out to the supervisor.
struct EditAndResubmitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appInfo: AppInfo
    let form: SubmittedForm
    var outsideServiceSuggestions: [OutsideServiceSuggestion] = []
    var onSuccess: (SubmittedForm) -> Void

    @State private var title: String
    @State private var supervisorName: String
    @State private var supervisorEmail: String
    @State private var advisorName: String
    @State private var selectedSLOs: Set<String>
    @State private var reflection1: String
    @State private var reflection2: String
    @State private var reflection3: String
    @State private var taxID: String
    @State private var organization: String
    @State private var services: [LocalService]
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showMail = false
    @State private var pendingMailData: MailData? = nil

    init(form: SubmittedForm, outsideServiceSuggestions: [OutsideServiceSuggestion] = [], onSuccess: @escaping (SubmittedForm) -> Void) {
        self.form = form
        self.outsideServiceSuggestions = outsideServiceSuggestions
        self.onSuccess = onSuccess
        _title = State(initialValue: form.title)
        _supervisorName = State(initialValue: form.supervisorName)
        _supervisorEmail = State(initialValue: form.supervisorEmail)
        _advisorName = State(initialValue: form.advisorName)
        _selectedSLOs = State(initialValue: Set(form.slos))
        _reflection1 = State(initialValue: form.reflection1)
        _reflection2 = State(initialValue: form.reflection2)
        _reflection3 = State(initialValue: form.reflection3)
        _taxID = State(initialValue: form.taxID)
        _organization = State(initialValue: form.organization)
        _services = State(initialValue: form.services)
    }

    var hasOutsideService: Bool { services.contains { $0.description == "Outside Community Service" } }
    var totalHours: Double { services.reduce(0) { $0 + $1.hours } }
    var canSubmit: Bool {
        !title.isEmpty && !supervisorName.isEmpty && !supervisorEmail.isEmpty && !services.isEmpty &&
        !advisorName.isEmpty &&
        !selectedSLOs.isEmpty &&
        !reflection1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !reflection2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !reflection3.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!hasOutsideService || (!taxID.isEmpty && !organization.isEmpty))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Form Details") {
                    TextField("Title (e.g. Food Bank Volunteering)", text: $title)
                    HStack {
                        Text("Entries"); Spacer()
                        Text("\(services.count)").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Total Hours"); Spacer()
                        Text("\(totalHours, specifier: "%.1f")").foregroundColor(.secondary)
                    }
                }

                Section {
                    ForEach(services.indices, id: \.self) { index in
                        EditableServiceEntryRow(service: $services[index])
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { services.remove(at: index) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                } header: { Text("Service Entries") } footer: {
                    if services.isEmpty { Text("At least one service entry is required.").foregroundColor(.red) }
                }

                Section {
                    TextField("Supervisor Full Name", text: $supervisorName)
                    TextField("Supervisor Email", text: $supervisorEmail)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                } header: { Text("Supervisor") } footer: {
                    Text("They'll receive a fresh email with a link to review and re-sign the form.")
                }

                Section("Advisor") {
                    if advisorList.isEmpty {
                        TextField("Advisor Name", text: $advisorName)
                    } else {
                        Picker("Advisor", selection: $advisorName) {
                            Text("Select…").tag("")
                            ForEach(advisorList, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }

                Section {
                    Text("How did your service recorded on this form incorporate the Schoolwide Learner Objectives (SLOs) of Oakwood High School?")
                        .font(.subheadline)
                    ForEach(slOptions, id: \.self) { slo in
                        Button {
                            if selectedSLOs.contains(slo) { selectedSLOs.remove(slo) } else { selectedSLOs.insert(slo) }
                        } label: {
                            HStack {
                                Image(systemName: selectedSLOs.contains(slo) ? "checkmark.square.fill" : "square")
                                Text(slo)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.primary)
                    }
                    TextField("How did your service incorporate the SLO(s) noted above?", text: $reflection1, axis: .vertical).lineLimit(3...6)
                } header: { Text("Student Reflection") }

                Section {
                    TextField("How did your service contribute to your community?", text: $reflection2, axis: .vertical).lineLimit(3...6)
                } header: { Text("Community Contribution") }

                Section {
                    TextField("Did this service connect to or enhance your academic goals or interests? If so, how?", text: $reflection3, axis: .vertical).lineLimit(3...6)
                } header: { Text("Academic Connection") }

                if hasOutsideService {
                    if !outsideServiceSuggestions.isEmpty {
                        Section("Use a Previous Entry") {
                            ForEach(outsideServiceSuggestions) { suggestion in
                                Button {
                                    organization = suggestion.organization
                                    taxID = suggestion.taxID
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.organization.isEmpty ? suggestion.title : suggestion.organization)
                                            .foregroundColor(.primary)
                                        Text("\(suggestion.title) · Tax ID \(suggestion.taxID)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        TextField("Organization Name", text: $organization)
                        TextField("Tax ID Number", text: $taxID)
                    } header: { Text("Organization Tax ID") }
                    footer: { Text("Required for outside community service hours. Tap a previous entry above to fill both, or type your own.") }
                }

                if let error = errorMessage {
                    Section { Text(error).foregroundColor(.red) }
                }
            }
            .navigationTitle("Edit & Resubmit")
            .inlineNavigationBarTitle()
            .sheet(isPresented: $showMail, onDismiss: { dismiss() }) {
                if let data = pendingMailData { MailComposerView(data: data, isPresented: $showMail) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await submit() } } label: {
                        if isSubmitting { ProgressView() } else { Text("Resubmit") }
                    }
                    .disabled(!canSubmit || isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true; errorMessage = nil
        let updatedForm = ServiceForm(title: title, dateCreated: form.submittedAt, services: services,
                               slos: Array(selectedSLOs),
                               reflection1: reflection1, reflection2: reflection2, reflection3: reflection3,
                               taxID: hasOutsideService ? taxID : nil,
                               organization: hasOutsideService ? organization : nil)
        do {
            try await FirebaseService.shared.resubmitServiceForm(
                formId: form.id, form: updatedForm,
                supervisorName: supervisorName, supervisorEmail: supervisorEmail, advisorName: advisorName)

            var resubmittedForm = form
            resubmittedForm.title = title
            resubmittedForm.totalHours = totalHours
            resubmittedForm.slos = Array(selectedSLOs)
            resubmittedForm.reflection1 = reflection1
            resubmittedForm.reflection2 = reflection2
            resubmittedForm.reflection3 = reflection3
            resubmittedForm.taxID = hasOutsideService ? taxID : ""
            resubmittedForm.organization = hasOutsideService ? organization : ""
            resubmittedForm.services = services
            resubmittedForm.supervisorName = supervisorName
            resubmittedForm.supervisorEmail = supervisorEmail
            resubmittedForm.advisorName = advisorName
            resubmittedForm.status = "pending_signature"
            resubmittedForm.rejectionReason = ""
            resubmittedForm.supervisorSignature = ""
            resubmittedForm.signerEmail = ""
            resubmittedForm.signatureImageBase64 = nil
            resubmittedForm.signedAt = nil

            let mailData = makeSigningMailData(to: supervisorEmail, supervisorName: supervisorName,
                studentName: appInfo.googleVM.userName, title: title, totalHours: totalHours,
                signingURL: "\(signingBaseURL)/\(form.id)")

            await MainActor.run {
                onSuccess(resubmittedForm)
                if MFMailComposeViewController.canSendMail() {
                    pendingMailData = mailData
                    showMail = true
                } else {
                    dismiss()
                }
            }
        } catch {
            await MainActor.run { errorMessage = "Failed to resubmit form: \(error.localizedDescription)"; isSubmitting = false }
        }
    }
}

// MARK: - EditableServiceEntryRow

/// Simple per-row editable fields for a service entry — used by EditAndResubmitSheet so a
/// rejected form's individual date/hours/description/notes can be fixed before resubmitting.
struct EditableServiceEntryRow: View {
    @Binding var service: LocalService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Activity / Notes", text: $service.notes)
            TextField("Type (e.g. Outside Community Service)", text: $service.description)
            HStack {
                TextField("Date (MM/dd/yyyy)", text: $service.date)
                Spacer()
                TextField("Hours", value: $service.hours, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Mail Composer

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
    @EnvironmentObject var appInfo: AppInfo
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
                        appInfo.localServices.append(LocalService(date: f.string(from: date), description: description,
                                                      notes: notes, hours: Double(hours) ?? 0))
                        dismiss()
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

// MARK: - VeracrossServiceRow

struct VeracrossServiceRow: View {
    let service: Service
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

// MARK: - Data Models


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
                let rowClass = (try? row.className()) ?? ""
                let veracrossId = rowClass.range(of: #"row_(\d+)"#, options: .regularExpression)
                    .flatMap { Int(rowClass[$0].dropFirst("row_".count)) }
                let s = Service(
                    date: (try? row.select("td.volunteer_date").text()) ?? "",
                    description: (try? row.select("td.description").text()) ?? "",
                    notes: (try? row.select("td.notes").text()) ?? "",
                    hours: Double((try? row.select("td.volunteer_hours").text()) ?? "") ?? 0,
                    schoolYear: year,
                    veracrossId: veracrossId)
                grouped[year, default: []].append(s)
            }
        }
        await MainActor.run { servicesByYear = grouped }
    }
}
