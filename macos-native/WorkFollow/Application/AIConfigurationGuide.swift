import Foundation

enum AIConfigurationGuide {
    static let nodeDownloadURL = URL(string: "https://nodejs.org/zh-cn/download")!
    static let nodeInstallCommand = #"""
    brew install node@24
    "$(brew --prefix node@24)/bin/node" --version
    """#

    static let piInstallCommand = #"""
    (
      set -e
      if command -v brew >/dev/null 2>&1; then
        WORKFOLLOW_NODE_BIN="$(brew --prefix node@24)/bin"
        if [ -x "$WORKFOLLOW_NODE_BIN/node" ]; then
          export PATH="$WORKFOLLOW_NODE_BIN:$PATH"
        fi
      fi
      npm install --global --prefix "$HOME/.local" @earendil-works/pi-coding-agent@0.86.1
      "$HOME/.local/bin/pi" --version
    )
    """#

    static let piModelsTemplate = #"""
    {
      "providers": {
        "my-text": {
          "baseUrl": "https://YOUR_TEXT_ENDPOINT/v1",
          "api": "openai-completions",
          "apiKey": "YOUR_API_KEY",
          "models": [{ "id": "YOUR_TEXT_MODEL" }]
        },
        "bailian-speech": {
          "baseUrl": "https://YOUR_WORKSPACE.cn-beijing.maas.aliyuncs.com",
          "api": "openai-completions",
          "apiKey": "YOUR_API_KEY",
          "models": [{ "id": "qwen-audio-3.1-asr-flash-streaming" }]
        }
      }
    }
    """#

    static func piModelsURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let custom = environment["PI_CODING_AGENT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let directory = custom.isEmpty ? home.appendingPathComponent(".pi/agent")
            : URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        return directory.appendingPathComponent("models.json")
    }

    static func preparePiModels(at url: URL = piModelsURL()) throws -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try piModelsTemplate.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return url
    }

}
