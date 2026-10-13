//
//  notchpulse-fanhelper.c
//  NotchPulse
//
//  Privileged native helper daemon for Apple Silicon and Intel fan control.
//  Zero-dependency, standalone IOKit C binary matching ThermalForge kernel algorithms.
//  Runs as root via launchd and communicates through /var/run/notchpulse_fan.sock.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <signal.h>
#include <mach/mach.h>
#include <IOKit/IOKitLib.h>

#define SOCKET_PATH "/var/run/notchpulse_fan.sock"

#pragma pack(push, 1)
typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfo;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    uint16_t _pad0;
    SMCPLimitData pLimitData;
    SMCKeyInfo keyInfo;
    uint8_t _pad1;
    uint16_t padding;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint8_t _pad2;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParamStruct;
#pragma pack(pop)

static io_connect_t g_conn = 0;
static char g_modeKeyTemplate[8] = "F%dMd";
static int g_hasFtst = 0;
static volatile int g_running = 1;

static uint32_t fourCC(const char* s) {
    uint32_t ans = 0;
    for (int i = 0; i < 4 && s[i] != '\0'; i++) {
        ans = (ans << 8) | (uint8_t)s[i];
    }
    return ans;
}

static int smcOpen(void) {
    if (g_conn != 0) return 1;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self_, 0, &g_conn);
    IOObjectRelease(service);
    return (kr == kIOReturnSuccess && g_conn != 0);
}

static kern_return_t callSMC(SMCParamStruct* in, SMCParamStruct* out) {
    if (!smcOpen()) return kIOReturnNotOpen;
    size_t inSize = sizeof(SMCParamStruct);
    size_t outSize = sizeof(SMCParamStruct);
    return IOConnectCallStructMethod(g_conn, 2, in, inSize, out, &outSize);
}

static int smcGetKeyInfo(const char* key, uint32_t* outSize, uint32_t* outType) {
    SMCParamStruct in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = fourCC(key);
    in.data8 = 9; // SMCCommand.readKeyInfo
    kern_return_t kr = callSMC(&in, &out);
    if (kr != kIOReturnSuccess || out.result != 0) {
        return 0;
    }
    if (outSize) *outSize = out.keyInfo.dataSize;
    if (outType) *outType = out.keyInfo.dataType;
    return 1;
}

static int smcReadKey(const char* key, uint8_t* outBytes, uint32_t* outSize) {
    uint32_t dataSize = 0;
    uint32_t dataType = 0;
    if (!smcGetKeyInfo(key, &dataSize, &dataType) || dataSize == 0) {
        return 0;
    }
    SMCParamStruct in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = fourCC(key);
    in.keyInfo.dataSize = dataSize;
    in.keyInfo.dataType = dataType;
    in.data8 = 5; // SMCCommand.readBytes
    kern_return_t kr = callSMC(&in, &out);
    if (kr != kIOReturnSuccess || out.result != 0) {
        return 0;
    }
    if (outBytes) {
        memcpy(outBytes, out.bytes, dataSize);
    }
    if (outSize) *outSize = dataSize;
    return 1;
}

static int smcWriteKey(const char* key, const uint8_t* bytes, uint32_t size) {
    uint32_t keyDataSize = 0;
    uint32_t keyDataType = 0;
    // CRITICAL: ThermalForge requirement - query key info before write
    if (!smcGetKeyInfo(key, &keyDataSize, &keyDataType)) {
        return 0;
    }
    SMCParamStruct in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = fourCC(key);
    in.data8 = 6; // SMCCommand.writeBytes
    in.keyInfo.dataSize = (keyDataSize > 0) ? keyDataSize : size;
    in.keyInfo.dataType = keyDataType;
    uint32_t copyLen = (size < in.keyInfo.dataSize) ? size : in.keyInfo.dataSize;
    memcpy(in.bytes, bytes, copyLen);
    kern_return_t kr = callSMC(&in, &out);
    return (kr == kIOReturnSuccess && out.result == 0);
}

static void initHardware(void) {
    uint8_t bytes[32];
    uint32_t sz = 0;
    // ThermalForge hardware detection: M5 Max uses F%dmd, M1-M4 use F%dMd
    if (smcReadKey("F0md", bytes, &sz)) {
        strncpy(g_modeKeyTemplate, "F%dmd", sizeof(g_modeKeyTemplate));
    } else {
        strncpy(g_modeKeyTemplate, "F%dMd", sizeof(g_modeKeyTemplate));
    }

    uint32_t ftstSize = 0;
    if (smcGetKeyInfo("Ftst", &ftstSize, NULL) && ftstSize > 0) {
        g_hasFtst = 1;
    } else {
        g_hasFtst = 0;
    }
}

