import Foundation
import UIKit
import Combine

// MARK: - HubSpot backend response models (file-scope to avoid Swift 6 actor isolation issues)

struct HubSpotStatusResponse: Decodable, Sendable {
    let ok: Bool
    let connected: Bool
    let hub_id: String?
    let updated_at: String?
}

struct HubSpotDealSearchItem: Identifiable, Decodable {
    let id: String
    let dealname: String
    let amount: String?
    let dealstage: String?
    let closedate: String?
}

struct HubSpotDealSearchResponse: Decodable, Sendable {
    let ok: Bool
    let results: [HubSpotDealSearchItem]
}

struct HubSpotDealBundle: Decodable, Sendable {
    struct Deal: Decodable {
        let id: String
        let dealname: String
        let amount: String?
        let dealstage: String?
        let closedate: String?
    }
    struct Company: Decodable {
        let id: String
        let name: String
        let domain: String?
        let phone: String?
        let website: String?
        let address: String?
        let city: String?
        let state: String?
        let zip: String?
        let country: String?
    }
    struct Contact: Decodable {
        let id: String
        let firstname: String
        let lastname: String
        let email: String?
        let phone: String?
        let mobilephone: String?
        let jobtitle: String?
    }

    let ok: Bool
    let deal: Deal
    let company: Company?
    let contacts: [Contact]
}

// New detailed company and contact response models
// Note: HubSpot CRM v3 "object by id" responses typically look like:
// { "id": "123", "properties": { "name": "...", "phone": "...", ... }, ... }
// These models decode BOTH shapes:
//  - flat JSON (id, name, phone, ...)
//  - HubSpot shape (id + properties.{...})

struct HubSpotCompanyDetail: Decodable {
    let id: String
    let name: String?
    let domain: String?
    let phone: String?
    let website: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let country: String?

    private struct Properties: Decodable {
        let name: String?
        let domain: String?
        let phone: String?
        let website: String?
        let address: String?
        let city: String?
        let state: String?
        let zip: String?
        // Removed zipcode here as per instructions
        let country: String?
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name, domain, phone, website, address, city, state, zip, zipcode, country
        case properties
    }

    init(from decoder: Decoder) throws {
      
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? ""

        // Try HubSpot nested properties first
        if let props = try? c.decode(Properties.self, forKey: .properties) {
            self.name = props.name
            self.domain = props.domain
            self.phone = props.phone
            self.website = props.website
            self.address = props.address
            self.city = props.city
            self.state = props.state

            var zipValue: String? = props.zip
            if zipValue == nil {
                // Support legacy nested `zipcode` / alternative keys
                if let rawProps = try? c.decode([String: String?].self, forKey: .properties) {
                    zipValue = rawProps["zip"] ?? nil
                    if zipValue == nil {
                        zipValue = rawProps["zipcode"] ?? nil
                    }
                }
            }
            self.zip = zipValue

            self.country = props.country
            return
        }

        // Fallback: flat JSON
        self.name = try? c.decode(String.self, forKey: .name)
        self.domain = try? c.decode(String.self, forKey: .domain)
        self.phone = try? c.decode(String.self, forKey: .phone)
        self.website = try? c.decode(String.self, forKey: .website)
        self.address = try? c.decode(String.self, forKey: .address)
        self.city = try? c.decode(String.self, forKey: .city)
        self.state = try? c.decode(String.self, forKey: .state)
        // Support both `zip` and legacy `zipcode`
        if let z = try? c.decode(String.self, forKey: .zip) {
            self.zip = z
        } else {
            self.zip = try? c.decode(String.self, forKey: .zipcode)
        }
        self.country = try? c.decode(String.self, forKey: .country)
    }
}

struct HubSpotContactDetail: Decodable {
    let id: String
    let firstname: String?
    let lastname: String?
    let email: String?
    let phone: String?
    let mobilephone: String?
    let jobtitle: String?

    private struct Properties: Decodable {
        let firstname: String?
        let lastname: String?
        let email: String?
        let phone: String?
        let mobilephone: String?
        let jobtitle: String?
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case firstname, lastname, email, phone, mobilephone, jobtitle
        case properties
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? ""

