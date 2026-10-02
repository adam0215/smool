import AppKit

enum HomeApp: String, Hashable {
    case spotify = "Spotify"
    case codex = "Codex"

    var bundleIdentifier: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .codex: "com.openai.codex"
        }
    }

    var webURL: URL {
        switch self {
        case .spotify: URL(string: "https://open.spotify.com")!
        case .codex: URL(string: "https://chatgpt.com/codex")!
        }
    }
}
