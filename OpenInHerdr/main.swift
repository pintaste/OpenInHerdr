// main.swift
// OpenInHerdr — Finder toolbar app that opens the current directory in Herdr

import Cocoa
import ScriptingBridge

// MARK: - Constants

private let herdrBundleId = "dev.herdr.app"
private let herdrFallbackPaths = [
    NSHomeDirectory() + "/Applications/Herdr.app",
    "/Applications/Herdr.app",
]
/// How long to wait for a freshly launched Herdr window to accept commands.
private let launchTimeout: TimeInterval = 15

// MARK: - Herdr location

/// Prefer Launch Services (bundle id), then ~/Applications, then /Applications.
func resolveHerdrAppURL() -> URL? {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: herdrBundleId) {
        return url
    }
    for path in herdrFallbackPaths where FileManager.default.fileExists(atPath: path) {
        return URL(fileURLWithPath: path)
    }
    return nil
}

/// The app binary doubles as the `herdr-app` CLI (`Herdr do space.new ...`).
func resolveHerdrCLIURL(appURL: URL) -> URL? {
    let cli = Bundle(url: appURL)?.executableURL
        ?? appURL.appendingPathComponent("Contents/MacOS/Herdr")
    return FileManager.default.isExecutableFile(atPath: cli.path) ? cli : nil
}

// MARK: - Finder path
//
// ScriptingBridge returns SBScriptableApplication (a private subclass of SBApplication).
// Swift's @objc optional protocol calls use respondsToSelector: first, which returns
// false for ScriptingBridge's dynamically-forwarded methods. We bypass this by using
// perform(_:) to send the ObjC message directly, letting ScriptingBridge forward it
// as an Apple Event — which is what triggers the TCC permission dialog.

func desktopPath() -> String {
    FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
        .first?.path ?? NSHomeDirectory() + "/Desktop"
}

/// If the URL is a file, return its parent directory; if a folder, return itself.
func directoryPath(from url: URL) -> String {
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
       !isDirectory.boolValue {
        return url.deletingLastPathComponent().path
    }
    return url.path
}

func urlFromFinderItem(_ item: NSObject) -> URL? {
    if let urlStr = item.value(forKey: "URL") as? String, let url = URL(string: urlStr) {
        return url
    }
    // Some items need an extra get() to resolve the SBObject proxy.
    if let resolved = (item as? SBObject)?.get() as? NSObject,
       let urlStr = resolved.value(forKey: "URL") as? String,
       let url = URL(string: urlStr) {
        return url
    }
    return nil
}

func finderItems(from raw: Any?) -> [NSObject] {
    if let arr = raw as? [NSObject] { return arr }
    if let nsa = raw as? NSArray { return nsa.compactMap { $0 as? NSObject } }
    if let sb = raw as? SBElementArray {
        return (0..<sb.count).compactMap { sb.object(at: $0) as? NSObject }
    }
    return []
}

/// Selection first (file → parent), then front Finder window, then Desktop.
func finderPath() -> String {
    let desktop = desktopPath()
    guard let app = SBApplication(bundleIdentifier: "com.apple.Finder") else { return desktop }

    // 1) Selected items (OpenInTerminal-style)
    if let selection = app.perform(NSSelectorFromString("selection"))?
        .takeUnretainedValue() as? SBObject {
        let items = finderItems(from: selection.get())
        if let first = items.first, let url = urlFromFinderItem(first) {
            return directoryPath(from: url)
        }
    }

    // 2) Frontmost Finder window target
    if let windows = app.perform(NSSelectorFromString("FinderWindows"))?
        .takeUnretainedValue() as? SBElementArray,
       windows.count > 0,
       let firstWindow = windows.firstObject as? NSObject,
       let target = firstWindow.value(forKey: "target") as? SBObject,
       let item = target.get() as? NSObject,
       let url = urlFromFinderItem(item) {
        return directoryPath(from: url)
    }

    return desktop
}

/// A folder passed on the command line wins over Finder (handy for testing:
/// `OpenInHerdr.app/Contents/MacOS/OpenInHerdr /some/dir`).
func targetPath() -> String {
    let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
    if let arg = args.first {
        return directoryPath(from: URL(fileURLWithPath: arg))
    }
    return finderPath()
}

// MARK: - Process helpers