        // Try HubSpot nested properties first
        if let props = try? c.decode(Properties.self, forKey: .properties) {
            self.firstname = props.firstname
            self.lastname = props.lastname
            self.email = props.email
            self.phone = props.phone
            self.mobilephone = props.mobilephone
            self.jobtitle = props.jobtitle
            return
        }

        // Fallback: flat JSON
        self.firstname = try? c.decode(String.self, forKey: .firstname)
        self.lastname = try? c.decode(String.self, forKey: .lastname)
        self.email = try? c.decode(String.self, forKey: .email)
        self.phone = try? c.decode(String.self, forKey: .phone)
        self.mobilephone = try? c.decode(String.self, forKey: .mobilephone)
        self.jobtitle = try? c.decode(String.self, forKey: .jobtitle)
    }
}

// MARK: - HubSpotService (backend-first)

final class HubSpotService: ObservableObject {
    static let shared = HubSpotService()

    // Published state for Settings UI
    @Published var isConnected: Bool = false
    @Published var connectedHubId: String? = nil

    private init() {}

    // MARK: - Config (from Info.plist)

    /// Base URL of your Vercel backend, e.g. https://scotsman.vercel.app
    private var backendBaseURL: URL {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SCOTSMAN_BACKEND_BASE_URL") as? String) ?? "https://scotsman.vercel.app"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed) ?? URL(string: "https://scotsman.vercel.app")!
    }

    /// API key that your backend expects in the header `x-scotsman-key`
    private var apiKey: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SCOTSMAN_API_KEY") as? String) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OAuth: start in browser via backend

    /// Opens the backend authorize endpoint, which redirects to HubSpot OAuth.
    func connectInBrowser() {
        let url = backendBaseURL.appendingPathComponent("api/hubspot/authorize")
        UIApplication.shared.open(url)
    }

