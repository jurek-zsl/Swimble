import SwiftUI
import AppKit

/// Certificate Management Wizard allowing inspection, export, import, and generation of Mumble X.509 certificates.
public struct CertificateWizardModal: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss

    @State private var showGenerateConfirm: Bool = false
    @State private var statusMessage: String? = nil
    @State private var isErrorMessage: Bool = false
    @State private var showingImportPasswordAlert: Bool = false
    @State private var pendingImportData: Data? = nil
    @State private var pendingImportFilename: String = ""
    @State private var importPassword: String = ""
    @State private var showingExportPasswordAlert: Bool = false
    @State private var pendingExportURL: URL? = nil
    @State private var exportPassword: String = ""

    public init(store: MumbleStore) {
        self.store = store
    }

    private var formattedFingerprint: String {
        store.certFingerprint
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(store.accentTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Certificate Wizard")
                            .font(.headline.bold())
                        Text("Manage your cryptographic identity used for server authentication.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))

            Divider()

            VStack(spacing: 16) {
                // Status banner
                if let msg = statusMessage {
                    HStack(spacing: 8) {
                        Image(systemName: isErrorMessage ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(isErrorMessage ? Color.red : Color.green)
                        Text(msg)
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(10)
                    .background((isErrorMessage ? Color.red : Color.green).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                // 1. Current Certificate Info Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                            .foregroundStyle(store.accentTint)
                        Text("Active Client Identity")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("SECURE")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.18), in: Capsule())
                            .foregroundStyle(.green)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SHA-1 Fingerprint:")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(formattedFingerprint.isEmpty ? "Generating..." : formattedFingerprint)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .textSelection(.enabled)

                            Spacer()

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(formattedFingerprint, forType: .string)
                                statusMessage = "Fingerprint copied to clipboard!"
                                isErrorMessage = false
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }

                // 2. Certificate Actions
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        // Export .p12
                        Button(action: exportCertificate) {
                            VStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title2)
                                Text("Export Backup (.p12)")
                                    .font(.subheadline.bold())
                                Text("Save certificate to transfer to other computers.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        // Import .p12
                        Button(action: importCertificate) {
                            VStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.title2)
                                Text("Import Backup (.p12)")
                                    .font(.subheadline.bold())
                                Text("Load an existing Mumble certificate file.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }

                    // Generate New
                    Button(action: {
                        showGenerateConfirm = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Generate New Certificate")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 420)
        .onChange(of: store.identityError) { _, error in if let error { statusMessage = error; isErrorMessage = true } }
        .confirmationDialog(
            "Generate New Certificate?",
            isPresented: $showGenerateConfirm,
            titleVisibility: .visible
        ) {
            Button("Generate New Certificate", role: .destructive) {
                let newIdent = generateClientIdentity(commonName: "Swimble User")
                installIdentity(newIdent, message: "New client certificate generated successfully!")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Generating a new certificate will change your unique identity. On servers where you were registered or had ACL permissions, you may need to register again.")
        }
        .alert("Export Certificate (.p12)", isPresented: $showingExportPasswordAlert) {
            SecureField("Password (leave blank for none)", text: $exportPassword)
            Button("Export") {
                if let url = pendingExportURL {
                    do {
                        let p12Data = try exportIdentityToPkcs12(
                            certPem: store.clientIdentity.certPem,
                            keyPem: store.clientIdentity.keyPem,
                            password: exportPassword
                        )
                        try p12Data.write(to: url)
                        statusMessage = "Certificate exported to \(url.lastPathComponent) successfully!"
                        isErrorMessage = false
                    } catch {
                        statusMessage = "Failed to export certificate: \(error.localizedDescription)"
                        isErrorMessage = true
                    }
                }
                pendingExportURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingExportURL = nil
            }
        } message: {
            Text("Optionally protect your exported PKCS#12 certificate file with a password.")
        }
        .alert("Certificate Password", isPresented: $showingImportPasswordAlert) {
            SecureField("Enter certificate password", text: $importPassword)
            Button("Import") {
                if let data = pendingImportData {
                    do {
                        let imported = try importIdentityFromPkcs12(p12Bytes: data, password: importPassword)
                        installIdentity(imported, message: "Certificate imported successfully!")
                    } catch {
                        statusMessage = "Failed to import certificate: \(error.localizedDescription)"
                        isErrorMessage = true
                    }
                }
                pendingImportData = nil
            }
            Button("Cancel", role: .cancel) {
                pendingImportData = nil
            }
        } message: {
            Text("This PKCS#12 certificate bundle from \(pendingImportFilename) is protected with a password. Please enter the password to unlock it.")
        }
    }

    private func installIdentity(_ identity: ClientIdentity, message: String) {
        statusMessage = "Saving identity to Keychain…"
        Task { @MainActor in
            do { try await store.updateClientIdentity(identity); statusMessage = message; isErrorMessage = false }
            catch { statusMessage = "Identity was not changed: \(error.localizedDescription)"; isErrorMessage = true }
        }
    }

    private func exportCertificate() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pkcs12]
        savePanel.nameFieldStringValue = "Swimble_Certificate.p12"
        savePanel.title = "Export Mumble Certificate (.p12)"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            pendingExportURL = url
            exportPassword = ""
            showingExportPasswordAlert = true
        }
    }

    private func importCertificate() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.pkcs12]
        openPanel.allowsMultipleSelection = false
        openPanel.title = "Import Mumble Certificate (.p12)"

        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let data = try Data(contentsOf: url)
                // First attempt import without password (for unencrypted or blank password archives)
                do {
                    let imported = try importIdentityFromPkcs12(p12Bytes: data, password: "")
                    installIdentity(imported, message: "Certificate imported from \(url.lastPathComponent) successfully!")
                } catch {
                    // Requires password or failed with blank password: prompt user
                    pendingImportData = data
                    pendingImportFilename = url.lastPathComponent
                    importPassword = ""
                    showingImportPasswordAlert = true
                }
            } catch {
                statusMessage = "Failed to read certificate file: \(error.localizedDescription)"
                isErrorMessage = true
            }
        }
    }
}
