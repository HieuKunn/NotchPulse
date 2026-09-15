import Foundation
import IOKit

let kSMCKeyNotFound: UInt8 = 0x84
let kSMCSuccess: UInt8 = 0
let kSMCError: UInt8 = 1

let kSMCUserClientOpen: UInt8 = 0
let kSMCUserClientClose: UInt8 = 1
let kSMCHandleYPCEvent: UInt8 = 2
let kSMCReadKey: UInt8 = 5
let kSMCWriteKey: UInt8 = 6
let kSMCGetKeyCount: UInt8 = 7
let kSMCGetKeyFromIndex: UInt8 = 8
let kSMCGetKeyInfo: UInt8 = 9

struct SMCVersion {
    var major: CUnsignedChar
    var minor: CUnsignedChar
    var build: CUnsignedChar
    var reserved: CUnsignedChar
    var release: CUnsignedShort
}

struct SMCPLimitData {
    var version: UInt16
    var length: UInt16
    var cpuPLimit: UInt32
    var gpuPLimit: UInt32
    var memPLimit: UInt32
}

struct SMCKeyInfoData {
    var dataSize: UInt32
    var dataType: UInt32
    var dataAttributes: UInt8
}

struct SMCParamStruct {
    var key: UInt32
    var vers: SMCVersion
    private var padding1: UInt16
    var pLimitData: SMCPLimitData
    var keyInfo: SMCKeyInfoData
    private var padding2_0: UInt8
    private var padding2_1: UInt16
    var result: UInt8
    var status: UInt8
    var data8: UInt8
    private var padding3: UInt8
    var data32: UInt32
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    
    init() {
        self.key = 0
        self.vers = SMCVersion(major: 0, minor: 0, build: 0, reserved: 0, release: 0)
        self.padding1 = 0
        self.pLimitData = SMCPLimitData(version: 0, length: 0, cpuPLimit: 0, gpuPLimit: 0, memPLimit: 0)
        self.keyInfo = SMCKeyInfoData(dataSize: 0, dataType: 0, dataAttributes: 0)
        self.padding2_0 = 0
        self.padding2_1 = 0
        self.result = 0
        self.status = 0
        self.data8 = 0
        self.padding3 = 0
        self.data32 = 0
        self.bytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }
}
