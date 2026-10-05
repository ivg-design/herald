import XCTest
@testable import HeraldClient

final class HeraldVersionTests: XCTestCase {
    func testVersionMatchesProjectYml() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let yml = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
        func values(_ key: String) -> Set<String> {
            Set(yml.components(separatedBy: "\n").compactMap { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix(key + ":") else { return nil }
                return t.dropFirst(key.count + 1).trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            })
        }
        XCTAssertEqual(values("MARKETING_VERSION"), [HeraldVersion.marketing],
                       "Sources/HeraldClient/HeraldVersion.swift `marketing` must equal MARKETING_VERSION in project.yml: change one to match the other")
        XCTAssertEqual(values("CURRENT_PROJECT_VERSION"), [HeraldVersion.build],
                       "Sources/HeraldClient/HeraldVersion.swift `build` must equal CURRENT_PROJECT_VERSION in project.yml: change one to match the other")
    }
}
