import SwiftUI
import AppKit
import UniformTypeIdentifiers

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case audioInput = "Audio Input"
    case audioOutput = "Audio Output"
    case userInterface = "User Interface"
    case shortcuts = "Shortcuts"
    case network = "Network"
    case messages = "Messages"
    case overlay = "Overlay"
    case tokens = "Access Tokens"
    case certificates = "Certificates"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .audioInput: return "mic.fill"
        case .audioOutput: return "speaker.wave.3.fill"
        case .userInterface: return "macwindow"
        case .shortcuts: return "keyboard"
        case .network: return "network"
        case .messages: return "bubble.left.and.bubble.right.fill"
        case .overlay: return "pip.fill"
        case .tokens: return "key.fill"
        case .certificates: return "person.badge.shield.checkmark.fill"
        }
    }

    // Backward compatibility aliases
    public static var general: SettingsTab { .userInterface }
    public static var audio: SettingsTab { .audioInput }
}

/// Comprehensive Settings dialog supporting Audio Input, Audio Output, User Interface,
/// Shortcuts, Network, Messages, Overlay, Access Tokens, and Certificates with persistence footer controls.
public struct SettingsModal: View {
    @Bindable public var store: MumbleStore
    @Binding public var isPresented: Bool
    @State public var selectedTab: SettingsTab = .audioInput

    @State private var newTokenText: String = ""

    public init(store: MumbleStore, isPresented: Binding<Bool>, initialTab: SettingsTab = .audioInput) {
        self.store = store
        self._isPresented = isPresented
        self._selectedTab = State(initialValue: initialTab)
    }

    public var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.iconName)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.vertical, 2)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            VStack(spacing: 0) {
                // Header Bar
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: selectedTab.iconName)
                            .font(.title3)
                            .foregroundStyle(store.accentTint)
                        Text(selectedTab.rawValue)
                            .font(.title3.bold())
                    }

                    Spacer()

                    Button("Close") {
                        isPresented = false
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.85))

                Divider()

                // Content View for Selected Tab
                Group {
                    switch selectedTab {
                    case .audioInput:
                        AudioInputSettingsTab(store: store)
                    case .audioOutput:
                        AudioOutputSettingsTab(store: store)
                    case .userInterface:
                        UserInterfaceSettingsTab(store: store)
                    case .shortcuts:
                        ShortcutsSettingsTab(store: store)
                    case .network:
                        NetworkSettingsTab(store: store)
                    case .messages:
                        MessagesSettingsTab(store: store)
                    case .overlay:
                        OverlaySettingsTab(store: store)
                    case .tokens:
                        AccessTokensSettingsTab(store: store, newTokenText: $newTokenText)
                    case .certificates:
                        CertificatesSettingsTab(store: store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // 8. Settings Footer Actions
                SettingsFooterView(store: store, currentTab: selectedTab) {
                    isPresented = false
                }
            }
        }
        .frame(minWidth: 840, idealWidth: 900, minHeight: 620, idealHeight: 680)
    }
}

// MARK: - Access Tokens Settings Tab

