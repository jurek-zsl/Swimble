import SwiftUI

/// Audio Statistics window replicating Mumble's iconic diagnostic tool with live FFT spectrum graph,
/// signal analysis, dB level meters, and configuration feedback.
public struct AudioStatisticsModal: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss

    private var spectrum: AudioSpectrumAnalyzer {
        store.audioEngine.spectrum
    }

    private var audioEngine: MacAudioEngine {
        store.audioEngine
    }

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundStyle(store.accentTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Statistics")
                            .font(.headline.bold())
                        Text("Real-time DSP metrics, voice activity detection, and frequency spectrum.")
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

            ScrollView {
                VStack(spacing: 16) {
                    // Row 1: Input Levels & Signal Analysis
                    HStack(alignment: .top, spacing: 14) {
                        // 1. Input Levels
                        StatsCard(title: "Input Levels") {
                            StatRow(label: "Microphone RMS level", value: String(format: "%+.2f dB", spectrum.peakMicDb))
                            StatRow(label: "Speaker RMS level", value: String(format: "%+.2f dB", spectrum.peakSpeakerDb))
                            StatRow(label: "Capture overruns", value: "\(store.client.audioMetrics().captureOverruns)")
                            StatRow(label: "Playback underruns", value: "\(store.client.audioMetrics().playbackUnderruns)")
                        }

                        // 2. Signal Analysis
                        StatsCard(title: "Signal Analysis") {
                            StatRow(label: "Microphone RMS amplitude", value: "\(spectrum.micPowerPercent)%")
                            StatRow(label: "Signal-to-noise ratio", value: "Not measured")
                            StatRow(label: "Speech detection", value: audioEngine.isTransmitting ? "Threshold active" : "Below threshold")
                        }
                    }

                    // Row 2: Configuration feedback
                    StatsCard(title: "Configuration feedback") {
                        VStack(spacing: 10) {
                            HStack {
                                HStack(spacing: 6) {
                                    Text("Current audio bitrate")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(store.connectionStatus == .connected ? "\(store.client.audioBitrate() / 1000) kbit/s configured" : "Disconnected")
                                        .font(.subheadline.monospacedDigit().bold())
                                }

                                Spacer()

                                HStack(spacing: 6) {
                                    Text("Packet duration")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("\(ClientPreferences.shared.packetDurationMs) ms")
                                        .font(.subheadline.monospacedDigit().bold())
                                }
                            }

                            // Speech Detection Meter Bar
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Speech Detection")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(audioEngine.isTransmitting ? "TRANSMITTING" : "SILENT")
                                        .font(.system(size: 9, weight: .heavy))
                                        .foregroundStyle(audioEngine.isTransmitting ? Color.green : Color.secondary)
                                }

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        // Track background
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color(NSColor.darkGray).opacity(0.4))

                                        // Live green signal bar
                                        let levelFrac = max(0.0, min(1.0, Double((spectrum.peakMicDb + 80.0) / 80.0)))
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(audioEngine.isTransmitting ? Color.green : Color.green.opacity(0.4))
                                            .frame(width: geo.size.width * CGFloat(levelFrac))

                                        // Red gate threshold marker
                                        let threshFrac = max(0.0, min(1.0, Double((audioEngine.vadThresholdDb + 80.0) / 80.0)))
                                        Rectangle()
                                            .fill(Color.red)
                                            .frame(width: 2.5, height: geo.size.height)
                                            .offset(x: geo.size.width * CGFloat(threshFrac) - 1.25)
                                    }
                                }
                                .frame(height: 18)
                            }
                        }
                    }

                    // Row 3: Signal and noise power spectrum (Live Graph matching Screenshot)
                    StatsCard(title: "Signal and noise power spectrum") {
                        VStack(alignment: .leading, spacing: 6) {
                            SpectrumChartView(magnitudes: spectrum.magnitudes)
                                .frame(height: 180)
                                .background(Color.black.opacity(0.85))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                }

                            HStack {
                                Text("0 Hz")
                                Spacer()
                                Text("6 kHz")
                                Spacer()
                                Text("12 kHz")
                                Spacer()
                                Text("18 kHz")
                                Spacer()
                                Text("24 kHz")
                            }
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 580, height: 600)
        .onAppear { spectrum.beginObserving(); store.client.setAudioDiagnostics(enabled: true); store.audioEngine.beginPreview() }
        .onDisappear { spectrum.endObserving(); store.client.setAudioDiagnostics(enabled: false); store.audioEngine.endPreview() }
    }
}

// MARK: - Subcomponents

private struct StatsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(.primary)
        }
    }
}

/// Canvas drawing the red FFT frequency curve and blue noise floor baseline matching Mumble
private struct SpectrumChartView: View {
    let magnitudes: [Float]

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let count = magnitudes.count

            guard count > 1 else { return }

            // 1. Draw horizontal grid lines
            for i in 1...3 {
                let y = h * (CGFloat(i) / 4.0)
                var gridPath = Path()
                gridPath.move(to: CGPoint(x: 0, y: y))
                gridPath.addLine(to: CGPoint(x: w, y: y))
                context.stroke(gridPath, with: .color(Color.white.opacity(0.06)), lineWidth: 0.5)
            }

            // 2. Draw Blue Baseline (Noise Floor) at bottom
            let baselineY = h - 10.0
            var bluePath = Path()
            bluePath.move(to: CGPoint(x: 0, y: baselineY))
            bluePath.addLine(to: CGPoint(x: w, y: baselineY))
            context.stroke(bluePath, with: .color(Color.blue), lineWidth: 1.5)

            // 3. Draw Red Frequency Power Curve
            var redPath = Path()
            let dx = w / CGFloat(count - 1)

            for i in 0..<count {
                let mag = CGFloat(magnitudes[i])
                let x = CGFloat(i) * dx
                let y = max(4, baselineY - (mag * (baselineY - 10)))

                if i == 0 {
                    redPath.move(to: CGPoint(x: x, y: y))
                } else {
                    redPath.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Stroke the red spectrum line
            context.stroke(redPath, with: .color(Color.red), lineWidth: 1.5)
        }
    }
}
