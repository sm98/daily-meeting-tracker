import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var auth = GoogleAuthManager.shared
    var onAccountsChanged: () -> Void = {}

    @State private var isConnecting = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        print("[SettingsView] launch-at-login toggle failed: \(error)")
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Divider()

            Text("Connected Google Accounts")
                .font(.headline)

            if auth.accounts.isEmpty {
                Text("No accounts connected yet.")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(auth.accounts) { account in
                        AccountRow(
                            account: account,
                            auth: auth,
                            onRemove: {
                                auth.disconnect(account)
                                onAccountsChanged()
                            },
                            onLabelChanged: onAccountsChanged
                        )
                        Divider()
                    }
                }
            }

            Button(isConnecting ? "Connecting…" : "+ Add Google Account") {
                isConnecting = true
                auth.connect { result in
                    DispatchQueue.main.async {
                        isConnecting = false
                        if case .success = result {
                            onAccountsChanged()
                        }
                    }
                }
            }
            .disabled(isConnecting)

            Spacer()
        }
        .padding(20)
        .frame(width: 360, height: 380, alignment: .top)
    }
}

private struct AccountRow: View {
    let account: ConnectedAccount
    let auth: GoogleAuthManager
    let onRemove: () -> Void
    let onLabelChanged: () -> Void

    @State private var label: String

    init(account: ConnectedAccount, auth: GoogleAuthManager, onRemove: @escaping () -> Void, onLabelChanged: @escaping () -> Void) {
        self.account = account
        self.auth = auth
        self.onRemove = onRemove
        self.onLabelChanged = onLabelChanged
        _label = State(initialValue: account.label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                // Commits on Return only — committing per keystroke would
                // trigger a full multi-account event refetch on every
                // character typed, burning API quota for nothing.
                TextField("Label", text: $label, onCommit: commitLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                Button("Remove", action: onRemove)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.system(size: 12))
            }
            Text(account.email)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func commitLabel() {
        auth.updateLabel(label, for: account)
        onLabelChanged()
    }
}
