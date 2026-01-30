import Foundation
import UIKit
import Combine

// MARK: - HubSpot backend response models (file-scope to avoid Swift 6 actor isolation issues)

struct HubSpotStatusResponse: Decodable {
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

struct HubSpotDealSearchResponse: Decodable {
    let ok: Bool
    let results: [HubSpotDealSearchItem]
}

struct HubSpotDealBundle: Decodable {
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
    }
    struct Contact: Decodable {
        let id: String
        let firstname: String
        let lastname: String
        let email: String?
    }

    let ok: Bool
    let deal: Deal
    let company: Company?
    let contacts: [Contact]
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

            do {
                let decoded = try JSONDecoder().decode(HubSpotStatusResponse.self, from: data)
                DispatchQueue.main.async {
                    self.isConnected = decoded.ok && decoded.connected
                    self.connectedHubId = decoded.hub_id
                    completion?(self.isConnected)
                }
            } catch {
                // If backend returned HTML (e.g. 404 page), decoding fails.
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                DispatchQueue.main.async {
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
            do {
                let decoded = try JSONDecoder().decode(HubSpotDealSearchResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(decoded.ok ? decoded.results : []))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
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
            do {
                let decoded = try JSONDecoder().decode(HubSpotDealBundle.self, from: data)
                DispatchQueue.main.async { completion(.success(decoded)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }
}
