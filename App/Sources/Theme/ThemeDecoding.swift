import Foundation

// Themes are saved and shared as JSON. These decoders fill in defaults for any field a theme
// doesn't have, so themes made with older (or newer) versions of the app always load.

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback()
    }
}
