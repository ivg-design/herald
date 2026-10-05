import Foundation

/// The one version the command line tool and the MCP server report. SwiftPM builds them without an Info.plist, so
/// the number lives here; `HeraldVersionTests` compares it with project.yml and says which line to change.
/// To bump a release: edit these two constants and MARKETING_VERSION / CURRENT_PROJECT_VERSION in project.yml.
public enum HeraldVersion {
    public static let marketing = "1.9.1"
    public static let build = "23"
}
