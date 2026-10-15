import SwiftUI
import AppKit
import UniformTypeIdentifiers

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general = "General"
    case audio = "Audio"
    case shortcuts = "Shortcuts"
    case tokens = "Access Tokens"
    case certificates = "Certificates"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .general: return "gearshape.fill"
        case .audio: return "waveform"
        case .shortcuts: return "keyboard"
        case .tokens: return "key.fill"
        case .certificates: return "person.badge.shield.checkmark.fill"
        }
    }
}

/// Comprehensive Settings Sheet supporting Audio devices, live VAD calibration, Loopback test,
/// Global Push-to-Talk shortcuts, Mumble ACL Server Access Tokens, and X.509 Certificate Management.
public struct SettingsModal: View {
    @Bindable public var store: MumbleStore
    @Binding public var isPresented: Bool
    @State public var selectedTab: SettingsTab = .general

    @State private var newTokenText: String = ""
    private var deviceManager = CoreAudioDeviceManager.shared

    public init(store: MumbleStore, isPresented: Binding<Bool>, initialTab: SettingsTab = .general) {
        self.store = store
        self._isPresented = isPresented
        self._selectedTab = State(initialValue: initialTab)
    }

    private var audioEngine: MacAudioEngine {
        store.audioEngine
    }

    private var globalPTT: GlobalPTT {
        store.globalPTT
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 16) {
                Text("Settings")
                    .font(.title2.bold())

                Spacer()

                // Tab Selector
                Picker("Tab", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.iconName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 480)

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))

            Divider()

            // Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsTab(store: store)
                    case .audio:
                        AudioSettingsTab(store: store, deviceManager: deviceManager)
                    case .shortcuts:
                        ShortcutsSettingsTab(store: store)
                    case .tokens:
                        AccessTokensSettingsTab(store: store, newTokenText: $newTokenText)
                    case .certificates:
                        CertificatesSettingsTab(store: store)
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 640, height: 540)
    }
}

// MARK: - 1. Audio Settings Tab

struct AudioSettingsTab: View {
    @Bindable var store: MumbleStore
    var deviceManager: CoreAudioDeviceManager

