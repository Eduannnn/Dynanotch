import Foundation

public enum MusicFavoriteAction {
    public static func script(trackID: String, favorited: Bool) -> String? {
        guard trackID.range(of: "^[0-9A-Fa-f]{16}$", options: .regularExpression) != nil else { return nil }
        return """
        with timeout of 3 seconds
        tell application id "com.apple.Music"
            set t to current track
            if (persistent ID of t as text) is not "\(trackID)" then error "The playing song changed." number -128
            set favorited of t to \(favorited ? "true" : "false")
            return favorited of t as text
        end tell
        end timeout
        """
    }
}
