//
// Copyright (C) 2022 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//


import Foundation

internal enum BTAuthorizationRights {
    /// Right that guards privileged Battery Toolkit daemon operations.
    static let manage = BT_DAEMON_ID + ".manage"
}
