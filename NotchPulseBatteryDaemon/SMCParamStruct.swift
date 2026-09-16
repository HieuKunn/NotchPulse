import Foundation
import IOKit

public let kSMCKeyNotFound: UInt8 = 0x84
public let kSMCSuccess: UInt8 = 0
public let kSMCError: UInt8 = 1

public let kSMCUserClientOpen: UInt8 = 0
public let kSMCUserClientClose: UInt8 = 1
public let kSMCHandleYPCEvent: UInt8 = 2
public let kSMCReadKey: UInt8 = 5
public let kSMCWriteKey: UInt8 = 6
public let kSMCGetKeyCount: UInt8 = 7
public let kSMCGetKeyFromIndex: UInt8 = 8
public let kSMCGetKeyInfo: UInt8 = 9

public struct SMCVersion: Sendable {
    public var major: CUnsignedChar
    public var minor: CUnsignedChar
    public var build: CUnsignedChar
    public var reserved: CUnsignedChar
    public var release: CUnsignedShort

    public init(major: CUnsignedChar, minor: CUnsignedChar, build: CUnsignedChar, reserved: CUnsignedChar, release: CUnsignedShort) {
        self.major = major
        self.minor = minor
        self.build = build
        self.reserved = reserved
        self.release = release
    }
}

public struct SMCPLimitData: Sendable {
    public var version: UInt16
    public var length: UInt16
    public var cpuPLimit: UInt32
    public var gpuPLimit: UInt32
    public var memPLimit: UInt32

    public init(version: UInt16, length: UInt16, cpuPLimit: UInt32, gpuPLimit: UInt32, memPLimit: UInt32) {
        self.version = version
        self.length = length
        self.cpuPLimit = cpuPLimit
        self.gpuPLimit = gpuPLimit
        self.memPLimit = memPLimit
    }
}

public struct SMCKeyInfoData: Sendable {
    public var dataSize: UInt32
    public var dataType: UInt32
    public var dataAttributes: UInt8

    public init(dataSize: UInt32, dataType: UInt32, dataAttributes: UInt8) {
        self.dataSize = dataSize
        self.dataType = dataType
        self.dataAttributes = dataAttributes
    }
}

public struct SMCParamStruct: Sendable {
    public var key: UInt32
    public var vers: SMCVersion
    private var padding1: UInt16
    public var pLimitData: SMCPLimitData
    public var keyInfo: SMCKeyInfoData
    private var padding2_0: UInt8
    private var padding2_1: UInt16
    public var result: UInt8
    public var status: UInt8
    public var data8: UInt8
    private var padding3: UInt8
    public var data32: UInt32
    public var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    
    public init() {
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
