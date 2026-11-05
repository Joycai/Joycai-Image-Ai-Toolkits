// Compile beside macos/Runner/CredentialProtection.swift in an independently
// signed .app. Never use the production bundle ID or credentials.
import Foundation
import Security

@main
struct CredentialProtectionProbe {
  static func main() throws {
    guard let bundle = Bundle.main.bundleIdentifier,
      bundle.hasPrefix("cn.joycai.mas06.acceptance."),
      CommandLine.arguments.count == 3
    else { throw ProbeError.invalidFixture }
    let mode = CommandLine.arguments[1]
    let file: URL
    if CommandLine.arguments[2] == "container" {
      let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      guard directory.path.contains(bundle) else { throw ProbeError.invalidFixture }
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      file = directory.appendingPathComponent("mas06-synthetic-envelope.txt")
    } else {
      file = URL(fileURLWithPath: CommandLine.arguments[2])
    }
    let protection = CredentialProtection()
    let synthetic = "MAS06 synthetic credential — not a real key"
    switch mode {
    case "write":
      try protection.prepare(allowCreate: true)
      let envelope = try protection.seal(synthetic)
      guard try protection.open(envelope) == synthetic,
        try protection.seal(synthetic) != envelope
      else { throw ProbeError.verification }
      try envelope.write(to: file, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    case "read":
      let envelope = try String(contentsOf: file, encoding: .utf8)
      guard try protection.open(envelope) == synthetic else { throw ProbeError.verification }
      guard var tampered = Data(base64Encoded: String(envelope.dropFirst(CredentialProtection.prefix.count)))
      else { throw ProbeError.verification }
      tampered[tampered.count - 1] ^= 1
      do {
        _ = try protection.open(CredentialProtection.prefix + tampered.base64EncodedString())
        throw ProbeError.acceptedTampering
      } catch ProbeError.acceptedTampering { throw ProbeError.acceptedTampering }
      catch { /* Authentication must fail. */ }
    case "delete":
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: bundle + ".credentials",
        kSecAttrAccount as String: "wrapping-key-v1",
        kSecUseDataProtectionKeychain as String: true,
        kSecAttrSynchronizable as String: false,
      ]
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw ProbeError.verification
      }
      let envelope = try String(contentsOf: file, encoding: .utf8)
      do {
        _ = try protection.open(envelope)
        throw ProbeError.acceptedMissingKey
      } catch ProbeError.acceptedMissingKey { throw ProbeError.acceptedMissingKey }
      catch { /* Decryption must not create a replacement wrapping key. */ }
      do {
        _ = try protection.seal(synthetic)
        throw ProbeError.acceptedMissingKey
      } catch ProbeError.acceptedMissingKey { throw ProbeError.acceptedMissingKey }
      catch { /* Runtime writes also must not recreate a lost key. */ }
      var read = query
      read[kSecReturnData as String] = true
      guard SecItemCopyMatching(read as CFDictionary, nil) == errSecItemNotFound else {
        throw ProbeError.verification
      }
    default: throw ProbeError.invalidFixture
    }
    print("MAS06 \(mode): PASS")
  }
  enum ProbeError: Error {
    case invalidFixture, verification, acceptedTampering, acceptedMissingKey
  }
}