    /// Optional: If you want a "Disconnect" UX, you'd implement a backend endpoint to revoke/clear tokens.
    func disconnectLocally() {
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectedHubId = nil
        }
    }

    // MARK: - Status

    /// Calls GET /api/hubspot/status and updates isConnected.
    func refreshConnectionStatus(completion: ((Bool) -> Void)? = nil) {
        let url = backendBaseURL.appendingPathComponent("api/hubspot/status")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !apiKey.isEmpty {
            req.setValue(apiKey, forHTTPHeaderField: "x-scotsman-key")
        }

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                DispatchQueue.main.async {
                    print("[HubSpotService] status error:", error.localizedDescription)
                    self.isConnected = false
                    self.connectedHubId = nil
                    completion?(false)
                }
                return
            }

            guard let data else {
                DispatchQueue.main.async {
                    print("[HubSpotService] status error: no data")
                    self.isConnected = false
                    self.connectedHubId = nil
                    completion?(false)
                }
                return
            }

            Task { @MainActor in
                do {
                    let decoded = try JSONDecoder().decode(HubSpotStatusResponse.self, from: data)
                    self.isConnected = decoded.ok && decoded.connected
                    self.connectedHubId = decoded.hub_id
                    completion?(self.isConnected)
                } catch {
                    // If backend returned HTML (e.g. 404 page), decoding fails.
                    let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                    print("[HubSpotService] status decode error:", error.localizedDescription)
                    print("[HubSpotService] status raw body (first 200):", String(body.prefix(200)))
                    self.isConnected = false
                    self.connectedHubId = nil
                    completion?(false)
                }
            }
        }.resume()
    }

    // MARK: - Deals search + bundle (for import)

    /// Calls GET /api/hubspot/deals?search=...&limit=...
    func searchDeals(query: String, limit: Int = 20, completion: @escaping (Result<[HubSpotDealSearchItem], Error>) -> Void) {
        var components = URLComponents(url: backendBaseURL.appendingPathComponent("api/hubspot/deals"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 50)))
        ]

        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        if !apiKey.isEmpty {
            req.setValue(apiKey, forHTTPHeaderField: "x-scotsman-key")
        }

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data else {
                DispatchQueue.main.async { completion(.success([])) }
                return
            }
            Task { @MainActor in
                do {
                    let decoded = try JSONDecoder().decode(HubSpotDealSearchResponse.self, from: data)
                    completion(.success(decoded.ok ? decoded.results : []))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Calls GET /api/hubspot/deals/{dealId}/bundle
    func fetchDealBundle(dealId: String, completion: @escaping (Result<HubSpotDealBundle, Error>) -> Void) {
        let url = backendBaseURL
            .appendingPathComponent("api/hubspot/deals")
            .appendingPathComponent(dealId)
            .appendingPathComponent("bundle")

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !apiKey.isEmpty {
            req.setValue(apiKey, forHTTPHeaderField: "x-scotsman-key")
        }

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data else {
                DispatchQueue.main.async { completion(.failure(NSError(domain: "HubSpotService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])) ) }
                return
            }
            Task { @MainActor in
                do {
                    let decoded = try JSONDecoder().decode(HubSpotDealBundle.self, from: data)
#if DEBUG
                    let cId = decoded.company?.id ?? "<nil>"
                    print("[HubSpotService] bundle ok=\(decoded.ok) dealId=\(decoded.deal.id) dealname=\(decoded.deal.dealname) companyId=\(cId) contacts=\(decoded.contacts.count)")
                    if let company = decoded.company {
                        print("[HubSpotService] bundle company name=\(company.name) domain=\(company.domain ?? "<nil>")")
                        print("[HubSpotService] bundle company phone=\(company.phone ?? "<nil>") website=\(company.website ?? "<nil>") address=\(company.address ?? "<nil>") city=\(company.city ?? "<nil>") state=\(company.state ?? "<nil>") zip=\(company.zip ?? "<nil>") country=\(company.country ?? "<nil>")")
                    }
                    if let first = decoded.contacts.first {
                        print("[HubSpotService] bundle first contact id=\(first.id) name=\(first.firstname) \(first.lastname) email=\(first.email ?? "<nil>") phone=\(first.phone ?? "<nil>") mobile=\(first.mobilephone ?? "<nil>") job=\(first.jobtitle ?? "<nil>")")
                    }
#endif
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - New: Company detail fetch

    /// Calls GET /api/hubspot/companies/{companyId}
    func fetchCompanyDetail(companyId: String, completion: @escaping (Result<HubSpotCompanyDetail, Error>) -> Void) {
        let url = backendBaseURL
            .appendingPathComponent("api/hubspot/companies")
            .appendingPathComponent(companyId)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !apiKey.isEmpty {
            req.setValue(apiKey, forHTTPHeaderField: "x-scotsman-key")
        }

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HubSpotService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                }
                return
            }
            Task { @MainActor in
                do {
                    let decoded = try JSONDecoder().decode(HubSpotCompanyDetail.self, from: data)
#if DEBUG
                    print("[HubSpotService] company detail id=\(decoded.id)")
                    print("[HubSpotService] company detail name=\(decoded.name ?? "<nil>") domain=\(decoded.domain ?? "<nil>")")
                    print("[HubSpotService] company detail phone=\(decoded.phone ?? "<nil>") website=\(decoded.website ?? "<nil>")")
                    print("[HubSpotService] company detail address=\(decoded.address ?? "<nil>") city=\(decoded.city ?? "<nil>") state=\(decoded.state ?? "<nil>") zip=\(decoded.zip ?? "<nil>") country=\(decoded.country ?? "<nil>")")
#endif
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    // MARK: - New: Contact detail fetch

    /// Calls GET /api/hubspot/contacts/{contactId}
    func fetchContactDetail(contactId: String, completion: @escaping (Result<HubSpotContactDetail, Error>) -> Void) {
        let url = backendBaseURL
            .appendingPathComponent("api/hubspot/contacts")
            .appendingPathComponent(contactId)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !apiKey.isEmpty {
            req.setValue(apiKey, forHTTPHeaderField: "x-scotsman-key")
        }

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "HubSpotService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                }
                return
            }
            Task { @MainActor in
                do {
                    let decoded = try JSONDecoder().decode(HubSpotContactDetail.self, from: data)
#if DEBUG
                    print("[HubSpotService] contact detail id=\(decoded.id)")
                    print("[HubSpotService] contact detail name=\(decoded.firstname ?? "<nil>") \(decoded.lastname ?? "<nil>")")
                    print("[HubSpotService] contact detail email=\(decoded.email ?? "<nil>") phone=\(decoded.phone ?? "<nil>") mobile=\(decoded.mobilephone ?? "<nil>")")
                    print("[HubSpotService] contact detail jobtitle=\(decoded.jobtitle ?? "<nil>")")
#endif
                    completion(.success(decoded))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}
