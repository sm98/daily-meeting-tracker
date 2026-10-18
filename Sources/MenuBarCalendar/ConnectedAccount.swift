import Foundation

/// The account's email doubles as its identifier — it's what we key the
/// Keychain-stored refresh token by. `label` is what's actually shown in
/// the UI (event rows, Settings) so users don't have to stare at raw
/// email addresses.
struct ConnectedAccount: Identifiable, Codable, Equatable {
    var id: String { email }
    let email: String
    var label: String

    /// Defaults a new account's label to the part of the email before "@".
    init(email: String, label: String? = nil) {
        self.email = email
        self.label = label ?? String(email.split(separator: "@").first ?? Substring(email))
    }
}
