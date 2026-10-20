import Foundation
import Observation
import AppKit

@Observable @MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    var status = ""
    var availableURL: URL?
    var checking = false
    private var checkedAtLaunch = false
    func checkAtLaunchIfEnabled() {
        guard !checkedAtLaunch, SettingsState.shared.checkForUpdatesOnStartup else { return }
        checkedAtLaunch = true; Task { await check() }
    }
    func check() async {
        guard !checking else { return }; checking = true; defer { checking = false }
        do {
            let url = URL(string: "https://api.github.com/repos/jurek-zsl/Swimble/releases/latest")!
            var request = URLRequest(url: url); request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Swimble", forHTTPHeaderField: "User-Agent")
            let (data,response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw URLError(.badServerResponse) }
            struct Release: Decodable { let tag_name: String; let html_url: URL }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if current.compare(latest, options: .numeric) == .orderedAscending {
                availableURL = release.html_url; status = "Swimble \(latest) is available."
                let alert = NSAlert(); alert.messageText = status; alert.informativeText = "Open the release page to download the update."
                alert.addButton(withTitle: "View Release"); alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.html_url) }
            } else { availableURL = nil; status = "Swimble is up to date (\(current))." }
        } catch { status = "Could not check for updates: \(error.localizedDescription)" }
    }
}