struct AccessTokensSettingsTab: View {
    @Bindable var store: MumbleStore
    @Binding var newTokenText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsCard {
                    SettingsSectionHeader(
                        "Server Access Tokens",
                        systemImage: "key.fill",
                        subtitle: "Access tokens grant access to password-protected channels and private groups on Mumble servers without needing server administrator status."
                    )

                    // Add Token Field
                    HStack(spacing: 10) {
                        TextField("Enter new access token (password)...", text: $newTokenText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                submitToken()
                            }

                        Button(action: submitToken) {
                            Label("Add Token", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newTokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Divider()

                    // Token List
                    if store.accessTokens.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "key.slash")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                            Text("No access tokens configured")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Add tokens above to automatically unlock restricted channels on connect.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(store.accessTokens.enumerated()), id: \.offset) { index, token in
                                HStack {
                                    Image(systemName: "key.fill")
                                        .foregroundStyle(Color.accentColor)

                                    Text(token)
                                        .font(.body.monospaced())

                                    Spacer()

                                    Button(action: {
                                        store.removeAccessToken(at: index)
                                    }) {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove Token")
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
        }
    }

    private func submitToken() {
        let trimmed = newTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addAccessToken(trimmed)
        newTokenText = ""
    }
}

// MARK: - Certificates Settings Tab

struct CertificatesSettingsTab: View {
    @Bindable var store: MumbleStore
    @State private var exportPassword = ""
    @State private var showingExportAlert = false
    @State private var importPassword = ""
    @State private var showingImportAlert = false
    @State private var selectedImportUrl: URL? = nil
    @State private var statusMessage: String? = nil
    @State private var isError: Bool = false
    @State private var showingRegenConfirmation = false
    @State private var didCopyFingerprint = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Certificate Identity Card
                SettingsCard {
                    SettingsSectionHeader(
                        "Client Identity & Certificate",
                        systemImage: "person.badge.shield.checkmark.fill",
                        subtitle: "Swimble uses client-side X.509 certificates to authenticate with Murmur servers without passwords. Your certificate is stored securely in the macOS Keychain."
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("SHA-1 Fingerprint:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(store.certFingerprint, forType: .string)
                                didCopyFingerprint = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    didCopyFingerprint = false
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: didCopyFingerprint ? "checkmark" : "doc.on.doc")
                                    Text(didCopyFingerprint ? "Copied" : "Copy")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Text(store.certFingerprint)
                            .font(.system(.caption, design: .monospaced))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .textSelection(.enabled)
                    }

                    if let msg = statusMessage {
                        Text(msg)
                            .font(.caption.bold())
                            .foregroundStyle(isError ? .red : .green)
                    }
                }

                // Actions: Export, Import, Generate
                SettingsCard {
                    SettingsSectionHeader(
                        "Certificate Backup & Transfer",
                        systemImage: "arrow.triangle.2.circlepath",
                        subtitle: "Export your certificate as a standard PKCS#12 (.p12) bundle to back it up or transfer your registered identity from classic Mumble."
                    )

                    HStack(spacing: 12) {
                        Button(action: {
                            exportPassword = ""
                            showingExportAlert = true
                        }) {
                            Label("Export Certificate (.p12)...", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.pkcs12, .data]
                            panel.allowsMultipleSelection = false
                            panel.canChooseDirectories = false
                            if panel.runModal() == .OK, let url = panel.url {
                                selectedImportUrl = url
                                importPassword = ""
                                showingImportAlert = true
                            }
                        }) {
                            Label("Import Certificate (.p12)...", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(role: .destructive, action: {
                            showingRegenConfirmation = true
                        }) {
                            Label("Generate New...", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
        }
        .alert("Export Certificate (.p12)", isPresented: $showingExportAlert) {
            SecureField("Password (optional)", text: $exportPassword)
            Button("Export") {
                performExport(password: exportPassword)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Set an optional password to encrypt your exported PKCS#12 bundle.")
        }
        .alert("Import Certificate (.p12)", isPresented: $showingImportAlert) {
            SecureField("Password (if encrypted)", text: $importPassword)
            Button("Import") {
                if let url = selectedImportUrl {
                    performImport(url: url, password: importPassword)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the password for the PKCS#12 certificate file.")
        }
        .alert("Generate New Certificate?", isPresented: $showingRegenConfirmation) {
            Button("Generate", role: .destructive) {
                let newId = generateClientIdentity(commonName: "Swimble User")
                store.updateClientIdentity(newId)
                statusMessage = "Successfully generated and saved new identity."
                isError = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Generating a new certificate will replace your current identity in Keychain. You may lose server registrations tied to your existing certificate.")
        }
    }

    private func performExport(password: String) {
        do {
            let data = try exportIdentityToPkcs12(
                certPem: store.clientIdentity.certPem,
                keyPem: store.clientIdentity.keyPem,
                password: password
            )
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pkcs12]
            panel.nameFieldStringValue = "Swimble-Certificate.p12"
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
                statusMessage = "Certificate exported successfully."
                isError = false
            }
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
            isError = true
        }
    }

    private func performImport(url: URL, password: String) {
        do {
            let data = try Data(contentsOf: url)
            let imported = try importIdentityFromPkcs12(p12Bytes: data, password: password)
            store.updateClientIdentity(imported)
            statusMessage = "Certificate imported successfully into Keychain."
            isError = false
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
            isError = true
        }
    }
}
