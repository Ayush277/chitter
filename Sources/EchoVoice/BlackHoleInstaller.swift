import Foundation
import CryptoKit
import EchoNet

/// F12: installs the free BlackHole 2ch virtual audio driver (GPL — downloaded at install time, never bundled or linked).
public enum BlackHoleInstaller {
    public static let version = "0.7.1"
    public static let url = URL(string: "https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg")!
    /// SHA-256 pinned from the Homebrew cask metadata for blackhole-2ch 0.7.1 (formulae.brew.sh), 2026-11-24.
    public static let sha256 = "57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf"

    public static let manualGuide = """
    Install BlackHole 2ch yourself:
      • brew install --cask blackhole-2ch      (or)
      • download the installer from https://existential.audio/blackhole/ and open it.
    Then restart Chitter. Everything except interpretation keeps working without it.
    """

    public enum InstallError: Error, CustomStringConvertible {
        case checksumMismatch(String), cancelled, failed(String)
        public var description: String {
            switch self {
            case .checksumMismatch(let got): return "The downloaded installer didn't match the expected checksum (got \(got.prefix(12))…). Nothing was installed."
            case .cancelled: return "Installation was cancelled."
            case .failed(let m): return "Installation failed: \(m)"
            }
        }
    }

    public static var isInstalled: Bool { AudioDevices.blackHole() != nil }

    public static func sha256Hex(of file: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: file); defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(file: URL, expected: String = sha256) throws {
        let got = try sha256Hex(of: file)
        guard got == expected else { throw InstallError.checksumMismatch(got) }
    }

    /// Downloads (through the Privacy Ledger), verifies, then installs with ONE admin prompt. Any failure leaves the
    /// rest of the app working and returns the manual guide.
    public static func install() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("chitter-bh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pkg = dir.appendingPathComponent("BlackHole2ch.pkg")
        try await NetworkGateway.shared.download(url, to: pkg, purpose: "Download BlackHole 2ch virtual microphone installer", provider: "existential.audio")
        try verify(file: pkg)
        let script = "do shell script \"/usr/sbin/installer -pkg \\(quoted(pkg.path)) -target /\" with administrator privileges"
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", script]
        let err = Pipe(); p.standardError = err
        try p.run(); p.waitUntilExit()
        try? FileManager.default.removeItem(at: dir)
        if p.terminationStatus != 0 {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw msg.contains("-128") ? InstallError.cancelled : InstallError.failed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    private static func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