    private var audioEngine: MacAudioEngine {
        store.audioEngine
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Devices Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Audio Devices")
                    .font(.headline)

                // Input Device Picker
                HStack {
                    Label("Input Device", systemImage: "mic.fill")
                        .frame(width: 140, alignment: .leading)
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { deviceManager.selectedInputDeviceID },
                        set: { deviceManager.setInputDevice($0) }
                    )) {
                        ForEach(deviceManager.inputDevices) { dev in
                            Text(dev.name).tag(dev.id)
                        }
                    }
                    .labelsHidden()
                }

                // Output Device Picker
                HStack {
                    Label("Output Device", systemImage: "speaker.wave.2.fill")
                        .frame(width: 140, alignment: .leading)
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { deviceManager.selectedOutputDeviceID },
                        set: { deviceManager.setOutputDevice($0) }
                    )) {
                        ForEach(deviceManager.outputDevices) { dev in
                            Text(dev.name).tag(dev.id)
                        }
                    }
                    .labelsHidden()
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            // Transmit Mode & Calibration
            VStack(alignment: .leading, spacing: 14) {
                Text("Voice Activation & Calibration")
                    .font(.headline)

                Picker("Mode", selection: Binding(
                    get: { audioEngine.isPushToTalk ? 1 : 0 },
                    set: { audioEngine.isPushToTalk = ($0 == 1) }
                )) {
                    Text("Voice Activity (VAD)").tag(0)
                    Text("Push-to-Talk (PTT)").tag(1)
                }
                .pickerStyle(.segmented)

                if !audioEngine.isPushToTalk {
                    // Draggable VAD threshold slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Activation Threshold")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(audioEngine.vadThresholdDb)) dB")
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(audioEngine.vadThresholdDb) },
                                set: { audioEngine.vadThresholdDb = Float($0) }
                            ),
                            in: -60.0 ... -20.0,
                            step: 1.0
                        )

                        // Live Level Meter Bar
                        VStack(alignment: .leading, spacing: 4) {
                            Canvas { context, size in
                                // Background track
                                let trackPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
                                context.fill(trackPath, with: .color(Color.secondary.opacity(0.2)))

                                // Current mic level
                                let levelFraction = max(0.0, min(1.0, Double((audioEngine.inputLevelDb + 80) / 80)))
                                let fillWidth = size.width * CGFloat(levelFraction)
                                if fillWidth > 0 {
                                    let fillRect = CGRect(x: 0, y: 0, width: fillWidth, height: size.height)
                                    let fillPath = Path(roundedRect: fillRect, cornerRadius: size.height / 2)
                                    let fillColor = audioEngine.isTransmitting ? Color.green : Color.secondary
                                    context.fill(fillPath, with: .color(fillColor))
                                }

                                // Threshold gate marker
                                let threshFraction = max(0.0, min(1.0, Double((audioEngine.vadThresholdDb + 80) / 80)))
                                let gateX = size.width * CGFloat(threshFraction)
                                let markerRect = CGRect(x: max(0, gateX - 1), y: 0, width: 2, height: size.height)
                                context.fill(Path(markerRect), with: .color(Color.red))
                            }
                            .frame(height: 10)

                            HStack {
                                Text("-80 dB")
                                Spacer()
                                Text("Gate: \(Int(audioEngine.vadThresholdDb)) dB")
                                    .foregroundStyle(.red)
                                    .font(.caption2.bold())
                                Spacer()
                                Text("0 dB")
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }
                }

                Divider()

                // Loopback Test Toggle
                Toggle(isOn: Binding(
                    get: { audioEngine.isLoopbackTestEnabled },
                    set: { audioEngine.isLoopbackTestEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: audioEngine.isLoopbackTestEnabled ? "ear.fill" : "ear")
                                .foregroundStyle(audioEngine.isLoopbackTestEnabled ? Color.green : Color.primary)
                            Text("Loopback Mic Test")
                                .font(.subheadline.bold())
                        }
                        Text("Monitors your voice locally in real-time through the selected output device to check mic quality and test gate sensitivity.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(16)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            // Gaming & Hardware Quality Features
            VStack(alignment: .leading, spacing: 14) {
                Text("Bluetooth & Hardware Audio")
                    .font(.headline)

                Toggle(isOn: Binding(
                    get: { audioEngine.isAirPodsAudioLockEnabled },
                    set: { audioEngine.isAirPodsAudioLockEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AirPods / Bluetooth High-Quality Lock")
                            .font(.subheadline.bold())
                        Text("Locks mic to Mac's built-in mic so macOS never degrades Bluetooth stereo game audio into 16kHz Hands-Free mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hardware VoiceProcessingIO Active")
                            .font(.caption.bold())
                        Text("48,000 Hz Mono • Acoustic Echo Cancellation • Voice Isolation")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - 2. Shortcuts Settings Tab

struct ShortcutsSettingsTab: View {
    @Bindable var store: MumbleStore

    private var globalPTT: GlobalPTT {
        store.globalPTT
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Keybinds Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Global Hotkeys")
                    .font(.headline)

                // 1. Push-to-Talk Shortcut
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Push-to-Talk")
                            .font(.subheadline.bold())
                        Text("Hold this key while gaming to transmit voice.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        if globalPTT.activeRecordingAction == .ptt {
                            globalPTT.activeRecordingAction = nil
                        } else {
                            globalPTT.activeRecordingAction = .ptt
                        }
                    }) {
                        Text(globalPTT.activeRecordingAction == .ptt ? "Press any key..." : globalPTT.currentKeybind.displayString)
                            .bold()
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(globalPTT.activeRecordingAction == .ptt ? .orange : .accentColor)

                    if globalPTT.currentKeybind != .defaultGrave {
                        Button("Reset") {
                            globalPTT.currentKeybind = .defaultGrave
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                // 2. Push-to-Whisper Shortcut
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Push-to-Whisper")
                            .font(.subheadline.bold())
                        Text("Hold this key to whisper directly to the active whisper target.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        if globalPTT.activeRecordingAction == .whisper {
                            globalPTT.activeRecordingAction = nil
                        } else {
                            globalPTT.activeRecordingAction = .whisper
                        }
                    }) {
                        Text(globalPTT.activeRecordingAction == .whisper ? "Press any key..." : (globalPTT.whisperKeybind?.displayString ?? "None"))
                            .bold()
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(globalPTT.activeRecordingAction == .whisper ? .cyan : .secondary.opacity(0.3))

                    if globalPTT.whisperKeybind != nil {
                        Button("Clear") {
                            globalPTT.whisperKeybind = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                // 3. Global Mute Shortcut
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toggle Mute")
                            .font(.subheadline.bold())
                        Text("Mute or unmute your microphone globally.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        if globalPTT.activeRecordingAction == .mute {
                            globalPTT.activeRecordingAction = nil
                        } else {
                            globalPTT.activeRecordingAction = .mute
                        }
                    }) {
                        Text(globalPTT.activeRecordingAction == .mute ? "Press any key..." : (globalPTT.muteToggleKeybind?.displayString ?? "None"))
                            .bold()
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(globalPTT.activeRecordingAction == .mute ? .orange : .secondary.opacity(0.3))

                    if globalPTT.muteToggleKeybind != nil {
                        Button("Clear") {
                            globalPTT.muteToggleKeybind = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                // 3. Global Deafen Shortcut
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toggle Deafen")
                            .font(.subheadline.bold())
                        Text("Mute all incoming audio and microphone globally.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        if globalPTT.activeRecordingAction == .deafen {
                            globalPTT.activeRecordingAction = nil
                        } else {
                            globalPTT.activeRecordingAction = .deafen
                        }
                    }) {
                        Text(globalPTT.activeRecordingAction == .deafen ? "Press any key..." : (globalPTT.deafenToggleKeybind?.displayString ?? "None"))
                            .bold()
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(globalPTT.activeRecordingAction == .deafen ? .orange : .secondary.opacity(0.3))

                    if globalPTT.deafenToggleKeybind != nil {
                        Button("Clear") {
                            globalPTT.deafenToggleKeybind = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            // Accessibility Permission Status Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: globalPTT.isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.title3)
                        .foregroundStyle(globalPTT.isAccessibilityTrusted ? .green : .orange)

                    Text(globalPTT.isAccessibilityTrusted ? "Accessibility Permission Granted" : "Accessibility Permission Required")
                        .font(.headline)

                    Spacer()

                    Button("Check Again") {
                        globalPTT.refreshAccessibilityStatus()
                    }
                    .buttonStyle(.bordered)
                }

                Text("macOS requires Accessibility permissions for Swimble to intercept Push-to-Talk and hotkeys in the background while full-screen games or other applications are focused.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !globalPTT.isAccessibilityTrusted {
                    Button(action: {
                        globalPTT.openAccessibilitySettings()
                    }) {
                        Label("Open macOS System Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - 3. Server Access Tokens Tab

struct AccessTokensSettingsTab: View {
    @Bindable var store: MumbleStore
    @Binding var newTokenText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Server Access Tokens")
                    .font(.headline)
                Text("Access tokens grant permissions to password-protected channels and private groups on Mumble servers without needing server administrator status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func submitToken() {
        let trimmed = newTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addAccessToken(trimmed)
        newTokenText = ""
    }
}

// MARK: - 4. Certificates Settings Tab

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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Certificate Identity Card
            VStack(alignment: .leading, spacing: 12) {
                Text("Client Identity & Certificate")
                    .font(.headline)

                Text("Swimble uses client-side X.509 certificates to authenticate with Murmur servers without passwords. Your certificate is stored securely in the macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("SHA-1 Fingerprint:")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Text(store.certFingerprint)
                        .font(.system(.caption, design: .monospaced))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }

                if let msg = statusMessage {
                    Text(msg)
                        .font(.caption.bold())
                        .foregroundStyle(isError ? .red : .green)
                }
            }
            .padding(16)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            // Actions: Export, Import, Generate
            VStack(alignment: .leading, spacing: 14) {
                Text("Certificate Backup & Transfer")
                    .font(.headline)

                Text("Export your certificate as a standard PKCS#12 (.p12) bundle to back it up or transfer your registered identity from classic Mumble.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
            .padding(16)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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
