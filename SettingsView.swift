import SwiftUI
import CoreData
import Combine
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("darkMode") private var darkMode = false
    @AppStorage("hubSpotSyncEnabled") private var hubSpotSyncEnabled: Bool = false
    @ObservedObject private var hubSpotService = HubSpotService.shared

    @State private var isConnectingHubSpot = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showImportOpportunities = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("CRM Options")) {
                    Toggle("HubSpot", isOn: .constant(true))
                        .disabled(true)
                    Toggle("Salesforce", isOn: .constant(false))
                        .disabled(true)
                    Toggle("Microsoft Dynamics", isOn: .constant(false))
                        .disabled(true)
                }

                Section(header: Text("HubSpot Connection")) {
                    Section {
                        Button {
                            connectHubSpot()
                        } label: {
                            HStack {
                                Spacer()
                                if isConnectingHubSpot {
                                    ProgressView()
                                } else if hubSpotService.isConnected {
                                    Text("Connected")
                                } else {
                                    Text("Connect HubSpot")
                                }
                                Spacer()
                            }
                        }
                        .disabled(isConnectingHubSpot || hubSpotService.isConnected)
                    }

                    Text("Status: \(hubSpotService.isConnected ? "Connected" : "Disconnected")")
                        .foregroundColor(hubSpotService.isConnected ? .green : .red)

                    Toggle("Sync with HubSpot", isOn: $hubSpotSyncEnabled)
                        .disabled(!hubSpotService.isConnected)

                    Section(header: Text("Import")) {
                        Button {
                            showImportOpportunities = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Import Opportunities")
                                Spacer()
                            }
                        }
                        .disabled(!hubSpotService.isConnected)

                        Text("Search HubSpot deals and import the selected opportunities. We’ll pull the associated company and contacts as part of the import.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    if hubSpotSyncEnabled && hubSpotService.isConnected {
                        Text("Changes in this app will be synchronized to HubSpot.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Imported deals will not be updated back to HubSpot.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Appearance")) {
                    Toggle("Dark Mode", isOn: $darkMode)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                hubSpotService.refreshConnectionStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                hubSpotService.refreshConnectionStatus()
            }
            .onReceive(hubSpotService.$isConnected) { _ in }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("HubSpot Connection"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .sheet(isPresented: $showImportOpportunities) {
                ImportOpportunitiesView()
            }
        }
    }

    private func connectHubSpot() {
        isConnectingHubSpot = true
        HubSpotService.shared.connectInBrowser()
        isConnectingHubSpot = false
        alertMessage = "HubSpot login opened in your browser. Complete authorization, then return to the app."
        showAlert = true
    }
}

// MARK: - HubSpot Import UI

