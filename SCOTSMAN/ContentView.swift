//
//  ContentView.swift
//  SCOTSMAN
//
//  Created by Ian Miller on 1/27/26.
//

import SwiftUI
import CoreData
import Combine



struct ContentView: View {
    @State private var isShowingSettings = false
    @State private var isAuthenticating = false
    
    var body: some View {
        TabView {
            NavigationStack {
                CompaniesView()
                    .navigationTitle("Companies")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                isShowingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Companies", systemImage: "building.2")
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(isPresented: $isShowingSettings)
            }
            
            NavigationStack {
                ContactsView()
                    .navigationTitle("Contacts")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                isShowingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Contacts", systemImage: "person.2")
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(isPresented: $isShowingSettings)
            }
            
            NavigationStack {
                OpportunitiesView()
                    .navigationTitle("Opportunities")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                isShowingSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
            }
            .tabItem {
                Label("Opportunities", systemImage: "chart.bar")
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView(isPresented: $isShowingSettings)
            }
        }
    }
}

struct SettingsView: View {
    @Binding var isPresented: Bool
    @State private var isConnectingHubSpot = false
    @AppStorage("hubSpotSyncEnabled") private var hubSpotSyncEnabled: Bool = false
    @ObservedObject private var hubSpotService = HubSpotService.shared
    
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("CRM Options")) {
                    Toggle("HubSpot", isOn: .constant(true))
                        .disabled(true)
                    Toggle("Salesforce", isOn: .constant(false))
                        .disabled(true)
                    Toggle("Zoho", isOn: .constant(false))
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
                    
                    if hubSpotSyncEnabled && hubSpotService.isConnected {
                        Text("Changes in this app will be synchronized to HubSpot.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Imported deals will not be updated back to HubSpot.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    
                    // Future login/connect UI and logic hooks go here
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
            .onReceive(hubSpotService.$isConnected) { _ in
                // Update UI when connection changes
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("HubSpot Connection"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    private func connectHubSpot() {
        isConnectingHubSpot = true
        HubSpotService.shared.startOAuth { success in
            isConnectingHubSpot = false
            if success {
                alertMessage = "Successfully connected to HubSpot."
                hubSpotSyncEnabled = true
            } else {
                alertMessage = "Failed to connect to HubSpot. Please try again."
            }
            showAlert = true
        }
    }
}

struct CompaniesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Company.name, ascending: true)],
        animation: .default)
    private var companies: FetchedResults<Company>
    
    @State private var isShowingAddCompany = false
    @State private var companyToEdit: Company? = nil
    
    var body: some View {
        List {
            ForEach(companies) { company in
                Button {
                    companyToEdit = company
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(company.name ?? "Unknown")
                            .font(.headline)
                        
                        if let address = company.address,
                           !address.isEmpty {
                            Text(address)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let phone = company.phone,
                           !phone.isEmpty {
                            Text("Phone: \(phone)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let website = company.website,
                           !website.isEmpty {
                            Text("Website: \(website)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // Linked Contacts summary
                        let contactsSet = company.contacts as? Set<Contact> ?? []
                        if contactsSet.isEmpty {
                            Text("Contacts: None")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            let contactNames = contactsSet.map {
                                if let first = $0.firstName, let last = $0.lastName {
                                    return "\(first) \(last)"
                                } else {
                                    return "Unnamed"
                                }
                            }
                            .sorted()
                            let count = contactsSet.count
                            if count <= 3 {
                                Text("Contacts (\(count)): \(contactNames.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                let firstThree = contactNames.prefix(3).joined(separator: ", ")
                                Text("Contacts (\(count)): \(firstThree), ...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Linked Opportunities summary
                        let dealsSet = company.deals as? Set<Deal> ?? []
                        if dealsSet.isEmpty {
                            Text("Opportunities: None")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            let dealNames = dealsSet.map { $0.name ?? "Unnamed" }
                                .sorted()
                            let count = dealsSet.count
                            if count <= 3 {
                                Text("Opportunities (\(count)): \(dealNames.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                let firstThree = dealNames.prefix(3).joined(separator: ", ")
                                Text("Opportunities (\(count)): \(firstThree), ...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteCompanies)
        }
        .listStyle(InsetGroupedListStyle())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingAddCompany = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddCompany) {
            CompanyFormSheet(isPresented: $isShowingAddCompany, company: nil)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(item: $companyToEdit) { company in
            CompanyFormSheet(isPresented: Binding(
                get: { companyToEdit != nil },
                set: { if !$0 { companyToEdit = nil } }
            ), company: company)
            .environment(\.managedObjectContext, viewContext)
        }
    }
    
    private func deleteCompanies(offsets: IndexSet) {
        withAnimation {
            offsets.map { companies[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                // Handle error appropriately in production
                print("Error deleting company: \(error.localizedDescription)")
            }
        }
    }
}

struct CompanyFormSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var isPresented: Bool
    
    @State private var idString: String = UUID().uuidString
    @State private var name: String = ""
    @State private var domain: String = ""
    @State private var phone: String = ""
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var country: String = ""
    @State private var address: String = ""
    @State private var zipcode: String = ""
    @State private var website: String = ""
    @State private var createdAt: Date = Date()
    @State private var updatedAt: Date = Date()
    
    var company: Company?
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    init(isPresented: Binding<Bool>, company: Company?) {
        self._isPresented = isPresented
        self.company = company
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Company Details")) {
                    TextField("Name", text: $name)
                        .autocapitalization(.words)
                    
                    TextField("Address", text: $address)
                        .autocapitalization(.words)
                    TextField("City", text: $city)
                        .autocapitalization(.words)
                    TextField("State", text: $state)
                        .autocapitalization(.words)
                    TextField("Zipcode", text: $zipcode)
                        .keyboardType(.numbersAndPunctuation)
                    
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Website", text: $website)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                }
                
                Section(header: Text("Timestamps")) {
                    HStack {
                        Text("Created At")
                        Spacer()
                        Text(dateFormatter.string(from: createdAt))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Updated At")
                        Spacer()
                        Text(dateFormatter.string(from: updatedAt))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(company == nil ? "Add Company" : "Edit Company")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveCompany()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            if let company = company {
                idString = company.id ?? UUID().uuidString
                name = company.name ?? ""
                domain = company.domain ?? ""
                phone = company.phone ?? ""
                city = company.city ?? ""
                state = company.state ?? ""
                country = company.country ?? ""
                address = company.address ?? ""
                zipcode = company.zipcode ?? ""
                website = company.website ?? ""
                createdAt = company.createdAt ?? Date()
                updatedAt = company.updatedAt ?? Date()
            } else {
                idString = UUID().uuidString
                name = ""
                domain = ""
                phone = ""
                city = ""
                state = ""
                country = ""
                address = ""
                zipcode = ""
                website = ""
                createdAt = Date()
                updatedAt = Date()
            }
        }
    }
    
    private func saveCompany() {
        let editingCompany = company ?? Company(context: viewContext)
        editingCompany.id = idString
        editingCompany.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editingCompany.domain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        editingCompany.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        editingCompany.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        editingCompany.state = state.trimmingCharacters(in: .whitespacesAndNewlines)
        editingCompany.country = country.trimmingCharacters(in: .whitespacesAndNewlines)
        editingCompany.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        editingCompany.zipcode = zipcode.trimmingCharacters(in: .whitespacesAndNewlines)
        editingCompany.website = website.trimmingCharacters(in: .whitespacesAndNewlines)
        editingCompany.createdAt = createdAt
        editingCompany.updatedAt = updatedAt
        
        do {
            try viewContext.save()
            isPresented = false
        } catch {
            // Handle error appropriately in production
            print("Failed to save company: \(error.localizedDescription)")
        }
    }
}

struct ContactsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        entity: Contact.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Contact.lastName, ascending: true),
            NSSortDescriptor(keyPath: \Contact.firstName, ascending: true)
        ],
        animation: .default)
    private var contacts: FetchedResults<Contact>
    
    @State private var isShowingAddContact = false
    @State private var contactToEdit: Contact? = nil
    
    var body: some View {
        List {
            ForEach(contacts, id: \.objectID) { contact in
                Button {
                    contactToEdit = contact
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(contact.firstName ?? "") \(contact.lastName ?? "")")
                            .font(.headline)
                        
                        if let email = contact.email,
                           !email.isEmpty {
                            Text(email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let phone = contact.phone,
                           !phone.isEmpty {
                            Text("Phone: \(phone)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let jobTitle = contact.jobTitle,
                           !jobTitle.isEmpty {
                            Text("Job Title: \(jobTitle)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let company = contact.company,
                           let companyName = company.name,
                           !companyName.isEmpty {
                            Text("Company: \(companyName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Company: None")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Linked Deals summary
                        let dealsSet = contact.deals as? Set<Deal> ?? []
                        if dealsSet.isEmpty {
                            Text("Deals: None")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            let dealNames = dealsSet.map { $0.name ?? "Unnamed" }
                                .sorted()
                            let count = dealsSet.count
                            if count <= 3 {
                                Text("Deals (\(count)): \(dealNames.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                let firstThree = dealNames.prefix(3).joined(separator: ", ")
                                Text("Deals (\(count)): \(firstThree), ...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteContacts)
        }
        .listStyle(InsetGroupedListStyle())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingAddContact = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddContact) {
            ContactFormSheet(isPresented: $isShowingAddContact, contact: nil)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(item: $contactToEdit) { contact in
            ContactFormSheet(isPresented: Binding(
                get: { contactToEdit != nil },
                set: { if !$0 { contactToEdit = nil } }
            ), contact: contact)
            .environment(\.managedObjectContext, viewContext)
        }
    }
    
    private func deleteContacts(offsets: IndexSet) {
        withAnimation {
            offsets.map { contacts[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                // Handle error appropriately in production
                print("Error deleting contact: \(error.localizedDescription)")
            }
        }
    }
}

struct ContactFormSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Company.name, ascending: true)],
        animation: .default)
    private var companies: FetchedResults<Company>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Deal.name, ascending: true)],
        animation: .default)
    private var opportunities: FetchedResults<Deal>
    
    @Binding var isPresented: Bool
    
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    
    @State private var selectedCompany: Company? = nil
    @State private var selectedOpportunities: Set<Deal> = []
    
    var contact: Contact?
    
    init(isPresented: Binding<Bool>, contact: Contact?) {
        self._isPresented = isPresented
        self.contact = contact
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Contact Details")) {
                    TextField("First Name", text: $firstName)
                        .autocapitalization(.words)
                    TextField("Last Name", text: $lastName)
                        .autocapitalization(.words)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }
                
                Section(header: Text("Company")) {
                    Picker("Select Company", selection: $selectedCompany) {
                        Text("None").tag(Company?.none)
                        ForEach(companies) { company in
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
            .navigationTitle(contact == nil ? "Add Contact" : "Edit Contact")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        clearForm()
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveContact()
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                if let contactOpportunities = contact.deals as? Set<Deal> {
                    selectedOpportunities = contactOpportunities
                } else {
                    selectedOpportunities = []
                }
            } else {
                clearForm()
            }
        }
    }
    
    private func clearForm() {
        firstName = ""
        lastName = ""
        email = ""
        phone = ""
        selectedCompany = nil
        selectedOpportunities = []
    }
    
    private func saveContact() {
        if let contact = contact {
            // Editing existing contact - update only this contact
            contact.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            contact.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            contact.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
            contact.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
            
            contact.company = selectedCompany
            
            // Remove all current deals and add selected deals
            if let currentDeals = contact.deals as? Set<Deal> {
                currentDeals.forEach { contact.removeFromDeals($0) }
            }
            selectedOpportunities.forEach { contact.addToDeals($0) }
            
        } else {
            // Creating new contact
            let newContact = Contact(context: viewContext)
            newContact.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            newContact.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            newContact.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
            newContact.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
            
            newContact.company = selectedCompany
            
            selectedOpportunities.forEach { newContact.addToDeals($0) }
        }
        
        do {
            try viewContext.save()
            clearForm()
            isPresented = false
        } catch {
            // Handle error appropriately in production
            print("Failed to save contact: \(error.localizedDescription)")
        }
    }
}

struct OpportunitiesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Deal.name, ascending: true)],
        animation: .default)
    private var deals: FetchedResults<Deal>
    
    @State private var isShowingAddDeal = false
    @State private var dealToEdit: Deal? = nil
    
    var body: some View {
        List {
            ForEach(deals, id: \.objectID) { deal in
                Button {
                    dealToEdit = deal
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deal.name ?? "Unnamed Deal")
                            .font(.headline)
                        
                        if let stage = deal.stage,
                           !stage.isEmpty {
                            Text("Stage: \(stage)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        let amountNumber = deal.amount ?? NSDecimalNumber.zero
                        let amountString = String(format: "$%.2f", amountNumber.doubleValue)
                        Text("Amount: \(amountString)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let closeDate = deal.closeDate {
                            Text("Close Date: \(closeDate, formatter: dateFormatter)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        if let companyName = deal.company?.name, !companyName.isEmpty {
                            Text("Company: \(companyName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Company: None")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Primary contact (if any)
                        if let contactsSet = deal.contacts as? Set<Contact>, !contactsSet.isEmpty {
                            let firstContact = contactsSet.first
                            let contactName = "\(firstContact?.firstName ?? "") \(firstContact?.lastName ?? "")"
                            Text("Primary Contact: \(contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "None" : contactName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Primary Contact: None")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: deleteDeals)
        }
        .listStyle(InsetGroupedListStyle())
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingAddDeal = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddDeal) {
            OpportunityFormSheet(isPresented: $isShowingAddDeal, deal: nil)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(item: $dealToEdit) { deal in
            OpportunityFormSheet(isPresented: Binding(
                get: { dealToEdit != nil },
                set: { if !$0 { dealToEdit = nil } }
            ), deal: deal)
            .environment(\.managedObjectContext, viewContext)
        }
    }
    
    private func deleteDeals(offsets: IndexSet) {
        withAnimation {
            offsets.map { deals[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                // Handle error appropriately in production
                print("Error deleting deal: \(error.localizedDescription)")
            }
        }
    }
}

private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter
}()

struct OpportunityFormSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Company.name, ascending: true)],
        animation: .default)
    private var companies: FetchedResults<Company>
    
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Contact.lastName, ascending: true),
            NSSortDescriptor(keyPath: \Contact.firstName, ascending: true)
        ],
        animation: .default)
    private var contacts: FetchedResults<Contact>
    
    @Binding var isPresented: Bool
    
    @State private var name: String = ""
    @State private var stage: String = ""
    @State private var amountText: String = ""
    @State private var closeDate: Date = Date()
    
    @State private var selectedCompany: Company? = nil
    
    // Primary contact selection state
    @State private var selectedContact: Contact? = nil
    @State private var isShowingContactSelector = false
    
    // Contact selector search text
    @State private var contactSearchText: String = ""
    
    var deal: Deal?
    
    private let hubSpotStages: [(key: String, label: String)] = [
        ("appointmentscheduled", "Appointment Scheduled"),
        ("qualifiedtobuy", "Qualified to Buy"),
        ("presentation scheduled", "Presentation Scheduled"),
        ("decisionmaker bought-in", "Decision Maker Bought-In"),
        ("contract sent", "Contract Sent"),
        ("closedwon", "Closed Won"),
        ("closedlost", "Closed Lost")
    ]
    
    init(isPresented: Binding<Bool>, deal: Deal?) {
        self._isPresented = isPresented
        self.deal = deal
    }
    
    var filteredContacts: [Contact] {
        if contactSearchText.isEmpty {
            return contacts.map { $0 }
        }
        let lowercasedSearch = contactSearchText.lowercased()
        return contacts.filter {
            (($0.firstName ?? "").lowercased().contains(lowercasedSearch)) ||
            (($0.lastName ?? "").lowercased().contains(lowercasedSearch)) ||
            ("\($0.firstName ?? "") \($0.lastName ?? "")".lowercased().contains(lowercasedSearch))
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Company")) {
                    Picker("Select Company", selection: $selectedCompany) {
                        Text("None").tag(Company?.none)
                        ForEach(companies) { company in
                            Text(company.name ?? "Unknown").tag(Company?.some(company))
                        }
                    }
                }
                
                Section(header: Text("Opportunity Details")) {
                    TextField("Name", text: $name)
                        .autocapitalization(.words)
                    
                    Picker("Stage", selection: $stage) {
                        ForEach(hubSpotStages, id: \.key) { stageOption in
                            Text(stageOption.label).tag(stageOption.key)
                        }
                    }
                    
                    HStack {
                        Text("$")
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .onChange(of: amountText) {
                                newValue in
                                // Allow only numbers and decimal separator
                                let filtered = newValue.filter { "0123456789.".contains($0) }
                                if filtered != newValue {
                                    amountText = filtered
                                }
                            }
                    }
                    
                    DatePicker("Close Date", selection: $closeDate, displayedComponents: .date)
                }
                
                Section(header: Text("Primary Contact")) {
                    Button(action: {
                        isShowingContactSelector = true
                    }) {
                        HStack(spacing: 8) {
                            Text("Select Primary Contact")
                            Spacer()
                            if let selectedContact = selectedContact {
                                Text("\(selectedContact.firstName ?? "") \(selectedContact.lastName ?? "")")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } else {
                                Text("None")
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(deal == nil ? "Add Opportunity" : "Edit Opportunity")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        clearForm()
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveDeal()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $isShowingContactSelector) {
                NavigationStack {
                    VStack(spacing: 0) {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search Contacts", text: $contactSearchText)
                                .autocapitalization(.words)
                                .disableAutocorrection(true)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        
                        List(filteredContacts, id: \.objectID) { contact in
                            Button {
                                selectedContact = contact
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(contact.firstName ?? "") \(contact.lastName ?? "")")
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        if let email = contact.email, !email.isEmpty {
                                            Text(email)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if selectedContact == contact {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                            .imageScale(.large)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                            .imageScale(.large)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                        .listStyle(.insetGrouped)
                        
                        Divider()
                        
                        HStack {
                            Spacer()
                            Button("Done") {
                                isShowingContactSelector = false
                            }
                            .font(.headline)
                            .padding()
                            Spacer()
                        }
                    }
                    .navigationTitle("Select Primary Contact")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") {
                                isShowingContactSelector = false
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if let deal = deal {
                name = deal.name ?? ""
                stage = deal.stage ?? hubSpotStages.first?.key ?? ""
                amountText = {
                    if let amount = deal.amount?.doubleValue {
                        if amount == 0 {
                            return ""
                        }
                        return String(format: "%.2f", amount)
                    }
                    return ""
                }()
                closeDate = deal.closeDate ?? Date()
                selectedCompany = deal.company
                
                if let dealContacts = deal.contacts as? Set<Contact>, !dealContacts.isEmpty {
                    // Pick the first as primary contact
                    selectedContact = dealContacts.first
                } else {
                    selectedContact = nil
                }
                contactSearchText = ""
            } else {
                selectedCompany = nil
                selectedContact = nil
                stage = hubSpotStages.first?.key ?? ""
                amountText = ""
                closeDate = Date()
                contactSearchText = ""
            }
        }
    }
    
    private func clearForm() {
        name = ""
        stage = hubSpotStages.first?.key ?? ""
        amountText = ""
        closeDate = Date()
        selectedCompany = nil
        selectedContact = nil
        contactSearchText = ""
    }
    
    private func saveDeal() {
        let editingDeal = deal ?? Deal(context: viewContext)
        editingDeal.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editingDeal.stage = stage.trimmingCharacters(in: .whitespacesAndNewlines)
        let amountDecimal = NSDecimalNumber(string: amountText)
        editingDeal.amount = amountDecimal == NSDecimalNumber.notANumber ? NSDecimalNumber.zero : amountDecimal
        editingDeal.closeDate = closeDate
        
        // Set company relation
        editingDeal.company = selectedCompany
        
        // Set contacts relation: only one primary contact
        if let currentContacts = editingDeal.contacts as? Set<Contact> {
            currentContacts.forEach { editingDeal.removeFromContacts($0) }
        }
        if let selectedContact = selectedContact {
            editingDeal.addToContacts(selectedContact)
        }
        
        do {
            try viewContext.save()
            clearForm()
            isPresented = false
        } catch {
            // Handle error appropriately in production
            print("Failed to save deal: \(error.localizedDescription)")
        }
    }
}

extension NumberFormatter {
    static var currency: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter
    }
}

#Preview {
    ContentView()
}

