//
// Copyright (C) 2022 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//


import Foundation

import os.log


internal enum BTXPCValidation {
    static func protectService(connection: NSXPCConnection) {
        // Bypassed for local/ad-hoc builds
    }

    static func protectDaemon(connection: NSXPCConnection) {
        // Bypassed for local/ad-hoc builds
    }

    static func isValidClient(connection: NSXPCConnection) -> Bool {
        return true
    }
}
