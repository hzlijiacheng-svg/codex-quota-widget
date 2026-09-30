import Foundation

public enum CodexExecutableLocator {
    public static func candidates(
        environment: [String: String],
        homeDirectory: URL
    ) -> [String] {
        let applicationRelativePaths = [
            "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "Contents/Resources/codex"
        ]
        var paths: [String] = []
        if let override = environment["CODEX_QUOTA_CODEX_PATH"], !override.isEmpty {
            paths.append(override)
        }
        for application in ["ChatGPT.app", "Codex.app"] {
            for relativePath in applicationRelativePaths {
                paths.append("/Applications/\(application)/\(relativePath)")
            }
        }
        for application in ["ChatGPT.app", "Codex.app"] {
            for relativePath in applicationRelativePaths {
                paths.append(
                    homeDirectory
                        .appendingPathComponent("Applications")
                        .appendingPathComponent(application)
                        .appendingPathComponent(relativePath)
                        .path
                )
            }
        }
        paths.append(contentsOf: ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"])
        return paths
    }

    public static func firstExecutable(
        environment: [String: String],
        homeDirectory: URL,
        isExecutable: (String) -> Bool
    ) -> String? {
        candidates(environment: environment, homeDirectory: homeDirectory)
            .first(where: isExecutable)
    }
}
