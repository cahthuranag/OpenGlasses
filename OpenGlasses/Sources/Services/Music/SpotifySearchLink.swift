import Foundation

/// The one thing Avenkin does with Spotify: open the Spotify app's own search screen with the
/// wearer's words typed in, through the universal link Spotify claims. No API, no client id, no
/// account — nothing is played until the wearer taps. Pure.
enum SpotifySearchLink {
    static let host = "open.spotify.com"

    static func url(for phrase: String) -> URL? {
        let words = MusicRequestParser.spokenForm(phrase)
        guard !words.isEmpty,
              let encoded = words.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#")))
        else { return nil }
        return URL(string: "https://\(host)/search/\(encoded)")
    }
}
