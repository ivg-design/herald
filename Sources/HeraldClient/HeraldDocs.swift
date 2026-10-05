import Foundation

/// Where the published documentation lives. Links in the app are built from `baseURL`; the path is the docs page under
/// docs/ without `.md` (`cloud/connect-chatgpt`).
public enum HeraldDocs {
    public static let baseURL = "https://forge.mograph.life/apps/herald/docs"
    public static func url(_ page: String) -> URL? {
        URL(string: baseURL + "/" + page.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
