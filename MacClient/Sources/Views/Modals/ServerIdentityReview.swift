import SwiftUI

extension ServerIdentityChallenge: Identifiable {
    public var id: String { "\(host):\(port):\(fingerprint)" }
}

struct ServerIdentityReview: View {
    @Bindable var store: MumbleStore
    let challenge: ServerIdentityChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(challenge.previousFingerprint == nil ? "Verify Server Identity" : "Server Certificate Changed",
                  systemImage: "exclamationmark.shield")
                .font(.title2.bold())
            Text("\(challenge.host):\(challenge.port)").font(.headline)
            Text("The connection was blocked before credentials or voice were sent. Confirm this SHA-256 fingerprint with the server administrator through a trusted channel before continuing.")
            Text(challenge.reason).font(.caption).foregroundStyle(.secondary)
            if let previous = challenge.previousFingerprint {
                Text("Previously trusted certificate").font(.caption.bold())
                Text(previous).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }
            Text("Presented certificate · SHA-256").font(.caption.bold())
            Text(challenge.fingerprint).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            HStack {
                Button("Cancel", role: .cancel) { store.rejectServerIdentity() }
                Spacer()
                Button("Trust Once") { store.acceptServerIdentity(remember: false) }
                Button("Trust and Save") { store.acceptServerIdentity(remember: true) }
            }
        }
        .padding(24)
        .frame(width: 600)
        .interactiveDismissDisabled()
    }
}
