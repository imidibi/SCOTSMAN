import SwiftUI
import CoreData

struct CompaniesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Company.name, ascending: true)],
        animation: .default)
    private var companies: FetchedResults<Company>
    
    @State private var showingAddCompany = false
    @State private var companyToEdit: Company? = nil
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(companies, id: \Company.objectID) { company in
                    Button {
                        companyToEdit = company
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(company.name ?? "Unknown").font(.headline)
                            if let address = company.address, !address.isEmpty {
                                Text(address).font(.subheadline).foregroundColor(.secondary)
                            }
                            if let phone = company.phone, !phone.isEmpty {
                                Text("Phone: \(phone)").font(.subheadline).foregroundColor(.secondary)
                            }
                            if let website = company.website, !website.isEmpty {
                                Text("Website: \(website)").font(.subheadline).foregroundColor(.secondary)
                            }
                            let contactsSet = company.contacts as? Set<Contact> ?? []
                            if contactsSet.isEmpty {
                                Text("Contacts: None").font(.caption).foregroundColor(.secondary)
                            } else {
                                let contactNames = contactsSet.map { ( ($0.firstName ?? "") + " " + ($0.lastName ?? "") ).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.sorted()
                                let count = contactsSet.count
                                if count <= 3 {
                                    Text("Contacts (\(count)): \(contactNames.joined(separator: ", "))").font(.caption).foregroundColor(.secondary)
                                } else {
                                    let firstThree = contactNames.prefix(3).joined(separator: ", ")
                                    Text("Contacts (\(count)): \(firstThree), ...").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            let dealsSet = company.deals as? Set<Deal> ?? []
                            if dealsSet.isEmpty {
                                Text("Opportunities: None").font(.caption).foregroundColor(.secondary)
                            } else {
                                let dealNames = dealsSet.map { $0.name ?? "Unnamed" }.sorted()
                                let count = dealsSet.count
                                if count <= 3 {
                                    Text("Opportunities (\(count)): \(dealNames.joined(separator: ", "))").font(.caption).foregroundColor(.secondary)
                                } else {
                                    let firstThree = dealNames.prefix(3).joined(separator: ", ")
                                    Text("Opportunities (\(count)): \(firstThree), ...").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteCompanies)
            }
            .onAppear {
                dedupeCompaniesByHubSpotId()
                dedupeCompaniesWithoutIdByName()
            }
            .navigationTitle("Companies")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddCompany = true }) {
                        Label("Add Company", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddCompany) {
                CompanyFormSheet().environment(\.managedObjectContext, viewContext)
            }
            .sheet(item: $companyToEdit, onDismiss: { companyToEdit = nil }) { company in
                CompanyFormSheet(company: company)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
    }
    
    private func deleteCompanies(offsets: IndexSet) {
        withAnimation {
            offsets.map { companies[$0] }.forEach(viewContext.delete)
            
            do {
                try viewContext.save()
            } catch {
                // Handle the error appropriately in a production app
                print("Failed to delete company: \(error.localizedDescription)")
            }
        }
    }
    
    private func dedupeCompaniesByHubSpotId() {
        // If there are duplicate rows with the same `Company.id` (HubSpot id), SwiftUI/UI can misbehave.
        // Keep the most recently updated record and merge relationships/fields from duplicates.
        let req: NSFetchRequest<Company> = Company.fetchRequest()
        req.sortDescriptors = [
            NSSortDescriptor(keyPath: \Company.updatedAt, ascending: false),
            NSSortDescriptor(keyPath: \Company.createdAt, ascending: false)
        ]

        do {
            let all = try viewContext.fetch(req)
            var keeperById: [String: Company] = [:]
            var toDelete: [Company] = []

            for c in all {
                guard let hubId = c.id?.trimmingCharacters(in: .whitespacesAndNewlines), !hubId.isEmpty else {
                    continue
                }

                // Only de-dupe true HubSpot ids. Local ids are prefixed to avoid collisions.
                if hubId.hasPrefix("local-") {
                    continue
                }

                if let keeper = keeperById[hubId], keeper != c {
                    // Merge contacts (and ensure each contact points to keeper)
                    let dupContacts = (c.contacts as? Set<Contact>) ?? []
                    for contact in dupContacts {
                        keeper.addToContacts(contact)
                        // If your model uses an inverse relationship from Contact -> Company, set it.
                        // (Only do this if the relationship exists on Contact.)
                        if contact.responds(to: NSSelectorFromString("setCompany:")) {
                            contact.setValue(keeper, forKey: "company")
                        }
                    }

                    // Merge deals (and ensure each deal points to keeper)
                    let dupDeals = (c.deals as? Set<Deal>) ?? []
                    for deal in dupDeals {
                        keeper.addToDeals(deal)
                        if deal.responds(to: NSSelectorFromString("setCompany:")) {
                            deal.setValue(keeper, forKey: "company")
                        }
                    }

                    // Prefer non-empty scalar fields from the duplicate if keeper is missing them
                    if (keeper.name ?? "").isEmpty, let v = c.name, !v.isEmpty { keeper.name = v }
                    if (keeper.domain ?? "").isEmpty, let v = c.domain, !v.isEmpty { keeper.domain = v }
                    if (keeper.phone ?? "").isEmpty, let v = c.phone, !v.isEmpty { keeper.phone = v }
                    if (keeper.website ?? "").isEmpty, let v = c.website, !v.isEmpty { keeper.website = v }
                    if (keeper.address ?? "").isEmpty, let v = c.address, !v.isEmpty { keeper.address = v }
                    if (keeper.city ?? "").isEmpty, let v = c.city, !v.isEmpty { keeper.city = v }
                    if (keeper.state ?? "").isEmpty, let v = c.state, !v.isEmpty { keeper.state = v }
                    if (keeper.zipcode ?? "").isEmpty, let v = c.zipcode, !v.isEmpty { keeper.zipcode = v }
                    if (keeper.country ?? "").isEmpty, let v = c.country, !v.isEmpty { keeper.country = v }

                    // Keep the newest timestamps
                    if let dupUpdated = c.updatedAt {
                        if keeper.updatedAt == nil || dupUpdated > (keeper.updatedAt ?? .distantPast) {
                            keeper.updatedAt = dupUpdated
                        }
                    }
                    if keeper.createdAt == nil {
                        keeper.createdAt = c.createdAt
                    }

                    toDelete.append(c)
                } else {
                    keeperById[hubId] = c
                }
            }

            if !toDelete.isEmpty {
                toDelete.forEach { viewContext.delete($0) }
                try viewContext.save()
                print("[CompaniesView] De-duped companies by id. Removed: \(toDelete.count)")
            }
        } catch {
            print("[CompaniesView] Failed to de-dupe companies: \(error.localizedDescription)")
        }
    }
    
    private func dedupeCompaniesWithoutIdByName() {
        let req: NSFetchRequest<Company> = Company.fetchRequest()
        req.sortDescriptors = [
            NSSortDescriptor(keyPath: \Company.updatedAt, ascending: false),
            NSSortDescriptor(keyPath: \Company.createdAt, ascending: false)
        ]

        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        do {
            let all = try viewContext.fetch(req)
            var keeperByName: [String: Company] = [:]
            var toDelete: [Company] = []

            for c in all {
                let hasId = !(c.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                guard !hasId else { continue }

                let key = norm(c.name ?? "")
                guard !key.isEmpty else { continue }

                if let keeper = keeperByName[key], keeper != c {
                    let dupContacts = (c.contacts as? Set<Contact>) ?? []
                    for contact in dupContacts {
                        keeper.addToContacts(contact)
                        if contact.responds(to: NSSelectorFromString("setCompany:")) {
                            contact.setValue(keeper, forKey: "company")
                        }
                    }

                    let dupDeals = (c.deals as? Set<Deal>) ?? []
                    for deal in dupDeals {
                        keeper.addToDeals(deal)
                        if deal.responds(to: NSSelectorFromString("setCompany:")) {
                            deal.setValue(keeper, forKey: "company")
                        }
                    }

                    if (keeper.domain ?? "").isEmpty, let v = c.domain, !v.isEmpty { keeper.domain = v }
                    if (keeper.phone ?? "").isEmpty, let v = c.phone, !v.isEmpty { keeper.phone = v }
                    if (keeper.website ?? "").isEmpty, let v = c.website, !v.isEmpty { keeper.website = v }
                    if (keeper.address ?? "").isEmpty, let v = c.address, !v.isEmpty { keeper.address = v }
                    if (keeper.city ?? "").isEmpty, let v = c.city, !v.isEmpty { keeper.city = v }
                    if (keeper.state ?? "").isEmpty, let v = c.state, !v.isEmpty { keeper.state = v }
                    if (keeper.zipcode ?? "").isEmpty, let v = c.zipcode, !v.isEmpty { keeper.zipcode = v }
                    if (keeper.country ?? "").isEmpty, let v = c.country, !v.isEmpty { keeper.country = v }

                    if let dupUpdated = c.updatedAt {
                        if keeper.updatedAt == nil || dupUpdated > (keeper.updatedAt ?? .distantPast) {
                            keeper.updatedAt = dupUpdated
                        }
                    }
                    if keeper.createdAt == nil { keeper.createdAt = c.createdAt }

                    toDelete.append(c)
                } else {
                    keeperByName[key] = c
                }
            }

            if !toDelete.isEmpty {
                toDelete.forEach { viewContext.delete($0) }
                try viewContext.save()
                print("[CompaniesView] De-duped companies without id by name. Removed: \(toDelete.count)")
            }
        } catch {
            print("[CompaniesView] Failed to de-dupe companies without id: \(error.localizedDescription)")
        }
    }
}

struct CompanyFormSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    var company: Company? = nil
    
    @State private var name: String = ""
    @State private var domain: String = ""
    @State private var phone: String = ""
    @State private var address: String = ""
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var zipcode: String = ""
    @State private var country: String = ""
    @State private var website: String = ""
    
    @State private var createdAt = Date()
    @State private var updatedAt = Date()
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()
    
    init(isPresented: Binding<Bool>? = nil, company: Company? = nil) {
        self.company = company
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Company Details")) {
                    TextField("Name", text: $name).autocapitalization(.words)
                    TextField("Domain", text: $domain).textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                    TextField("Website", text: $website).keyboardType(.URL).textInputAutocapitalization(.never)
                    TextField("Address", text: $address).autocapitalization(.words)
                    TextField("City", text: $city).autocapitalization(.words)
                    TextField("State", text: $state).autocapitalization(.words)
                    TextField("Zipcode", text: $zipcode).keyboardType(.numbersAndPunctuation)
                    TextField("Country", text: $country).autocapitalization(.words)
                }
                Section(header: Text("Timestamps")) {
                    HStack { Text("Created At"); Spacer(); Text(dateFormatter.string(from: createdAt)).foregroundColor(.secondary) }
                    HStack { Text("Updated At"); Spacer(); Text(dateFormatter.string(from: updatedAt)).foregroundColor(.secondary) }
                }
            }
            .navigationTitle(company == nil ? "New Company" : "Edit Company")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCompany()
                    }
                    .disabled(name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: prefillFields)
        }
    }
    
    private func prefillFields() {
        if let company = company {
            name = company.name ?? ""
            domain = company.domain ?? ""
            phone = company.phone ?? ""
            website = company.website ?? ""
            address = company.address ?? ""
            city = company.city ?? ""
            state = company.state ?? ""
            zipcode = company.zipcode ?? ""
            country = company.country ?? ""
            createdAt = company.createdAt ?? Date()
            updatedAt = company.updatedAt ?? Date()
        } else {
            // New company, default values
            createdAt = Date()
            updatedAt = Date()
        }
    }
    
    private func saveCompany() {
        let now = Date()
        
        if let company = company {
            company.name = name
            company.domain = domain
            company.phone = phone
            company.website = website
            company.address = address
            company.city = city
            company.state = state
            company.zipcode = zipcode
            company.country = country
            
            company.updatedAt = now
            if company.createdAt == nil {
                company.createdAt = now
            }
            
            do {
                try viewContext.save()
                dismiss()
            } catch {
                print("Failed to save company: \(error.localizedDescription)")
            }
        } else {
            let newCompany = Company(context: viewContext)
            
            if newCompany.id == nil || (newCompany.id ?? "").isEmpty {
                // Use a prefix so local records never collide with HubSpot numeric ids.
                newCompany.id = "local-\(UUID().uuidString)"
            }
            
            newCompany.name = name
            newCompany.domain = domain
            newCompany.phone = phone
            newCompany.website = website
            newCompany.address = address
            newCompany.city = city
            newCompany.state = state
            newCompany.zipcode = zipcode
            newCompany.country = country
            
            newCompany.createdAt = now
            newCompany.updatedAt = now
            
            do {
                try viewContext.save()
                dismiss()
            } catch {
                print("Failed to save company: \(error.localizedDescription)")
            }
        }
    }
}