@discardableResult
func runProcess(executable: URL, arguments: [String]) -> (output: String, status: Int32) {
    let p = Process()
    p.executableURL = executable
    p.arguments = arguments
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do {
        try p.run()
    } catch {
        return ("", 1)
    }
    // Read before waiting so a large `ls` can't fill the pipe and block.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (output, p.terminationStatus)
}

func herdr(_ cli: URL, _ args: [String]) -> (output: String, status: Int32) {
    runProcess(executable: cli, arguments: args)
}

func jsonObject(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

/// `herdr-app ls` / `do` print this when no Herdr window is open.
func isNoWindowError(_ output: String) -> Bool {
    output.contains("no Herdr window")
}

func isWindowReady(cli: URL) -> Bool {
    let (out, status) = herdr(cli, ["ls"])
    return status == 0 && !isNoWindowError(out) && jsonObject(out) != nil
}

func activateHerdr() {
    let app = NSWorkspace.shared.runningApplications
        .first { $0.bundleIdentifier == herdrBundleId }
    if #available(macOS 14.0, *) {
        app?.activate()
    } else {
        app?.activate(options: .activateIgnoringOtherApps)
    }
}

/// Launch Herdr through Launch Services (not as our child), so it outlives us.
func launchHerdr(appURL: URL) -> Bool {
    runProcess(
        executable: URL(fileURLWithPath: "/usr/bin/open"),
        arguments: ["-a", appURL.path]
    ).status == 0
}

func waitForWindow(cli: URL, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if isWindowReady(cli: cli) { return true }
        Thread.sleep(forTimeInterval: 0.25)
    }
    return false
}

// MARK: - Spaces

func normalizedPath(_ path: String) -> String {
    // Resolve /tmp → /private/tmp etc. so Finder paths match Herdr's folders.
    URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
}

/// A local space whose folder is this path (from `herdr-app ls`), if any.
func existingSpaceId(cli: URL, path: String) -> String? {
    let (out, status) = herdr(cli, ["ls"])
    guard status == 0,
          let root = jsonObject(out),
          let spaces = root["spaces"] as? [[String: Any]] else { return nil }
    let want = normalizedPath(path)
    return spaces.first { space in
        let isLocal = space["machine"] == nil || space["machine"] is NSNull
        guard isLocal, let folder = space["folder"] as? String else { return false }
        return normalizedPath(folder) == want
    }?["id"] as? String
}

/// Same folder already open → new tab in that space; otherwise a new space.
func openInRunningHerdr(cli: URL, path: String) -> (ok: Bool, output: String) {
    if let spaceId = existingSpaceId(cli: cli, path: path) {
        let (out, status) = herdr(cli, ["do", "tab.new", "--space", spaceId, "--folder", path])
        if status == 0 {
            _ = herdr(cli, ["do", "space.select", "--id", spaceId])
            return (true, out)
        }
    }
    let (out, status) = herdr(cli, ["do", "space.new", "--folder", path])
    return (status == 0, out)
}

// MARK: - Errors

func notifyError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "OpenInHerdr"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.runModal()
}

// MARK: - Main

let path = targetPath()

guard let appURL = resolveHerdrAppURL() else {
    notifyError("找不到 Herdr。请从 https://herdr.dev 安装后重试（支持 ~/Applications、/Applications 或其它 Launch Services 可发现的位置）。")
    exit(1)
}

guard let cliURL = resolveHerdrCLIURL(appURL: appURL) else {
    notifyError("Herdr 安装不完整：找不到 \(appURL.path)/Contents/MacOS/Herdr。")
    exit(1)
}

var lastOutput = ""

if !isWindowReady(cli: cliURL) {
    if !launchHerdr(appURL: appURL) || !waitForWindow(cli: cliURL, timeout: launchTimeout) {
        notifyError("Herdr 窗口没有在 \(Int(launchTimeout)) 秒内就绪，无法打开：\n\(path)")
        exit(1)
    }
}

let result = openInRunningHerdr(cli: cliURL, path: path)
if result.ok {
    activateHerdr()
    exit(0)
}
lastOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

var detail = "无法在 Herdr 中打开：\n\(path)"
if !lastOutput.isEmpty {
    detail += "\n\nHerdr 返回：\(lastOutput)"
}
detail += "\n\n若刚拒绝过权限：系统设置 → 隐私与安全性 → 自动化 → OpenInHerdr → Finder。\n也可运行：tccutil reset AppleEvents com.local.OpenInHerdr"
notifyError(detail)
exit(1)
