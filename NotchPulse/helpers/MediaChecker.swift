//
//  MediaChecker.swift
//  NotchPulse
//
//  Created by Alexander on 2025-07-26.
//

import Foundation

final class MediaChecker: Sendable {

    enum MediaCheckerError: Error {
        case missingResources
        case processExecutionFailed
        case timeout
        case testInfrastructureFailure(String)
    }

    func checkDeprecationStatus() async throws -> Bool {
        try await Task.detached(priority: .userInitiated) {
            guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
                  let nowPlayingTestClientPath = Bundle.main.url(forResource: "MediaRemoteAdapterTestClient", withExtension: nil)?.path,
                  let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
            else {
                throw MediaCheckerError.missingResources
            }

            // Verify the framework binary actually exists on disk
            let frameworkBinaryPath = frameworkPath + "/MediaRemoteAdapter"
            guard FileManager.default.fileExists(atPath: frameworkBinaryPath) else {
                print("MediaChecker: MediaRemoteAdapter framework binary not found at \(frameworkBinaryPath)")
                throw MediaCheckerError.missingResources
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [scriptURL.path, frameworkPath, nowPlayingTestClientPath, "test"]

            // Capture stderr to distinguish real deprecation from test infrastructure failures
            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                throw MediaCheckerError.processExecutionFailed
            }

            // Timeout after 10 seconds
            let didExit: Bool = try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    process.waitUntilExit()
                    return true
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    if process.isRunning {
                        process.terminate()
                    }
                    return false // Timed out
                }
                for try await exited in group {
                    if exited {
                        group.cancelAll()
                        return true
                    }
                }
                throw MediaCheckerError.timeout
            }

            if !didExit {
                throw MediaCheckerError.timeout
            }

            let exitCode = process.terminationStatus

            // Exit code 0 means the test passed — NowPlaying is NOT deprecated
            if exitCode == 0 {
                return false
            }

            // Exit code 1 could mean either:
            // (a) Real deprecation: adapter_test() ran and determined MediaRemote is non-functional
            // (b) Infrastructure failure: framework failed to load, test client timed out, etc.
            //
            // We check stderr for known infrastructure failure messages.
            // If it's an infrastructure failure, we throw instead of falsely marking as deprecated.
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrString = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !stderrString.isEmpty {
                let knownInfraFailures = [
                    "Failed to load framework",
                    "Framework not found",
                    "Symbol",
                    "not found in",
                    "did not signal setup_done",
                    "Error executing",
                    "Missing",
                ]
                let isInfraFailure = knownInfraFailures.contains { stderrString.contains($0) }

                if isInfraFailure {
                    print("MediaChecker: Test infrastructure failure (not a real deprecation): \(stderrString)")
                    throw MediaCheckerError.testInfrastructureFailure(stderrString)
                }
            }

            // If we get here with exit code 1 and no known infra failure message,
            // it's likely a genuine deprecation signal from adapter_test()
            print("MediaChecker: adapter_test returned exit code \(exitCode), marking as deprecated")
            return true
        }.value
    }
}
