import Foundation
import AuthenticationServices
import Security
import UIKit
import Combine

// MARK: - HubSpotService

class HubSpotService: NSObject, ObservableObject {
    static let shared = HubSpotService()

    // MARK: OAuth Config
    private let clientID = "<YOUR_HUBSPOT_CLIENT_ID>" // Replace with your client ID
    private let clientSecret = "<YOUR_HUBSPOT_CLIENT_SECRET>" // Replace with your client secret
    private let redirectURI = "<YOUR_CALLBACK_URI>" // e.g., "com.yourapp://oauth-callback"
    private let scopes = "contacts deals companies"
    private let authURL = "https://app.hubspot.com/oauth/authorize"
    private let tokenURL = "https://api.hubapi.com/oauth/v1/token"

    // MARK: Token Storage
    private(set) var accessToken: String? {
        get { HubSpotService.loadKeychain("hs_access_token") }
        set { HubSpotService.saveKeychain("hs_access_token", value: newValue) }
    }
    private(set) var refreshToken: String? {
        get { HubSpotService.loadKeychain("hs_refresh_token") }
        set { HubSpotService.saveKeychain("hs_refresh_token", value: newValue) }
    }
    
    @Published var isConnected: Bool = false
    private var currentAuthSession: ASWebAuthenticationSession?

    // MARK: - Public API

    func startOAuth(completion: @escaping (Bool) -> Void) {
        var urlComponents = URLComponents(string: authURL)!
        urlComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code")
        ]
        guard let url = urlComponents.url else { completion(false); return }

        currentAuthSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: URL(string: redirectURI)?.scheme
        ) { [weak self] callbackURL, error in
            guard let self = self, let callbackURL = callbackURL, error == nil,
                let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value
            else {
                completion(false)
                return
            }
            self.exchangeCodeForToken(code: code, completion: completion)
        }
        currentAuthSession?.presentationContextProvider = self
        currentAuthSession?.start()
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        isConnected = false
    }

    // MARK: - API Calls Example

    func searchDeals(named name: String, completion: @escaping ([HubSpotDeal]) -> Void) {
        // Example implementation for searching deals by name
        guard let token = accessToken else { completion([]); return }
        guard var urlComponents = URLComponents(string: "https://api.hubapi.com/crm/v3/objects/deals") else {
            completion([])
            return
        }
        // Set query to filter deals by name
        // HubSpot API expects filters as JSON in the request body, but here is a simple placeholder
        urlComponents.queryItems = [
            URLQueryItem(name: "properties", value: "dealname"),
            URLQueryItem(name: "limit", value: "20")
        ]
        
        guard let url = urlComponents.url else {
            completion([])
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = responseJSON["results"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let deals: [HubSpotDeal] = results.compactMap { item in
                guard let id = item["id"] as? String,
                      let properties = item["properties"] as? [String: Any],
                      let dealName = properties["dealname"] as? String else { return nil }
                return HubSpotDeal(id: id, name: dealName)
            }
            DispatchQueue.main.async { completion(deals) }
        }.resume()
    }

    // Add other API/CRUD as needed

    // MARK: - Private

    private func exchangeCodeForToken(code: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: tokenURL) else { completion(false); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=authorization_code&client_id=\(clientID)&client_secret=\(clientSecret)&redirect_uri=\(redirectURI)&code=\(code)"
        req.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, response, error in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.accessToken = access
            self.refreshToken = refresh
            DispatchQueue.main.async {
                self.isConnected = true
                completion(true)
            }
        }.resume()
    }

    // MARK: - Keychain Helpers

    static func saveKeychain(_ key: String, value: String?) {
        guard let value = value?.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "HubSpotService",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = query.merging([kSecValueData as String: value]) { $1 }
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func loadKeychain(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "HubSpotService",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        guard status == errSecSuccess, let data = dataTypeRef as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension HubSpotService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if #available(iOS 15.0, *) {
            // Prefer creating ASPresentationAnchor with windowScene if available
            if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                return ASPresentationAnchor(windowScene: windowScene)
            }
        }
        // Fallback for older iOS versions
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - HubSpotDeal Placeholder (expand as needed)

struct HubSpotDeal: Identifiable {
    let id: String
    let name: String
    // Add other deal fields as needed
}