static int getFanCount(void) {
    uint8_t bytes[32];
    uint32_t sz = 0;
    if (smcReadKey("FNum", bytes, &sz) && sz >= 1 && bytes[0] > 0) {
        return (int)bytes[0];
    }
    uint32_t probe = 0;
    if (smcGetKeyInfo("F0Ac", &probe, NULL)) {
        if (smcGetKeyInfo("F1Ac", &probe, NULL)) {
            return 2;
        }
        return 1;
    }
    return 0;
}

static int unlockFans(void) {
    int count = getFanCount();
    if (count <= 0) return 0;

    if (g_hasFtst) {
        // M1-M4 path: Ftst unlock suppresses thermalmonitord
        uint8_t one = 1;
        smcWriteKey("Ftst", &one, 1);
        usleep(500000); // 500ms
    }

    // Set each fan to manual mode with retry loop (up to 10s like ThermalForge)
    for (int i = 0; i < count; i++) {
        char modeKey[16];
        snprintf(modeKey, sizeof(modeKey), g_modeKeyTemplate, i);
        uint8_t one = 1;
        int unlocked = 0;
        for (int retry = 0; retry < 100; retry++) {
            if (smcWriteKey(modeKey, &one, 1)) {
                unlocked = 1;
                break;
            }
            usleep(100000); // 100ms
        }
        if (!unlocked) {
            return 0;
        }
    }
    return 1;
}

static int setFanRPM(float rpm) {
    int count = getFanCount();
    if (count <= 0) return 0;
    unlockFans();

    for (int i = 0; i < count; i++) {
        char targetKey[16];
        snprintf(targetKey, sizeof(targetKey), "F%dTg", i);
        smcWriteKey(targetKey, (const uint8_t*)&rpm, 4);
    }
    return 1;
}

static void resetAuto(void) {
    int count = getFanCount();
    uint8_t zero = 0;
    float zeroF = 0.0f;
    for (int i = 0; i < count; i++) {
        char modeKey[16];
        snprintf(modeKey, sizeof(modeKey), g_modeKeyTemplate, i);
        smcWriteKey(modeKey, &zero, 1);

        char targetKey[16];
        snprintf(targetKey, sizeof(targetKey), "F%dTg", i);
        smcWriteKey(targetKey, (const uint8_t*)&zeroF, 4);
    }
    if (g_hasFtst) {
        smcWriteKey("Ftst", &zero, 1);
    }
    uint16_t zero16 = 0;
    smcWriteKey("FS! ", (const uint8_t*)&zero16, 2);
}

static void sigHandler(int sig) {
    (void)sig;
    g_running = 0;
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;
    signal(SIGTERM, sigHandler);
    signal(SIGINT, sigHandler);

    initHardware();

    unlink(SOCKET_PATH);
    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) return 1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(server_fd);
        return 1;
    }

    chmod(SOCKET_PATH, 0666);
    listen(server_fd, 8);

    while (g_running) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) break;

        char buf[128];
        ssize_t n = read(client_fd, buf, sizeof(buf) - 1);
        if (n > 0) {
            buf[n] = '\0';
            if (strncmp(buf, "auto", 4) == 0) {
                resetAuto();
                write(client_fd, "OK\n", 3);
            } else if (strncmp(buf, "max", 3) == 0) {
                setFanRPM(6500.0f);
                write(client_fd, "OK\n", 3);
            } else if (strncmp(buf, "set ", 4) == 0) {
                float rpm = (float)atof(buf + 4);
                if (rpm > 0.0f) {
                    setFanRPM(rpm);
                }
                write(client_fd, "OK\n", 3);
            } else if (strncmp(buf, "ping", 4) == 0) {
                write(client_fd, "PONG\n", 5);
            } else if (strncmp(buf, "status", 6) == 0) {
                char reply[64];
                snprintf(reply, sizeof(reply), "FANS:%d MODE:%s\n", getFanCount(), g_modeKeyTemplate);
                write(client_fd, reply, strlen(reply));
            } else {
                write(client_fd, "ERR\n", 4);
            }
        }
        close(client_fd);
    }

    resetAuto();
    close(server_fd);
    unlink(SOCKET_PATH);
    if (g_conn != 0) {
        IOServiceClose(g_conn);
    }
    return 0;
}
