import Foundation

@MainActor
final class LocalControl {
    static let shared = LocalControl()
    private var timer: Timer?
    private(set) var status = ""
    func start() {
        guard timer == nil else { return }
        status = startLocalControl()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                let commands = takeLocalCommands()
                guard let store = GlobalPTT.shared.activeStore ?? MumbleStore.activeStores.first(where: { $0.connectionStatus == .connected }) else { return }
                for command in commands { self.execute(command, store: store) }
            }
        }
    }
    private func execute(_ command: String, store: MumbleStore) {
        switch command {
        case "mute": store.setSelfMute(true)
        case "unmute": store.setSelfMute(false)
        case "togglemute": store.toggleSelfMute()
        case "deaf": store.setSelfDeaf(true)
        case "undeaf": store.setSelfDeaf(false)
        case "toggledeaf": store.toggleSelfDeaf()
        case "starttalking": store.audioEngine.setPushToTalkActive(true)
        case "stoptalking": store.audioEngine.setPushToTalkActive(false)
        default:
            let parts = command.split(separator: " ")
            if parts.count == 2, let id = UInt32(parts[1]) {
                if parts[0] == "join" { store.joinChannel(channelId: id) }
                if parts[0] == "listen" { store.client.setChannelListening(channelId: id, listening: !store.isListening(to: id)) }
            }
        }
    }
}
