import Foundation

/// What a `sound` string means once checked against the disk.
public enum SoundChoice: Equatable, Sendable {
    /// "none" (or empty): deliberately silent.
    case silent
    /// "default": the caller substitutes the app's default sound.
    case useDefault
    /// An existing audio file, as an absolute path.
    case file(String)
    /// Not "none", not a sound that exists. The string says why.
    case invalid(String)
}

/// Validates notification sounds: a system sound name (files in /System/Library/Sounds), a sound the user
/// installed (/Library/Sounds, ~/Library/Sounds), a file path, "none" or "default".
public enum SoundCatalog {
    public static let systemDirectory = "/System/Library/Sounds"
    public static let audioExtensions: Set<String> = ["aiff", "aif", "aifc", "wav", "mp3", "m4a", "aac", "caf"]

    /// System sounds first so "Glass" can never be shadowed by a user file of the same name.
    public static var defaultDirectories: [String] {
        [systemDirectory, "/Library/Sounds", (("~/Library/Sounds") as NSString).expandingTildeInPath]
    }

    /// Audio files (not folders) directly inside `directory`, by file name.
    private static func audioFiles(in directory: String) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return files.filter {
            guard audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) else { return false }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: (directory as NSString).appendingPathComponent($0), isDirectory: &isDir)
                && !isDir.boolValue
        }
    }

    /// Names (without extension) of the sounds in `directory`, sorted.
    public static func names(in directory: String = systemDirectory) -> [String] {
        audioFiles(in: directory)
            .map { ($0 as NSString).deletingPathExtension }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public static func resolve(_ spec: String, directories: [String] = defaultDirectories) -> SoundChoice {
        let s = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        switch s.lowercased() {
        case "", "none": return .silent
        case "default": return .useDefault
        default: break
        }
        if s.hasPrefix("/") || s.hasPrefix("~") {
            let path = (s as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                return .invalid("no sound file at \(path)")
            }
            guard audioExtensions.contains((path as NSString).pathExtension.lowercased()) else {
                return .invalid("\(path) is not a supported audio file")
            }
            return .file(path)
        }
        // A bare name, optionally with its extension ("Glass" or "Glass.aiff"), matched case-insensitively
        // because "glass" is an obvious thing for a client to send.
        let base = audioExtensions.contains((s as NSString).pathExtension.lowercased())
            ? (s as NSString).deletingPathExtension : s
        for dir in directories {
            if let match = audioFiles(in: dir).first(where: {
                ($0 as NSString).deletingPathExtension.caseInsensitiveCompare(base) == .orderedSame
            }) {
                return .file((dir as NSString).appendingPathComponent(match))
            }
        }
        return .invalid("no sound named \"\(s)\"")
    }

    /// True for everything that will play or is intentionally silent ("none", "default", a real sound).
    public static func isValid(_ spec: String, directories: [String] = defaultDirectories) -> Bool {
        if case .invalid = resolve(spec, directories: directories) { return false }
        return true
    }
}