struct ImportOpportunitiesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext

    @State private var query: String = ""
    @State private var isLoading = false
    @State private var results: [HubSpotDealSearchItem] = []
    @State private var selected = Set<String>()
    @State private var errorMessage: String? = nil

    // simple progress info for sequential fetch
    @State private var importingCount: Int = 0
    @State private var totalToImport: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    TextField("Search deals by name…", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button("Search") { search() }
                        .disabled(isLoading)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if isLoading {
                    ProgressView(totalToImport > 0 ? "Importing \(importingCount)/\(totalToImport)…" : "Loading…")
                        .padding(.top, 8)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                if results.isEmpty {
                    Spacer()
                    Text("Search HubSpot deals to import.")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List {
                        ForEach(results, id: \.id) { deal in
                            Button { toggleSelection(deal.id) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selected.contains(deal.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selected.contains(deal.id) ? .accentColor : .secondary)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(deal.dealname.isEmpty ? "(No name)" : deal.dealname)
                                            .font(.headline)
                                            .foregroundColor(.primary)

                                        HStack(spacing: 10) {
                                            if let stage = deal.dealstage, !stage.isEmpty {
                                                Text("Stage: \(stage)")
                                            }
                                            if let amount = deal.amount, !amount.isEmpty {
                                                Text("Amount: \(amount)")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }

                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Import Opportunities")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importSelected() }
                        .disabled(selected.isEmpty || isLoading)
                }
            }
        }
    }

    private func toggleSelection(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func search() {
        errorMessage = nil
        isLoading = true
        importingCount = 0
        totalToImport = 0

        HubSpotService.shared.searchDeals(query: query, limit: 25) { result in
            isLoading = false
            switch result {
            case .success(let items):
                results = items
                let ids = Set(items.map { $0.id })
                selected = selected.filter { ids.contains($0) }
            case .failure(let err):
                errorMessage = err.localizedDescription
                results = []
                selected.removeAll()
            }
        }
    }

    private func importSelected() {
        errorMessage = nil
        isLoading = true

        let ids = Array(selected)
        totalToImport = ids.count
        importingCount = 0

        fetchBundlesSequentially(ids: ids, index: 0)
    }

    private func fetchBundlesSequentially(ids: [String], index: Int) {
        if index >= ids.count { isLoading = false; return }

        let dealId = ids[index]
        HubSpotService.shared.fetchDealBundle(dealId: dealId) { result in
            switch result {
            case .success(let bundle):
                // Fetch full details for company and contacts before import
                fetchDetailsForBundle(bundle) { companyDetail, contactDetails in
                    do {
                        try importBundleIntoCoreData(bundle, companyDetail: companyDetail, contactDetails: contactDetails)
                        importingCount = index + 1
                        print("[Import] ✅ Saved to Core Data: \(bundle.deal.dealname)")
                        fetchBundlesSequentially(ids: ids, index: index + 1)
                    } catch {
                        errorMessage = "Failed saving deal \(dealId): \(error.localizedDescription)"
                        isLoading = false
                    }
                }
            case .failure(let err):
                errorMessage = "Failed importing deal \(dealId): \(err.localizedDescription)"
                isLoading = false
            }
        }
    }

    /// Fetch detailed info for the company and contacts in the bundle serially
    private func fetchDetailsForBundle(_ bundle: HubSpotDealBundle,
                                       completion: @escaping (HubSpotCompanyDetail?, [String: HubSpotContactDetail]) -> Void) {
        var companyDetail: HubSpotCompanyDetail? = nil
        var contactDetails: [String: HubSpotContactDetail] = [:]

        // Helper function to fetch contact details one by one
        func fetchContactDetailsSequentially(_ contacts: [HubSpotDealBundle.Contact], index: Int) {
            if index >= contacts.count {
                completion(companyDetail, contactDetails)
                return
            }
            let contactId = contacts[index].id.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !contactId.isEmpty {
                HubSpotService.shared.fetchContactDetail(contactId: contactId) { result in
                    switch result {
                    case .success(let detail):
                        contactDetails[contactId] = detail
                    case .failure:
                        break // ignore failure for individual contacts
                    }
                    fetchContactDetailsSequentially(contacts, index: index + 1)
                }
            } else {
                fetchContactDetailsSequentially(contacts, index: index + 1)
            }
        }

        if let cid = bundle.company?.id {
            let companyId = cid.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !companyId.isEmpty {
                HubSpotService.shared.fetchCompanyDetail(companyId: companyId) { result in
                    switch result {
                    case .success(let detail):
                        companyDetail = detail
                    case .failure:
                        companyDetail = nil
                    }
                    // After company detail, fetch contacts detail sequentially
                    fetchContactDetailsSequentially(bundle.contacts, index: 0)
                }
                return
            }
        }
        // No company detail to fetch, proceed to contacts detail fetch
        fetchContactDetailsSequentially(bundle.contacts, index: 0)
    }

    // MARK: - Core Data Import
    private func importBundleIntoCoreData(_ bundle: HubSpotDealBundle, companyDetail: HubSpotCompanyDetail?, contactDetails: [String: HubSpotContactDetail]) throws {
        var caught: Error?

        viewContext.performAndWait {
            do {
                let companyObj = try upsertCompany(from: bundle.company, detail: companyDetail)
                let contactObjs = try upsertContacts(from: bundle.contacts, company: companyObj, details: contactDetails)
                let dealObj = try upsertDeal(from: bundle.deal, company: companyObj)

                if let companyObj {
                    dealObj.company = companyObj
                    companyObj.addToDeals(dealObj)
                }

                if let current = dealObj.contacts as? Set<Contact> {
                    current.forEach { dealObj.removeFromContacts($0) }
                }
                contactObjs.forEach { dealObj.addToContacts($0) }

                contactObjs.forEach { contact in
                    contact.addToDeals(dealObj)
                    if let companyObj {
                        contact.company = companyObj
                        companyObj.addToContacts(contact)
                    }
                }

                // Set timestamps after upserting and relationship setup
                let now = Date()

                if let companyObj {
                    companyObj.updatedAt = now
                    if companyObj.createdAt == nil || companyObj.createdAt == Date.distantPast {
                        companyObj.createdAt = now
                    }
                }

                for contact in contactObjs {
                    contact.updatedAt = now
                    if contact.createdAt == nil || contact.createdAt == Date.distantPast {
                        contact.createdAt = now
                    }
                }

                dealObj.updatedAt = now
                if dealObj.createdAt == nil || dealObj.createdAt == Date.distantPast {
                    dealObj.createdAt = now
                }

                if viewContext.hasChanges {
                    try viewContext.save()
                }
            } catch {
                caught = error
            }
        }

        if let caught { throw caught }
    }

    /// Map HubSpot Company fields to Core Data Company entity
    private func upsertCompany(from company: HubSpotDealBundle.Company?, detail: HubSpotCompanyDetail? = nil) throws -> Company? {
        guard let company else { return nil }

        // HubSpot external id
        let externalId = company.id.trimmingCharacters(in: .whitespacesAndNewlines)

        // Prefer bundle values, fall back to detail values
        var name = company.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var domain = (company.domain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if name.isEmpty, let dn = detail?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !dn.isEmpty {
            name = dn
        }
        if domain.isEmpty, let dd = detail?.domain?.trimmingCharacters(in: .whitespacesAndNewlines), !dd.isEmpty {
            domain = dd
        }

        if name.isEmpty { return nil }

        let req = NSFetchRequest<Company>(entityName: "Company")
        req.fetchLimit = 1

        // IMPORTANT: if we have an externalId, we ONLY match on that. This prevents creating duplicates.
        if !externalId.isEmpty {
            req.predicate = NSPredicate(format: "id == %@", externalId)
        } else if !domain.isEmpty {
            req.predicate = NSPredicate(format: "domain ==[c] %@", domain)
        } else {
            req.predicate = NSPredicate(format: "name ==[c] %@", name)
        }

        let existing = try viewContext.fetch(req).first
        let obj = existing ?? Company(context: viewContext)

        // Ensure a stable unique id
        if !externalId.isEmpty {
            obj.id = externalId
        } else if (obj.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            obj.id = UUID().uuidString
        }

        // Base fields
        obj.name = name
        if !domain.isEmpty { obj.domain = domain }

        // Bundle fields (preferred when present)
        if let phone = company.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            obj.phone = phone
        }
        if let website = company.website?.trimmingCharacters(in: .whitespacesAndNewlines), !website.isEmpty {
            obj.website = website
        }
        if let address = company.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
            obj.address = address
        }
        if let city = company.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            obj.city = city
        }
        if let state = company.state?.trimmingCharacters(in: .whitespacesAndNewlines), !state.isEmpty {
            obj.state = state
        }
        if let zip = company.zip?.trimmingCharacters(in: .whitespacesAndNewlines), !zip.isEmpty {
            obj.zipcode = zip
        }
        if let country = company.country?.trimmingCharacters(in: .whitespacesAndNewlines), !country.isEmpty {
            obj.country = country
        }

        if let d = detail {
            if ((obj.phone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty,
               let phone = d.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
                obj.phone = phone
            }
            if ((obj.website ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty,
               let website = d.website?.trimmingCharacters(in: .whitespacesAndNewlines), !website.isEmpty {
                obj.website = website
            }
            if ((obj.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty,
               let address = d.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
                obj.address = address
            }
            if ((obj.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty,
               let city = d.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
                obj.city = city
            }
            if ((obj.state ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty,
               let state = d.state?.trimmingCharacters(in: .whitespacesAndNewlines), !state.isEmpty {
                obj.state = state
            }
            if ((obj.zipcode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty,
               let zip = d.zip?.trimmingCharacters(in: .whitespacesAndNewlines), !zip.isEmpty {
                obj.zipcode = zip
            }
            if ((obj.country ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty,
               let country = d.country?.trimmingCharacters(in: .whitespacesAndNewlines), !country.isEmpty {
                obj.country = country
            }
        }

        if ((obj.website ?? "").trimmingCharacters(in: .whitespacesAndNewlines)).isEmpty, !domain.isEmpty {
            obj.website = "https://\(domain)"
        }

        // Debug: confirm what we are about to persist
        print("[Import] 🏢 Upsert Company id=\(obj.id ?? "") name=\(obj.name ?? "") address=\(obj.address ?? "") city=\(obj.city ?? "") state=\(obj.state ?? "") zip=\(obj.zipcode ?? "") phone=\(obj.phone ?? "") website=\(obj.website ?? "")")

        return obj
    }

    /// Map HubSpot Contact fields to Core Data Contact entity
    private func upsertContacts(from contacts: [HubSpotDealBundle.Contact], company: Company?, details: [String: HubSpotContactDetail] = [:]) throws -> [Contact] {
        var out: [Contact] = []
        out.reserveCapacity(contacts.count)

        for c in contacts {
            let externalId = c.id.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let email = (c.email ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let first = c.firstname.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let last = c.lastname.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            if email.isEmpty && first.isEmpty && last.isEmpty { continue }

            let req = NSFetchRequest<Contact>(entityName: "Contact")
            req.fetchLimit = 1

            if !externalId.isEmpty {
                // Prefer matching by externalId if available
                req.predicate = NSPredicate(format: "id == %@", externalId)
            } else if !email.isEmpty {
                req.predicate = NSPredicate(format: "email ==[c] %@", email)
            } else if let companyName = company?.name, !companyName.isEmpty {
                req.predicate = NSPredicate(format: "firstName ==[c] %@ AND lastName ==[c] %@ AND company.name ==[c] %@", first, last, companyName)
            } else {
                req.predicate = NSPredicate(format: "firstName ==[c] %@ AND lastName ==[c] %@", first, last)
            }

            let existing = try viewContext.fetch(req).first
            let obj = existing ?? Contact(context: viewContext)

            // Assign id: use externalId if available, else generate UUID if id is empty
            if externalId.isEmpty {
                if (obj.id ?? "").isEmpty {
                    obj.id = UUID().uuidString
                }
            } else {
                obj.id = externalId
            }

            if !first.isEmpty { obj.firstName = first }
            if !last.isEmpty { obj.lastName = last }

            // Email: prefer bundle email, but fall back to detail email when missing
            if !email.isEmpty {
                obj.email = email
            } else if let dEmail = details[externalId]?.email?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !dEmail.isEmpty {
                obj.email = dEmail
            }

            // Bundle fields (preferred when present)
            if let phone = c.phone?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !phone.isEmpty {
                obj.phone = phone
            }
            if let jobTitle = c.jobtitle?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !jobTitle.isEmpty {
                obj.jobTitle = jobTitle
            }

            if let company { obj.company = company }

            if let detail = details[externalId] {
                if ((obj.phone ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)).isEmpty,
                   let phone = detail.phone?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !phone.isEmpty {
                    obj.phone = phone
                }
                if ((obj.mobilePhone ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)).isEmpty,
                   let mobilePhone = detail.mobilephone?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !mobilePhone.isEmpty {
                    obj.mobilePhone = mobilePhone
                }
                if ((obj.jobTitle ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)).isEmpty,
                   let jobTitle = detail.jobtitle?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !jobTitle.isEmpty {
                    obj.jobTitle = jobTitle
                }
            }

            // TODO: If your Contact entity supports an externalId, set it here from c.id

            // HubSpot bundle currently does NOT include address info.
            // Preserve any existing address fields by not clearing them here.

            out.append(obj)
        }

        return out
    }

    /// Map HubSpot Deal fields to Core Data Deal entity
    private func upsertDeal(from deal: HubSpotDealBundle.Deal, company: Company?) throws -> Deal {
        let rawName = deal.dealname.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let name = rawName.isEmpty ? "(No name)" : rawName

        let stage = (deal.dealstage ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        let req = NSFetchRequest<Deal>(entityName: "Deal")
        req.fetchLimit = 1

        let externalId = deal.id.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if !externalId.isEmpty {
            // Attempt fetch by id first (using Core Data 'id' property as external CRM id when provided)
            req.predicate = NSPredicate(format: "id == %@", externalId)
        } else {
            // fallback to name + company + closeDate (if available) matching
            if let companyName = company?.name, !companyName.isEmpty, let closeRaw = deal.closedate, let closeDate = parseHubSpotDate(closeRaw) {
                req.predicate = NSPredicate(format: "name ==[c] %@ AND company.name ==[c] %@ AND closeDate == %@", name, companyName, closeDate as CVarArg)
            } else if let companyName = company?.name, !companyName.isEmpty {
                req.predicate = NSPredicate(format: "name ==[c] %@ AND company.name ==[c] %@", name, companyName)
            } else {
                req.predicate = NSPredicate(format: "name ==[c] %@", name)
            }
        }

        let existing = try viewContext.fetch(req).first
        let obj = existing ?? Deal(context: viewContext)

        // Assign id: use externalId if available, else generate UUID if id is empty
        if externalId.isEmpty {
            if (obj.id ?? "").isEmpty {
                obj.id = UUID().uuidString
            }
        } else {
            obj.id = externalId
        }

        obj.name = name
        if !stage.isEmpty { obj.stage = stage }

        if let amountStr = deal.amount, !amountStr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            let cleaned = amountStr.replacingOccurrences(of: ",", with: "")
            let num = NSDecimalNumber(string: cleaned)
            if num != NSDecimalNumber.notANumber { obj.amount = num }
        }

        if let closeRaw = deal.closedate, let d = parseHubSpotDate(closeRaw) { obj.closeDate = d }

        if let company { obj.company = company }

        // TODO: If your Deal entity supports an externalId, set it here from deal.id

        // HubSpot bundle currently does NOT include address info.
        // Preserve any existing address fields by not clearing them here.

        return obj
    }

    private func parseHubSpotDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if let n = Double(trimmed) {
            if n > 100000000000 { return Date(timeIntervalSince1970: n / 1000.0) }
            else if n > 1000000000 { return Date(timeIntervalSince1970: n) }
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: trimmed) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return df.date(from: trimmed)
    }
}

