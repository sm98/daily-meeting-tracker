import Foundation
import AppKit
import CryptoKit
import Security

/// Handles Google's OAuth 2.0 Authorization Code flow with PKCE for any
/// number of connected accounts. Each account's refresh token is stored in
/// Keychain keyed by that account's email; the list of connected emails
/// (non-sensitive) lives in UserDefaults so Settings can show it without
/// touching Keychain until a token is actually needed.
final class GoogleAuthManager: ObservableObject {
    static let shared = GoogleAuthManager()

    @Published private(set) var accounts: [ConnectedAccount]

    private let keychainService = "com.menubarcalendar.google"
    private let accountsDefaultsKey = "com.menubarcalendar.connectedAccounts"
    // Kept alive only for the duration of one in-flight connect() attempt.
    private var activeServer: LoopbackServer?

    private init() {
        accounts = Self.loadAccounts(defaultsKey: "com.menubarcalendar.connectedAccounts")
    }

    func connect(completion: @escaping (Result<ConnectedAccount, Error>) -> Void) {
        guard activeServer == nil else {
            print("[GoogleAuthManager] connect() called while an attempt is already in flight, ignoring")
            return
        }

        let verifier = Self.randomCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        let server = LoopbackServer()
        activeServer = server

        server.waitForCode { [weak self] result in
            guard let self else { return }
            self.activeServer = nil
            switch result {
            case .success(let code):
                self.exchangeCode(code, verifier: verifier, redirectURI: server.redirectURI, completion: completion)
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: server.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            // Forces the account picker so adding a second account doesn't
            // silently re-auth whichever Google account is already signed
            // in in the browser.
            URLQueryItem(name: "prompt", value: "consent select_account")
        ]
        NSWorkspace.shared.open(components.url!)
    }

    func disconnect(_ account: ConnectedAccount) {
        KeychainStore.delete(service: keychainService, account: account.email)
        accounts.removeAll { $0.id == account.id }
        Self.saveAccounts(accounts, defaultsKey: accountsDefaultsKey)
    }

    func updateLabel(_ label: String, for account: ConnectedAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        accounts[index].label = trimmed.isEmpty ? account.email : trimmed
        Self.saveAccounts(accounts, defaultsKey: accountsDefaultsKey)
    }

    /// Exchanges a stored refresh token for a short-lived access token.
    /// Call this before every Calendar API request rather than caching the
    /// access token — it's cheap and avoids tracking expiry manually.
    func fetchAccessToken(for account: ConnectedAccount, completion: @escaping (Result<String, Error>) -> Void) {
        guard let refreshToken = KeychainStore.read(service: keychainService, account: account.email) else {
            completion(.failure(URLError(.userAuthenticationRequired)))
            return
        }
        postToken(params: [
            "client_id": GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]) { result in
            switch result {
            case .success(let token):
                completion(.success(token.access_token))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func exchangeCode(_ code: String, verifier: String, redirectURI: String, completion: @escaping (Result<ConnectedAccount, Error>) -> Void) {
        postToken(params: [
            "client_id": GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let token):
                guard let refreshToken = token.refresh_token else {
                    DispatchQueue.main.async { completion(.failure(URLError(.badServerResponse))) }
                    return
                }
                guard let idToken = token.id_token, let email = Self.decodeEmail(from: idToken) else {
                    DispatchQueue.main.async { completion(.failure(URLError(.badServerResponse))) }
                    return
                }
                KeychainStore.save(refreshToken, service: self.keychainService, account: email)
                let account = ConnectedAccount(email: email)
                DispatchQueue.main.async {
                    if !self.accounts.contains(account) {
                        self.accounts.append(account)
                        Self.saveAccounts(self.accounts, defaultsKey: self.accountsDefaultsKey)
                    }
                    completion(.success(account))
                }
            case .failure(let error):
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func postToken(params: [String: String], completion: @escaping (Result<TokenResponse, Error>) -> Void) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                print("[GoogleAuthManager] token request network error: \(error)")
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                print("[GoogleAuthManager] token request failed, status \(http.statusCode): \(body)")
            }
            guard let data, let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
            completion(.success(token))
        }.resume()
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let id_token: String?
    }

    private static func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URLEncode(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(hash))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Pulls the `email` claim out of the id_token JWT without verifying
    /// its signature — acceptable here since it came directly from Google
    /// over TLS moments earlier, not from an untrusted third party.
    private static func decodeEmail(from idToken: String) -> String? {
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard
            let data = Data(base64Encoded: payload),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let email = json["email"] as? String
        else { return nil }
        return email
    }

    private static func loadAccounts(defaultsKey: String) -> [ConnectedAccount] {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let accounts = try? JSONDecoder().decode([ConnectedAccount].self, from: data)
        else { return [] }
        return accounts
    }

    private static func saveAccounts(_ accounts: [ConnectedAccount], defaultsKey: String) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
