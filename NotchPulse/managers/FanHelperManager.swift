//
//  FanHelperManager.swift
//  NotchPulse
//
//  Standalone manager for NotchPulse's native privileged fan helper daemon.
//  Installs, checks status, and registers launchd daemon via AppleScript admin prompt.
//

import Foundation
import AppKit

public final class FanHelperManager: ObservableObject {
    public static let shared = FanHelperManager()

    public static let socketPath = "/var/run/notchpulse_fan.sock"
    public static let daemonPlistPath = "/Library/LaunchDaemons/com.notchpulse.fanhelper.plist"
    public static let installedBinaryPath = "/Library/PrivilegedHelperTools/notchpulse-fanhelper"

    @Published public private(set) var isHelperInstalled: Bool = false
    @Published public private(set) var isInstalling: Bool = false

    private init() {
        checkHelperStatus()
    }

    /// Checks if the helper binary, plist, and control socket are active
    @discardableResult
    public func checkHelperStatus() -> Bool {
        let binExists = FileManager.default.fileExists(atPath: Self.installedBinaryPath)
        let plistExists = FileManager.default.fileExists(atPath: Self.daemonPlistPath)
        let sockExists = FileManager.default.fileExists(atPath: Self.socketPath)

        let installed = (binExists && plistExists) || sockExists
        DispatchQueue.main.async { [weak self] in
            self?.isHelperInstalled = installed
        }
        return installed
    }

    /// Automatically prompts for administrator privileges and installs helper if not already running
    public func promptInstallIfNeeded(onSuccess: (() -> Void)? = nil) {
        guard !checkHelperStatus() && !isInstalling else {
            onSuccess?()
            return
        }
        installHelper { success in
            if success {
                onSuccess?()
            }
        }
    }

    /// Prompts user with native macOS admin authentication to install the privileged daemon
    public func installHelper(completion: @escaping (Bool) -> Void) {
        isInstalling = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Locate bundled helper binary
            var sourceBinaryPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/notchpulse-fanhelper").path
            if !FileManager.default.fileExists(atPath: sourceBinaryPath) {
                // Fallback to local source tree if running from dev build
                let fallback = "/Users/hieukunn/Learning ITM/My project/NotchPulse/NotchPulse/Resources/notchpulse-fanhelper"
                if FileManager.default.fileExists(atPath: fallback) {
                    sourceBinaryPath = fallback
                }
            }

            guard FileManager.default.fileExists(atPath: sourceBinaryPath) else {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion(false)
                }
                return
            }

            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.notchpulse.fanhelper</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(Self.installedBinaryPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
            </dict>
            </plist>
            """

            let tmpPlistPath = "/tmp/com.notchpulse.fanhelper.plist"
            try? plistContent.write(toFile: tmpPlistPath, atomically: true, encoding: .utf8)

            let script = """
            do shell script "mkdir -p /Library/PrivilegedHelperTools && cp -f '\(sourceBinaryPath)' '\(Self.installedBinaryPath)' && chown root:wheel '\(Self.installedBinaryPath)' && chmod 755 '\(Self.installedBinaryPath)' && cp -f '\(tmpPlistPath)' '\(Self.daemonPlistPath)' && chown root:wheel '\(Self.daemonPlistPath)' && chmod 644 '\(Self.daemonPlistPath)' && launchctl bootout system/com.notchpulse.fanhelper 2>/dev/null; launchctl bootstrap system '\(Self.daemonPlistPath)' 2>/dev/null || launchctl load -w '\(Self.daemonPlistPath)'" with administrator privileges with prompt "NotchPulse requires administrator privileges to enable direct hardware fan speed control."
            """

            var errorDict: NSDictionary?
            let appleScript = NSAppleScript(source: script)
            _ = appleScript?.executeAndReturnError(&errorDict)

            try? FileManager.default.removeItem(atPath: tmpPlistPath)

            Thread.sleep(forTimeInterval: 0.5)
            let success = self.checkHelperStatus()

            DispatchQueue.main.async {
                self.isInstalling = false
                completion(success)
            }
        }
    }

    /// Sends command to the privileged daemon socket
    @discardableResult
    public func sendCommand(_ command: String) -> Bool {
        let sock = Self.socketPath
        guard FileManager.default.fileExists(atPath: sock) else { return false }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        _ = sock.withCString {
            strncpy(&addr.sun_path.0, $0, maxLen - 1)
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return false }

        let cmdStr = command + "\n"
        guard let data = cmdStr.data(using: .utf8) else { return false }

        return data.withUnsafeBytes { ptr in
            write(fd, ptr.baseAddress!, data.count) > 0
        }
    }
}
