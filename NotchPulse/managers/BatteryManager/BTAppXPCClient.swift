//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import os.log
import ServiceManagement

@BTBackgroundActor
internal enum BTAppXPCClient {
    /// Cache a single Authorization to preserve the manage right.
    private static var simpleAuth: SimpleAuthRef? = nil

    private static func getSimpleAuth() -> SimpleAuthRef? {
        guard let simpleAuth = self.simpleAuth else {
            let simpleAuth = SimpleAuth.empty()
            self.simpleAuth = simpleAuth
            return simpleAuth
        }
        return simpleAuth
    }

    static func getAuthorization() async throws -> Data {
        guard let simpleAuth = self.getSimpleAuth(),
              let data = SimpleAuth.toData(simpleAuth: simpleAuth) else {
            throw BTError.notAuthorized
        }
        return data
    }

    static func getDaemonAuthorization() async throws -> Data {
        guard let simpleAuth = self.getSimpleAuth(),
              SimpleAuth.acquireInteractive(simpleAuth: simpleAuth, rightName: kSMRightModifySystemDaemons),
              let data = SimpleAuth.toData(simpleAuth: simpleAuth) else {
            throw BTError.notAuthorized
        }
        return data
    }

    static func getManageAuthorization() async throws -> Data {
        guard let simpleAuth = self.getSimpleAuth(),
              SimpleAuth.acquireInteractive(simpleAuth: simpleAuth, rightName: BTAuthorizationRights.manage),
              let data = SimpleAuth.toData(simpleAuth: simpleAuth) else {
            throw BTError.notAuthorized
        }
        return data
    }
}
