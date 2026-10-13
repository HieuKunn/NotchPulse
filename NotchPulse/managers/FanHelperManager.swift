//
//  FanHelperManager.swift
//  NotchPulse
//
//  Unified manager for NotchPulse's native privileged fan helper daemon.
//  Supports:
//  1. Silent installation via stored master credentials in NotchPulseVault (zero prompts)
//  2. Unified NotchPulse password overlay integration (one password for Face ID, App, & Fans)
//  3. Native AppleScript admin prompt fallback if needed.
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
        // If not installed yet but user already enrolled password in Vault, install silently
        if !isHelperInstalled && NotchPulseVault.hasStoredPassword() {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.installWithStoredPassword()
            }
        }
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

    /// Automatically installs helper if needed:
    /// - Uses NotchPulseVault master password silently if present (0 clicks / 0 prompts)
    /// - Otherwise presents unified NotchPulse password dialog
    public func promptInstallIfNeeded(onSuccess: (() -> Void)? = nil) {
        if checkHelperStatus() {
            onSuccess?()
            return
        }
        guard !isInstalling else { return }

        // 1. Silent install via NotchPulseVault if password already exists
        if NotchPulseVault.hasStoredPassword() {
            installWithStoredPassword { [weak self] success in
                if success {
                    onSuccess?()
                } else {
                    // Stored password was rejected or session locked -> present unified prompt
                    DispatchQueue.main.async {
                        self?.presentUnifiedPasswordPrompt(onSuccess: onSuccess)
                    }
                }
            }
            return
        }

        // 2. Present unified NotchPulse master auth prompt
        DispatchQueue.main.async { [weak self] in
            self?.presentUnifiedPasswordPrompt(onSuccess: onSuccess)
        }
    }

    /// Presents unified Notch overlay password prompt (shared with Face ID & App unlock)
    public func presentUnifiedPasswordPrompt(onSuccess: (() -> Void)? = nil) {
        FaceIDEnrollmentController.startPasswordOnly(onComplete: {
            if Self.shared.checkHelperStatus() {
                onSuccess?()
            } else {
                // As fallback if notch was cancelled or unsupported, fallback to AppleScript
                Self.shared.installHelperViaAppleScript { success in
                    if success { onSuccess?() }
                }
            }
        })
    }

    /// Tries silent installation using the password stored in NotchPulseVault
    @discardableResult
    public func installWithStoredPassword(completion: ((Bool) -> Void)? = nil) -> Bool {
        guard NotchPulseVault.hasStoredPassword() else {
            completion?(false)
            return false
        }
        do {
            let passwordData = try NotchPulseVault.readPassword()
            guard !passwordData.isEmpty else {
                completion?(false)
                return false
            }
            let password = String(decoding: passwordData, as: UTF8.self)
            return installWithPassword(password, completion: completion)
        } catch {
            completion?(false)
            return false
        }
    }

    /// Installs helper daemon directly using administrator password via sudo standard input
    @discardableResult
    public func installWithPassword(_ password: String, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard !password.isEmpty else {
            completion?(false)
            return false
        }

        isInstalling = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Locate bundled helper binary
            var sourceBinaryPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/notchpulse-fanhelper").path
            if !FileManager.default.fileExists(atPath: sourceBinaryPath) {
                let fallback = "/Users/hieukunn/Learning ITM/My project/NotchPulse/NotchPulse/Resources/notchpulse-fanhelper"
                if FileManager.default.fileExists(atPath: fallback) {
                    sourceBinaryPath = fallback
                }
            }

            guard FileManager.default.fileExists(atPath: sourceBinaryPath) else {
                DispatchQueue.main.async {
                    self.isInstalling = false
                    completion?(false)
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

            let shellScript = "mkdir -p /Library/PrivilegedHelperTools && cp -f '\(sourceBinaryPath)' '\(Self.installedBinaryPath)' && chown root:wheel '\(Self.installedBinaryPath)' && chmod 755 '\(Self.installedBinaryPath)' && cp -f '\(tmpPlistPath)' '\(Self.daemonPlistPath)' && chown root:wheel '\(Self.daemonPlistPath)' && chmod 644 '\(Self.daemonPlistPath)' && (launchctl bootout system/com.notchpulse.fanhelper 2>/dev/null || true); (launchctl bootstrap system '\(Self.daemonPlistPath)' 2>/dev/null || launchctl load -w '\(Self.daemonPlistPath)' 2>/dev/null)"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-S", "--", "/bin/sh", "-c", shellScript]

            let inPipe = Pipe()
            process.standardInput = inPipe
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                if let pwData = (password + "\n").data(using: .utf8) {
                    inPipe.fileHandleForWriting.write(pwData)
                    try? inPipe.fileHandleForWriting.close()
                }
                process.waitUntilExit()
            } catch {
                print("FanHelper install error: \(error)")
            }

            try? FileManager.default.removeItem(atPath: tmpPlistPath)

            Thread.sleep(forTimeInterval: 0.5)
            let success = self.checkHelperStatus()

            DispatchQueue.main.async {
                self.isInstalling = false
                completion?(success)
            }
        }

        return true
    }

    /// Legacy fallback: Prompts user with native macOS AppleScript security dialog
    public func installHelperViaAppleScript(completion: @escaping (Bool) -> Void) {
        isInstalling = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var sourceBinaryPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/notchpulse-fanhelper").path
            if !FileManager.default.fileExists(atPath: sourceBinaryPath) {
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
