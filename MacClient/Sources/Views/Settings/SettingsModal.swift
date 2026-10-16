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
            .background(Color(NSColor.windowBackgroundColor).opacity(0.85))

            Divider()

            // Tab Content (each tab manages its own ScrollView with side padding)
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
        .frame(minWidth: 680, idealWidth: 720, minHeight: 580, idealHeight: 640)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Devices Section
                SettingsCard {
                    SettingsSectionHeader(
                        "Audio Devices",
                        systemImage: "speaker.wave.2.fill",
                        subtitle: "Select the microphone and audio output devices used for voice chat."
                    )

                    VStack(spacing: 12) {
                        HStack {
                            Label("Input Device", systemImage: "mic.fill")
                                .frame(width: 140, alignment: .leading)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Picker("", selection: Binding(
                                get: { deviceManager.selectedInputDeviceID },
                                set: { deviceManager.setInputDevice($0) }
                            )) {
                                ForEach(deviceManager.inputDevices) { dev in
                                    Text(dev.name).tag(dev.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 320)
                        }

                        Divider()

                        HStack {
                            Label("Output Device", systemImage: "speaker.2.fill")
                                .frame(width: 140, alignment: .leading)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Picker("", selection: Binding(
                                get: { deviceManager.selectedOutputDeviceID },
                                set: { deviceManager.setOutputDevice($0) }
                            )) {
                                ForEach(deviceManager.outputDevices) { dev in
                                    Text(dev.name).tag(dev.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 320)
                        }
                    }
                }

                // 2. Transmit Mode & Calibration
                SettingsCard {
                    SettingsSectionHeader(
                        "Voice Activation & Calibration",
                        systemImage: "waveform",
                        subtitle: "Choose how your microphone transmits audio and calibrate sensitivity threshold."
                    )

                    Picker("Mode", selection: Binding(
                        get: { audioEngine.isPushToTalk ? 1 : 0 },
                        set: { audioEngine.isPushToTalk = ($0 == 1) }
                    )) {
                        Text("Voice Activity (VAD)").tag(0)
                        Text("Push-to-Talk (PTT)").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 2)

                    if !audioEngine.isPushToTalk {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Activation Threshold")
                                    .font(.subheadline.bold())
                                Spacer()
                                Text("\(Int(audioEngine.vadThresholdDb)) dB")
                                    .font(.subheadline.monospacedDigit().bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
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
                            VStack(alignment: .leading, spacing: 6) {
                                Canvas { context, size in
                                    // Background track
                                    let trackPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
                                    context.fill(trackPath, with: .color(Color.secondary.opacity(0.15)))

                                    // Current mic level
                                    let levelFraction = max(0.0, min(1.0, Double((audioEngine.inputLevelDb + 80) / 80)))
                                    let fillWidth = size.width * CGFloat(levelFraction)
                                    if fillWidth > 0 {
                                        let fillRect = CGRect(x: 0, y: 0, width: fillWidth, height: size.height)
                                        let fillPath = Path(roundedRect: fillRect, cornerRadius: size.height / 2)
                                        let fillColor = audioEngine.isTransmitting ? Color.green : Color.secondary.opacity(0.5)
                                        context.fill(fillPath, with: .color(fillColor))
                                    }

                                    // Threshold gate marker
                                    let threshFraction = max(0.0, min(1.0, Double((audioEngine.vadThresholdDb + 80) / 80)))
                                    let gateX = size.width * CGFloat(threshFraction)
                                    let markerRect = CGRect(x: max(0, gateX - 1.5), y: 0, width: 3, height: size.height)
                                    context.fill(Path(roundedRect: markerRect, cornerRadius: 1), with: .color(Color.red))
                                }
                                .frame(height: 12)

                                HStack {
                                    Text("-80 dB (Silent)")
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.red).frame(width: 6, height: 6)
                                        Text("Gate: \(Int(audioEngine.vadThresholdDb)) dB")
                                            .foregroundStyle(.red)
                                            .font(.caption2.bold())
                                    }
                                    Spacer()
                                    Text("0 dB (Max)")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Loopback Test Toggle
                    SettingsToggleRow(isOn: Binding(
                        get: { audioEngine.isLoopbackTestEnabled },
                        set: { audioEngine.isLoopbackTestEnabled = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: audioEngine.isLoopbackTestEnabled ? "ear.fill" : "ear")
                                    .foregroundStyle(audioEngine.isLoopbackTestEnabled ? Color.green : Color.primary)
                                Text("Loopback Mic Test")
                                    .font(.subheadline.bold())
                                if audioEngine.isLoopbackTestEnabled {
                                    Text("ACTIVE")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.green.opacity(0.18), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }
                            Text("Monitors your voice locally in real-time through the selected output device to check mic quality and test gate sensitivity.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // 3. Gaming & Hardware Quality Features
                SettingsCard {
                    SettingsSectionHeader(
                        "Hardware & Audio Processing",
                        systemImage: "slider.horizontal.3",
                        subtitle: "Acoustic echo cancellation, background audio ducking, and Bluetooth protection."
                    )

                    // 1. Ducking Toggle
                    SettingsToggleRow(
                        "Lower Background Apps Volume (Ducking)",
                        subtitle: "When enabled, macOS ducks Spotify, YouTube, games, and other apps during voice chat. Kept off so background audio stays at 100% volume.",
                        isOn: Binding(
                            get: { audioEngine.isAudioDuckingEnabled },
                            set: { audioEngine.isAudioDuckingEnabled = $0 }
                        )
                    )

                    Divider()

                    // 2. AirPods / Bluetooth Lock
                    SettingsToggleRow(
                        "AirPods / Bluetooth High-Quality Lock",
                        subtitle: "Locks mic to Mac's built-in mic so macOS never degrades Bluetooth stereo game audio into 16kHz Hands-Free mode.",
                        isOn: Binding(
                            get: { audioEngine.isAirPodsAudioLockEnabled },
                            set: { audioEngine.isAirPodsAudioLockEnabled = $0 }
                        )
                    )

                    Divider()

                    // 3. Hardware Echo Cancellation
                    SettingsToggleRow(
                        "Hardware Echo Cancellation & Voice Isolation",
                        subtitle: "Uses Apple VoiceProcessingIO to filter speaker echo and isolate speech from background noise.",
                        isOn: Binding(
                            get: { audioEngine.isVoiceProcessingEnabled },
                            set: { audioEngine.isVoiceProcessingEnabled = $0 }
                        )
                    )

                    Divider()

                    // VoiceProcessingIO Status Banner
                    HStack(spacing: 12) {
                        Image(systemName: audioEngine.isVoiceProcessingEnabled ? "checkmark.seal.fill" : "waveform.badge.magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(audioEngine.isVoiceProcessingEnabled ? .green : .blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(audioEngine.isVoiceProcessingEnabled ? "Apple VoiceProcessingIO Active" : "Direct CoreAudio Pipeline Active")
                                .font(.subheadline.bold())
                            Text(audioEngine.isVoiceProcessingEnabled ?
                                 "48,000 Hz Mono • AEC • Voice Isolation • \(audioEngine.isAudioDuckingEnabled ? "Ducking Active" : "Zero Background Ducking")" :
                                 "48,000 Hz Mono • Raw Audio • Zero Ducking • Lowest Latency")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(audioEngine.isVoiceProcessingEnabled ? "AEC ON" : "RAW")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background((audioEngine.isVoiceProcessingEnabled ? Color.green : Color.blue).opacity(0.15), in: Capsule())
                            .foregroundStyle(audioEngine.isVoiceProcessingEnabled ? .green : .blue)
                    }
                    .padding(12)
                    .background((audioEngine.isVoiceProcessingEnabled ? Color.green : Color.blue).opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder((audioEngine.isVoiceProcessingEnabled ? Color.green : Color.blue).opacity(0.2), lineWidth: 0.5)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
        }
    }
}

// MARK: - 2. Shortcuts Settings Tab

struct ShortcutRowView: View {
    let title: String
    let subtitle: String
    let action: KeybindAction
    let keybind: PTTKeybind?
    let defaultKeybind: PTTKeybind?
    let globalPTT: GlobalPTT
    let onResetOrClear: () -> Void

    var isRecording: Bool {
        globalPTT.activeRecordingAction == action
    }

    var displayLabel: String {
        if isRecording {
            return globalPTT.recordingPreviewString(for: action)
        }
        return keybind?.displayString ?? "None"
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: {
                if isRecording {
                    globalPTT.activeRecordingAction = nil
                } else {
                    globalPTT.activeRecordingAction = action
                }
            }) {
                HStack(spacing: 6) {
                    if isRecording {
                        Image(systemName: "record.circle")
                            .symbolEffect(.pulse)
                    }
                    Text(displayLabel)
                        .bold()
                }
                .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? .orange : (keybind != nil ? .accentColor : .secondary.opacity(0.3)))

            if let defaultKey = defaultKeybind {
                if keybind != defaultKey {
                    Button("Reset") {
                        onResetOrClear()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if keybind != nil {
                Button("Clear") {
                    onResetOrClear()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

struct ShortcutsSettingsTab: View {
    @Bindable var store: MumbleStore

    private var globalPTT: GlobalPTT {
        store.globalPTT
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Keybinds Section
                SettingsCard {
                    SettingsSectionHeader(
                        "Global Hotkeys",
                        systemImage: "keyboard",
                        subtitle: "Configure single keys or multi-key combinations that work globally even while gaming."
                    )

                    // 1. Push-to-Talk Shortcut
                    ShortcutRowView(
                        title: "Push-to-Talk",
                        subtitle: "Hold key combination to transmit audio while gaming.",
                        action: .ptt,
                        keybind: globalPTT.currentKeybind,
                        defaultKeybind: .defaultGrave,
                        globalPTT: globalPTT,
                        onResetOrClear: { globalPTT.currentKeybind = .defaultGrave }
                    )

                    Divider()

                    // 2. Push-to-Whisper Shortcut
                    ShortcutRowView(
                        title: "Push-to-Whisper",
                        subtitle: "Hold key combination to whisper directly to active target.",
                        action: .whisper,
                        keybind: globalPTT.whisperKeybind,
                        defaultKeybind: nil,
                        globalPTT: globalPTT,
                        onResetOrClear: { globalPTT.whisperKeybind = nil }
                    )

                    Divider()

                    // 3. Global Mute Shortcut
                    ShortcutRowView(
                        title: "Toggle Mute",
                        subtitle: "Mute or unmute your microphone globally (e.g. Ctrl + Shift + Z).",
                        action: .mute,
                        keybind: globalPTT.muteToggleKeybind,
                        defaultKeybind: nil,
                        globalPTT: globalPTT,
                        onResetOrClear: { globalPTT.muteToggleKeybind = nil }
                    )

                    Divider()

                    // 4. Global Deafen Shortcut
                    ShortcutRowView(
                        title: "Toggle Deafen",
                        subtitle: "Mute all incoming audio and your microphone globally.",
                        action: .deafen,
                        keybind: globalPTT.deafenToggleKeybind,
                        defaultKeybind: nil,
                        globalPTT: globalPTT,
                        onResetOrClear: { globalPTT.deafenToggleKeybind = nil }
                    )

                    Divider()

                    // 5. Global Overlay Shortcut
                    ShortcutRowView(
                        title: "Toggle Game Overlay",
                        subtitle: "Show or hide the floating in-game speaking HUD overlay.",
                        action: .overlay,
                        keybind: globalPTT.overlayToggleKeybind,
                        defaultKeybind: nil,
                        globalPTT: globalPTT,
                        onResetOrClear: { globalPTT.overlayToggleKeybind = nil }
                    )

                    Divider()

                    // Instructions / Tip banner
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard.badge.ellipsis")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                        Text("Tip: Click a shortcut button, then press any single key or combination of 2, 3 or more keys (e.g. Ctrl + Shift + Z). Press Escape to cancel or Delete to clear.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }

                // Accessibility Permission Status Card
                SettingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: globalPTT.isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.title2)
                            .foregroundStyle(globalPTT.isAccessibilityTrusted ? .green : .orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(globalPTT.isAccessibilityTrusted ? "Accessibility Permission Granted" : "Accessibility Permission Required")
                                .font(.headline)
                            Text("macOS requires Accessibility permissions for Swimble to intercept Push-to-Talk and hotkeys in the background while full-screen games or other applications are focused.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button("Check Again") {
                            globalPTT.refreshAccessibilityStatus()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

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
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
        }
    }
}

// MARK: - 3. Server Access Tokens Tab

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
