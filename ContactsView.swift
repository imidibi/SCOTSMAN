import SwiftUI
import CoreData

struct ContactsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        entity: Contact.entity(),
        sortDescriptors: [
            NSSortDescriptor(key: "lastName", ascending: true),
            NSSortDescriptor(key: "firstName", ascending: true)
        ]
    ) private var contacts: FetchedResults<Contact>
    
    @State private var showingAddContactSheet = false
    @State private var contactToEdit: Contact? = nil
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(contacts, id: \.objectID) { contact in
                    Button {
                        contactToEdit = contact
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            let fullName = "\(contact.firstName ?? "") \(contact.lastName ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
                            Text(fullName.isEmpty ? "Unnamed" : fullName)
                                .font(.headline)
                            if let email = contact.email, !email.isEmpty {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else if let phone = contact.phone, !phone.isEmpty {
                                Text(phone)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
                .onDelete(perform: deleteContacts)
            }
            .onAppear { dedupeContactsIfNeeded() }
            .navigationTitle("Contacts")
            .toolbar {
                Button(action: {
                    showingAddContactSheet.toggle()
                }) {
                    Label("Add Contact", systemImage: "plus")
                }
            }
            .sheet(isPresented: $showingAddContactSheet) {
                ContactFormSheet(contact: nil)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(item: $contactToEdit) { contact in
                ContactFormSheet(contact: contact)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
    }
    
    private func dedupeContactsIfNeeded() {
        // De-dupe by Contact.id (HubSpot/contact unique id). Keep newest, merge fields + relationships.
        let fetch = NSFetchRequest<Contact>(entityName: "Contact")
        fetch.returnsObjectsAsFaults = false

        do {
            let all = try viewContext.fetch(fetch)

            // Group by non-empty id
            var groups: [String: [Contact]] = [:]
            for c in all {
                let raw = (c.value(forKey: "id") as? String) ?? ""
                let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                groups[key, default: []].append(c)
            }

            var didChange = false

            func dateValue(_ obj: NSManagedObject, _ key: String) -> Date {
                return (obj.value(forKey: key) as? Date) ?? .distantPast
            }

            func strValue(_ obj: NSManagedObject, _ key: String) -> String {
                return ((obj.value(forKey: key) as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }

            for (_, arr) in groups {
                guard arr.count > 1 else { continue }

                // Keep the newest by updatedAt, fallback createdAt
                let sorted = arr.sorted {
                    let aU = dateValue($0, "updatedAt")
                    let bU = dateValue($1, "updatedAt")
                    if aU != bU { return aU > bU }
                    let aC = dateValue($0, "createdAt")
                    let bC = dateValue($1, "createdAt")
                    return aC > bC
                }

                guard let keep = sorted.first else { continue }
                let dups = sorted.dropFirst()

                // Prefer missing scalar fields from dups
                let scalarKeys = ["firstName", "lastName", "email", "phone"]
                for key in scalarKeys {
                    let keepVal = strValue(keep, key)
                    if keepVal.isEmpty {
                        for d in dups {
                            let dv = strValue(d, key)
                            if !dv.isEmpty {
                                keep.setValue(dv, forKey: key)
                                didChange = true
                                break
                            }
                        }
                    }
                }

                // Merge company relationship (prefer keep.company, else take first non-nil)
                if keep.value(forKey: "company") == nil {
                    for d in dups {
                        if let comp = d.value(forKey: "company") {
                            keep.setValue(comp, forKey: "company")
                            didChange = true
                            break
                        }
                    }
                }

                // Merge deals relationship (union)
                let keepDeals = (keep.value(forKey: "deals") as? Set<NSManagedObject>) ?? []
                var mergedDeals = keepDeals
                for d in dups {
                    let dDeals = (d.value(forKey: "deals") as? Set<NSManagedObject>) ?? []
                    mergedDeals.formUnion(dDeals)
                }
                if mergedDeals.count != keepDeals.count {
                    keep.setValue(mergedDeals as NSSet, forKey: "deals")
                    didChange = true
                }

                // Delete duplicates
                for d in dups {
                    viewContext.delete(d)
                    didChange = true
                }
            }

            if didChange {
                try viewContext.save()
            }
        } catch {
            print("[ContactsView] dedupe error: \(error)")
        }
    }
    
    private func deleteContacts(at offsets: IndexSet) {
        withAnimation {
            offsets.map { contacts[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                print("Delete error: \(error)")
            }
        }
    }
}

struct ContactFormSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    var contact: Contact? = nil
    
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: .default)
    private var companies: FetchedResults<Company>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
        animation: .default)
    private var opportunities: FetchedResults<Deal>
    
    @State private var selectedCompany: Company? = nil
    @State private var selectedOpportunities: Set<Deal> = []
    
    init(contact: Contact? = nil) {
        self.contact = contact
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Contact Info")) {
                    TextField("First Name", text: $firstName)
                        .autocapitalization(.words)
                    TextField("Last Name", text: $lastName)
                        .autocapitalization(.words)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Phone Number", text: $phone)
                        .keyboardType(.phonePad)
                }
                
                Section(header: Text("Company")) {
                    Picker("Select Company", selection: $selectedCompany) {
                        Text("None").tag(Company?.none)
                        ForEach(companies, id: \.objectID) { company in
                            Text(company.name ?? "Unknown").tag(Company?.some(company))
                        }
                    }
                }
                
                Section(header: Text("Opportunities")) {
                    if opportunities.isEmpty {
                        Text("No Opportunities Available").foregroundColor(.secondary)
                    } else {
                        List(opportunities, id: \.objectID, selection: $selectedOpportunities) { deal in
                            Text(deal.name ?? "Unnamed Deal")
                        }
                        .environment(\.editMode, .constant(EditMode.active))
                        .frame(minHeight: 150)
                    }
                }
            }
            .navigationTitle(contact == nil ? "New Contact" : "Edit Contact")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Ensure every Contact has a stable unique id.
                        // - For HubSpot-imported contacts, this should already be the HubSpot contact id.
                        // - For manually-created contacts, generate a UUID.
                        let incomingIdRaw = (contact?.value(forKey: "id") as? String) ?? ""
                        var effectiveId = incomingIdRaw.trimmingCharacters(in: .whitespacesAndNewlines)

                        if effectiveId.isEmpty {
                            // Prefix to avoid ever colliding with HubSpot numeric IDs
                            effectiveId = "local-\(UUID().uuidString)"
                        }

                        // Upsert: if another Contact already exists with this id, update it instead of creating a duplicate.
                        let existingFetch = NSFetchRequest<Contact>(entityName: "Contact")
                        existingFetch.predicate = NSPredicate(format: "id == %@", effectiveId)
                        existingFetch.fetchLimit = 2

                        let existingMatches = (try? viewContext.fetch(existingFetch)) ?? []
                        let existing = existingMatches.first(where: { $0.objectID != contact?.objectID })

                        let contactToSave = contact ?? existing ?? Contact(context: viewContext)
                        // Maintain timestamps
                        if contactToSave.createdAt == nil {
                            contactToSave.createdAt = Date()
                        }
                        contactToSave.updatedAt = Date()
                        contactToSave.setValue(effectiveId, forKey: "id")
                        
                        contactToSave.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                        contactToSave.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
                        contactToSave.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
                        contactToSave.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                        // NOTE: address fields live on Company (not Contact) in this model.
                        
                        contactToSave.company = selectedCompany
                        
                        if let currentDeals = contactToSave.deals as? Set<Deal> {
                            currentDeals.forEach { contactToSave.removeFromDeals($0) }
                        }
                        selectedOpportunities.forEach { contactToSave.addToDeals($0) }
                        
                        do {
                            try viewContext.save()
                            dismiss()
                        } catch {
                            // Handle the error appropriately in a real app
                            print("Failed to save contact: \(error.localizedDescription)")
                        }
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let contact = contact {
                    firstName = contact.firstName ?? ""
                    lastName = contact.lastName ?? ""
                    email = contact.email ?? ""
                    phone = contact.phone ?? ""
                    selectedCompany = contact.company
                    if let deals = contact.deals as? Set<Deal> {
                        selectedOpportunities = deals
                    } else {
                        selectedOpportunities = []
                    }
                } else {
                    firstName = ""
                    lastName = ""
                    email = ""
                    phone = ""
                    selectedCompany = nil
                    selectedOpportunities = []
                }
            }
        }
    }
}
