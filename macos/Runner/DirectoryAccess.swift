import Cocoa
import FlutterMacOS

/// One active scope per saved root, held for the app session because directory
/// watchers and queued tasks outlive the settings screen. Never exports grants.
final class DirectoryAccess {
  static let shared = DirectoryAccess()
  private struct Grant: Codable {
    let data: Data
    let readOnly: Bool
  }

  private var active: [String: URL] = [:]
  private var panelOpen = false

  private var storeURL: URL {
    get throws {
      let support = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true)
      let directory = support.appendingPathComponent(
        Bundle.main.bundleIdentifier ?? "joycai", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return directory.appendingPathComponent("directory-grants.plist")
    }
  }

  private func load() throws -> [String: Grant] {
    let url = try storeURL
    guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
    return try PropertyListDecoder().decode([String: Grant].self, from: Data(contentsOf: url))
  }

  private func save(_ records: [String: Grant]) throws {
    try PropertyListEncoder().encode(records).write(to: storeURL, options: .atomic)
  }

  private func canonical(_ url: URL) -> String {
    url.resolvingSymlinksInPath().standardizedFileURL.path
  }

  private func readableDirectory(_ url: URL) -> Bool {
    // Existence alone is insufficient under App Sandbox.
    (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
  }

  private func restore(_ path: String, records: inout [String: Grant]) -> String {
    // Revalidate identity even for a live scope. Keep the previous scope until
    // its replacement is acquired so background readers never see a gap.
    let previous = active.removeValue(forKey: path)
    defer { previous?.stopAccessingSecurityScopedResource() }
    guard let grant = records[path] else { return "needsAuthorization" }
    do {
      var stale = false
      let url = try URL(resolvingBookmarkData: grant.data,
        options: [.withSecurityScope, .withoutUI, .withoutMounting],
        relativeTo: nil, bookmarkDataIsStale: &stale)
      guard url.startAccessingSecurityScopedResource() else { return "unavailable" }
      var retained = false
      defer { if !retained { url.stopAccessingSecurityScopedResource() } }
      // Do not silently redirect a saved path or widen an MCP allowlist when
      // a folder moves or is replaced by a symlink. Let the user choose again.
      guard canonical(url) == path else { return "moved" }
      guard readableDirectory(url) else { return "unavailable" }
      if stale {
        var options: URL.BookmarkCreationOptions = [.withSecurityScope]
        if grant.readOnly { options.insert(.securityScopeAllowOnlyReadAccess) }
        let data = try url.bookmarkData(
          options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        records[path] = Grant(data: data, readOnly: grant.readOnly)
        try save(records)
      }
      active[path] = url
      retained = true
      return "available"
    } catch {
      // Keep the original record: an offline volume may become available later.
      return "unavailable"
    }
  }

  func register(_ controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "joycai/directory_access", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [self] call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      do {
        switch call.method {
        case "copyDrop":
          guard let bytes = args["bookmark"] as? FlutterStandardTypedData,
            let destination = args["destination"] as? String else {
            result(FlutterError(code: "bad_args", message: "bookmark and destination required", details: nil))
            return
          }
          let target = URL(fileURLWithPath: destination)
          let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
          guard canonical(target).hasPrefix(canonical(support) + "/") else {
            result(FlutterError(code: "bad_destination", message: "Private storage required", details: nil))
            return
          }
          var stale = false
          let source = try URL(resolvingBookmarkData: bytes.data,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil, bookmarkDataIsStale: &stale)
          guard source.startAccessingSecurityScopedResource() else {
            result(FlutterError(code: "access_denied", message: "Cannot access dropped file", details: nil))
            return
          }
          DispatchQueue.global(qos: .userInitiated).async {
            defer { source.stopAccessingSecurityScopedResource() }
            do {
              let values = try source.resourceValues(forKeys: [.isRegularFileKey])
              guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
              guard FileManager.default.createFile(atPath: target.path, contents: nil,
                attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
              let input = try FileHandle(forReadingFrom: source)
              defer { try? input.close() }
              let output = try FileHandle(forWritingTo: target)
              defer { try? output.close() }
              while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
              }
              try output.synchronize()
              DispatchQueue.main.async { result(nil) }
            } catch {
              let message = error.localizedDescription
              DispatchQueue.main.async {
                result(FlutterError(code: "import_failed", message: message, details: nil))
              }
            }
          }
        case "restoreAll":
          var records = try load()
          var states: [String: String] = [:]
          for path in Array(records.keys) { states[path] = restore(path, records: &records) }
          result(states)
        case "restore":
          guard let path = args["path"] as? String else {
            result(FlutterError(code: "bad_args", message: "path required", details: nil))
            return
          }
          var records = try load()
          // Reuse an explicitly selected ancestor, but not lexical prefix siblings.
          let candidates = records.keys.filter { path == $0 || path.hasPrefix($0 + "/") }
            .sorted { $0.count > $1.count }
          let home = canonical(URL(fileURLWithPath: NSHomeDirectory()))
          let temporary = canonical(FileManager.default.temporaryDirectory)
          let resolvedPath = canonical(URL(fileURLWithPath: path))
          if candidates.isEmpty &&
            (resolvedPath == home || resolvedPath.hasPrefix(home + "/") ||
              resolvedPath == temporary || resolvedPath.hasPrefix(temporary + "/")) {
            result(readableDirectory(URL(fileURLWithPath: path)) ? "available" : "unavailable")
            return
          }
          var status = "needsAuthorization"
          for root in candidates {
            status = restore(root, records: &records)
            if status == "available" { break }
          }
          result(status)
        case "pick":
          guard !panelOpen else {
            result(FlutterError(code: "busy", message: "Directory panel already open", details: nil))
            return
          }
          // Load before presenting: never overwrite an unreadable grant store.
          _ = try load()
          panelOpen = true
          let panel = NSOpenPanel()
          panel.canChooseDirectories = true
          panel.canChooseFiles = false
          panel.allowsMultipleSelection = false
          panel.canCreateDirectories = true
          if let title = args["title"] as? String { panel.message = title }
          if let initial = args["initialDirectory"] as? String {
            panel.directoryURL = URL(fileURLWithPath: initial, isDirectory: true)
          }
          panel.begin { [self] response in
            defer { panelOpen = false }
            guard response == .OK, let url = panel.url else { result(nil); return }
            do {
              let path = canonical(url)
              if let expected = args["requiredPath"] as? String,
                path != canonical(URL(fileURLWithPath: expected, isDirectory: true)) {
                result(FlutterError(code: "wrong_directory",
                  message: "Select the requested directory", details: nil))
                return
              }
              var options: URL.BookmarkCreationOptions = [.withSecurityScope]
              if args["readOnly"] as? Bool == true { options.insert(.securityScopeAllowOnlyReadAccess) }
              let data = try url.bookmarkData(
                options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
              var records = try load()
              // Do not downgrade an existing read/write grant for another feature.
              let readOnly = args["readOnly"] as? Bool == true
              if !readOnly || restore(path, records: &records) != "available" {
                records[path] = Grant(data: data, readOnly: readOnly)
              }
              try save(records)
              if let previous = active.removeValue(forKey: path) {
                previous.stopAccessingSecurityScopedResource()
              }
              guard restore(path, records: &records) == "available" else {
                result(FlutterError(code: "unavailable",
                  message: "Cannot restore selected directory access", details: nil))
                return
              }
              result(path)
            } catch {
              result(FlutterError(code: "grant_failed", message: error.localizedDescription, details: nil))
            }
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "grant_store", message: error.localizedDescription, details: nil))
      }
    }
  }

  func stopAll() {
    for url in active.values { url.stopAccessingSecurityScopedResource() }
    active.removeAll()
  }
}
