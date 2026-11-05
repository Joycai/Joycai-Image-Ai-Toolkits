import CryptoKit
#if canImport(FlutterMacOS)
import FlutterMacOS
#endif
import Foundation
import Security

/// One device-local wrapping key. Credentials remain transactional SQLite values;
/// rotating/deleting a credential never mutates the key used by other rows.
struct CredentialProtection {
  static let prefix = "joycai-secret:v1:"
  private enum Failure: Error { case unavailable }

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "") + ".credentials",
      kSecAttrAccount as String: "wrapping-key-v1",
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrSynchronizable as String: false,
    ]
  }

  private func key(create: Bool) throws -> SymmetricKey {
    var read = query
    read[kSecReturnData as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(read as CFDictionary, &item)
    if status == errSecSuccess, let data = item as? Data, data.count == 32 {
      return SymmetricKey(data: data)
    }
    guard status == errSecItemNotFound, create else { throw Failure.unavailable }
    let generated = SymmetricKey(size: .bits256)
    var add = query
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    add[kSecValueData as String] = generated.withUnsafeBytes { Data($0) }
    let added = SecItemAdd(add as CFDictionary, nil)
    guard added == errSecSuccess || added == errSecDuplicateItem else {
      throw Failure.unavailable
    }
    // Read back even after a race: use the persisted key, not a losing candidate.
    return try key(create: false)
  }

  func prepare(allowCreate: Bool) throws {
    _ = try key(create: allowCreate)
  }

  func seal(_ plaintext: String) throws -> String {
    let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key(create: false))
    guard let data = sealed.combined else { throw Failure.unavailable }
    return Self.prefix + data.base64EncodedString()
  }

  func open(_ envelope: String) throws -> String {
    guard envelope.hasPrefix(Self.prefix),
      let data = Data(base64Encoded: String(envelope.dropFirst(Self.prefix.count)))
    else { throw Failure.unavailable }
    let sealed = try AES.GCM.SealedBox(combined: data)
    let plaintext = try AES.GCM.open(sealed, using: key(create: false))
    guard let result = String(data: plaintext, encoding: .utf8) else {
      throw Failure.unavailable
    }
    return result
  }

  #if canImport(FlutterMacOS)
  static func register(_ controller: FlutterViewController) {
    let protection = CredentialProtection()
    let channel = FlutterMethodChannel(
      name: "joycai/credential_protection", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "prepare", let allowCreate = call.arguments as? Bool {
        do {
          try protection.prepare(allowCreate: allowCreate)
          result("")
        } catch {
          result(FlutterError(code: "credential_unavailable", message: nil, details: nil))
        }
        return
      }
      guard call.method == "seal" || call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let value = call.arguments as? String else {
        result(FlutterError(code: "credential_unavailable", message: nil, details: nil))
        return
      }
      do {
        result(try call.method == "seal" ? protection.seal(value) : protection.open(value))
      } catch {
        result(FlutterError(code: "credential_unavailable", message: nil, details: nil))
      }
    }
  }
  #endif
}
