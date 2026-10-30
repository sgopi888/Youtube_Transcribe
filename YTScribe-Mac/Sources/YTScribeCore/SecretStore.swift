import Foundation

/// OpenAI key storage. The app is ad-hoc signed, so its identity changes on every build and the Keychain
/// re-prompts forever ("Always Allow" cannot stick). The key lives in a 0600 file in Application Support instead;
/// an existing Keychain entry is copied over once on first read.
/// shortcut: plain file, user-only permissions, no encryption. Upgrade to the Keychain once the app has a stable Developer ID signature.
public enum SecretStore {
    static func fileURL(_ dir: URL) -> URL { dir.appendingPathComponent("openai.key") }

    public static func openAIKey(dir: URL = Library.supportDir) -> String? {
        if let s = try? String(contentsOf: fileURL(dir), encoding: .utf8) {
            let key = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { return key }
        }
        if let old = Keychain.get("openai"), !old.isEmpty {  // one-time migration; this read may prompt once
            saveOpenAIKey(old, dir: dir)
            return old
        }
        return nil
    }

    @discardableResult
    public static func saveOpenAIKey(_ key: String, dir: URL = Library.supportDir) -> Bool {
        let fm = FileManager.default
        let file = fileURL(dir)
        try? fm.removeItem(at: file)
        if key.isEmpty { Keychain.set("", for: "openai"); return true }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            return fm.createFile(atPath: file.path, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600])
        } catch { return false }
    }
}
