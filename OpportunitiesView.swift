import SwiftUI
import CoreData

struct OpportunitiesView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Deal.closeDate, ascending: true)], animation: .default)
    private var opportunities: FetchedResults<Deal>

    @State private var showingAddOpportunity = false
    @State private var opportunityToEdit: Deal? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(opportunities, id: \.objectID) { opportunity in
                    Button {
                        opportunityToEdit = opportunity
                    } label: {
                        VStack(alignment: .leading) {
                            Text(opportunity.name ?? "Untitled")
                                .font(.headline)
                            if let date = opportunity.closeDate {
                                Text(date, formatter: dateFormatter)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            if let companyName = opportunity.company?.name, !companyName.isEmpty {
                                Text("Company: \(companyName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteOpportunities)
            }
            .onAppear {
                dedupeDealsIfNeeded()
            }
            .navigationTitle("Opportunities")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddOpportunity = true
                    }) {
                        Label("Add Opportunity", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddOpportunity) {
                DealFormSheet()
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(item: $opportunityToEdit) { opportunity in
                DealFormSheet(deal: opportunity)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
    }

    private func deleteOpportunities(offsets: IndexSet) {
        withAnimation {
            offsets.map { opportunities[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                print("Delete error: \(error)")
            }
        }
    }

    /// Defensive cleanup: if multiple Deal rows share the same external `id`,
    /// keep the newest and merge relationships + missing scalar fields.
    private func dedupeDealsIfNeeded() {
        let fetch = NSFetchRequest<Deal>(entityName: "Deal")
        // Only deals that actually have an external id
        fetch.predicate = NSPredicate(format: "id != nil AND id != ''")

        do {
            let all = try viewContext.fetch(fetch)
            let grouped = Dictionary(grouping: all) { ($0.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.key.isEmpty }

            var didDelete = false

            for (_, deals) in grouped {
                guard deals.count > 1 else { continue }

                // Keep the most recently updated/created deal
                let sorted = deals.sorted {
                    let aTime = ($0.updatedAt ?? $0.createdAt ?? .distantPast)
                    let bTime = ($1.updatedAt ?? $1.createdAt ?? .distantPast)
                    return aTime > bTime
                }

                guard let keeper = sorted.first else { continue }
                let duplicates = sorted.dropFirst()

                for dup in duplicates {
                    // Merge scalar fields if keeper is missing
                    if (keeper.name ?? "").isEmpty { keeper.name = dup.name }
                    if (keeper.stage ?? "").isEmpty { keeper.stage = dup.stage }
                    if keeper.amount == nil { keeper.amount = dup.amount }
                    if keeper.closeDate == nil { keeper.closeDate = dup.closeDate }

                    // Prefer company if keeper doesn't have one
                    if keeper.company == nil, let c = dup.company { keeper.company = c }

                    // Union contacts relationship
                    let keeperContacts = (keeper.contacts as? Set<Contact>) ?? []
                    let dupContacts = (dup.contacts as? Set<Contact>) ?? []
                    if !dupContacts.isEmpty {
                        keeper.contacts = NSSet(set: keeperContacts.union(dupContacts))
                    }

                    viewContext.delete(dup)
                    didDelete = true
                }
            }

            if didDelete {
                try viewContext.save()
                print("[OpportunitiesView] ✅ De-duped duplicate Deal rows by id")
            }
        } catch {
            print("[OpportunitiesView] De-dupe error: \(error)")
        }
    }
}

struct DealFormSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)], animation: .default)
    private var companies: FetchedResults<Company>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(key: "lastName", ascending: true),
        NSSortDescriptor(key: "firstName", ascending: true)
    ], animation: .default)
    private var contacts: FetchedResults<Contact>

    @State private var name: String = ""
    @State private var stage: String = ""
    @State private var amountText: String = ""
    @State private var date: Date = Date()
    @State private var selectedCompany: Company? = nil
    @State private var selectedContact: Contact? = nil
    @State private var contactSearchText: String = ""
    @State private var showingContactPicker = false

    private let hubSpotStages: [(key: String, label: String)] = [
        ("appointmentscheduled", "Appointment Scheduled"),
        ("qualifiedtobuy", "Qualified to Buy"),
        ("presentation scheduled", "Presentation Scheduled"),
        ("decisionmaker bought-in", "Decision Maker Bought-In"),
        ("contract sent", "Contract Sent"),
        ("closedwon", "Closed Won"),
        ("closedlost", "Closed Lost")
    ]

    private var deal: Deal?

    init(deal: Deal? = nil) {
        self.deal = deal
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Opportunity Details")) {
                    TextField("Name", text: $name)
                    Picker("Stage", selection: $stage) {
                        ForEach(hubSpotStages, id: \.key) { stage in
                            Text(stage.label).tag(stage.key)
                        }
                    }
                    HStack {
                        Text("$")
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .onChange(of: amountText) { oldValue, newValue in
                                let filtered = newValue.filter { "0123456789.".contains($0) }
                                if filtered != newValue {
                                    amountText = filtered
                                }
                            }
                    }
                    DatePicker("Close Date", selection: $date, displayedComponents: .date)
                }
                Section(header: Text("Company")) {
                    Picker("Select Company", selection: $selectedCompany) {
                        Text("None").tag(Company?.none)
                        ForEach(companies, id: \.objectID) { company in
                            Text(company.name ?? "Unknown").tag(Company?.some(company))
                        }
                    }
                }
                Section(header: Text("Primary Contact")) {
                    Button {
                        showingContactPicker.toggle()
                    } label: {
                        HStack {
                            Text("Select Primary Contact")
                            Spacer()
                            Text((selectedContact?.firstName ?? "") + (selectedContact?.lastName != nil ? " " + (selectedContact?.lastName ?? "") : ""))
                                .foregroundColor(selectedContact == nil ? .secondary : .primary)
                        }
                    }
                }
            }
            .navigationTitle(deal == nil ? "New Opportunity" : "Edit Opportunity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDeal()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showingContactPicker) {
                NavigationStack {
                    List {
                        ForEach(contacts.filter { contactSearchText.isEmpty ? true :
                            (contactMatchesSearch(contact: $0)) }, id: \.objectID) { contact in
                            Button(action: {
                                selectedContact = contact
                                showingContactPicker = false
                            }) {
                                VStack(alignment: .leading) {
                                    Text("\(contact.firstName ?? "") \(contact.lastName ?? "")")
                                    if let companyName = contact.company?.name, !companyName.isEmpty {
                                        Text("Company: \(companyName)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $contactSearchText)
                    .navigationTitle("Select Contact")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingContactPicker = false
                            }
                        }
                    }
                }
            }
            .onAppear {
                if let deal = deal {
                    name = deal.name ?? ""
                    stage = deal.stage ?? ""
                    if let amount = deal.amount {
                        amountText = amount.stringValue
                    } else {
                        amountText = ""
                    }
                    date = deal.closeDate ?? Date()
                    selectedCompany = deal.company
                    if let contactsSet = deal.contacts as? Set<Contact>, let firstContact = contactsSet.first {
                        selectedContact = firstContact
                    }
                }
            }
        }
    }

    private func contactMatchesSearch(contact: Contact) -> Bool {
        let search = contactSearchText.lowercased()
        let firstName = contact.firstName?.lowercased() ?? ""
        let lastName = contact.lastName?.lowercased() ?? ""
        return firstName.contains(search) || lastName.contains(search)
    }

    private func saveDeal() {
        let dealToSave = deal ?? Deal(context: viewContext)

        // Ensure every deal has a stable id.
        // Imported HubSpot deals should already set `id` in their import/upsert path.
        // For manual deals created here, generate a local id.
        if dealToSave.id == nil || (dealToSave.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dealToSave.id = "local-\(UUID().uuidString)"
        }

        dealToSave.name = name
        dealToSave.stage = stage.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = NSDecimalNumber(string: amountText)
        if parsed == NSDecimalNumber.notANumber {
            dealToSave.amount = nil
        } else {
            dealToSave.amount = parsed
        }
        dealToSave.closeDate = date
        dealToSave.company = selectedCompany

        if let contact = selectedContact {
            dealToSave.contacts = NSSet(object: contact)
        } else {
            dealToSave.contacts = NSSet()
        }

        do {
            try viewContext.save()
        } catch {
            // Handle the error appropriately in a real app
            print("Error saving deal: \(error.localizedDescription)")
        }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter
}()
