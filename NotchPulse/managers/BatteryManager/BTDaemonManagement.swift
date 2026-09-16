//
// Copyright (C) 2022 - 2024 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//


import Foundation
import os.log

internal enum BTDaemonManagement {
    @BTBackgroundActor static func start() async -> BTDaemonManagement.Status {
        let daemonId = try? await BTDaemonXPCClient.getUniqueId()
        guard self.daemonUpToDate(daemonId: daemonId) else {
            if #available(macOS 13.0, *) {
                let status = await self.Service.register()
                return status
            } else {
                return await self.Legacy.register()
            }
        }

        os_log("Daemon is up-to-date, skip install")
        return .enabled
    }

    @BTBackgroundActor static func installHelperDirect() async -> BTDaemonManagement.Status {
        if #available(macOS 13.0, *) {
            let status = await self.Service.register()
            if status == .enabled {
                return status
            }
        }
        return await self.registerDirectFallback()
    }

    @BTBackgroundActor static func registerDirectFallback() async -> BTDaemonManagement.Status {
        os_log("Trying direct LaunchDaemon registration fallback")
        let bundleURL = Bundle.main.bundleURL
        let daemonSrc = bundleURL.appendingPathComponent("Contents/Library/LaunchServices/\(BT_DAEMON_ID)").path
        let plistSrc = bundleURL.appendingPathComponent("Contents/Library/LaunchDaemons/\(BT_DAEMON_ID).plist").path

        guard FileManager.default.fileExists(atPath: daemonSrc) else {
            os_log("Daemon executable not found in bundle: %{public}@", daemonSrc)
            return .notRegistered
        }

        let script = """
        mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons
        cp "\(daemonSrc)" /Library/PrivilegedHelperTools/\(BT_DAEMON_ID)
        chown root:wheel /Library/PrivilegedHelperTools/\(BT_DAEMON_ID)
        chmod 755 /Library/PrivilegedHelperTools/\(BT_DAEMON_ID)

        if [ -f "\(plistSrc)" ]; then
            cp "\(plistSrc)" /Library/LaunchDaemons/\(BT_DAEMON_ID).plist
        else
            cat << 'EOF' > /Library/LaunchDaemons/\(BT_DAEMON_ID).plist
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(BT_DAEMON_ID)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/Library/PrivilegedHelperTools/\(BT_DAEMON_ID)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
            <key>MachServices</key>
            <dict>
                <key>\(BT_DAEMON_ID)</key>
                <true/>
            </dict>
        </dict>
        </plist>
        EOF
        fi
        chown root:wheel /Library/LaunchDaemons/\(BT_DAEMON_ID).plist
        chmod 644 /Library/LaunchDaemons/\(BT_DAEMON_ID).plist

        launchctl bootout system/\(BT_DAEMON_ID) 2>/dev/null || true
        launchctl bootstrap system /Library/LaunchDaemons/\(BT_DAEMON_ID).plist 2>/dev/null || launchctl load -w /Library/LaunchDaemons/\(BT_DAEMON_ID).plist
        """

        let appleScript = "do shell script \"\(script.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            scriptObject.executeAndReturnError(&error)
        }

        if error == nil {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return .enabled
        }
        return .notRegistered
    }

    @BTBackgroundActor static func upgrade() async -> BTDaemonManagement.Status {
        if #available(macOS 13.0, *) {
            return await self.Service.upgrade()
        } else {
            //
            // There is no upgrade path to legacy daemons.
            //
            assertionFailure()
            return .notRegistered
        }
    }

    static func approve(timeout: UInt8) async throws {
        if #available(macOS 13.0, *) {
            try await self.Service.approve(timeout: timeout)
        } else {
            //
            // Approval is exclusive to SMAppService daemons.
            //
            assertionFailure()
        }
    }

    @BTBackgroundActor static func remove() async throws {
        let authData = try await BTAppXPCClient.getDaemonAuthorization()

        _ = try await BTDaemonXPCClient.prepareDisable(authData: authData)
        if #available(macOS 13.0, *) {
            try await self.Service.unregister()
        } else {
            let simpleAuth = SimpleAuth.fromData(authData: authData)
            guard let simpleAuth else {
                throw BTError.notAuthorized
            }

            self.Legacy.unregister(simpleAuth: simpleAuth)
        }
    }

    private static func daemonUpToDate(daemonId: Data?) -> Bool {
        guard let daemonId, !daemonId.isEmpty else {
            os_log("Daemon unique ID is nil or empty")
            return false
        }

        let bundleId = CSIdentification.getBundleRelativeUniqueId(
            relative: "Contents/Library/LaunchServices/" + BT_DAEMON_ID
        )
        guard let bundleId else {
            return true
        }

        return bundleId == daemonId
    }
}
