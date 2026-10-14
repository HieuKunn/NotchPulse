#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <signal.h>
#include <pthread.h>
#include <time.h>
#include <mach/mach.h>
#include <IOKit/IOKitLib.h>

#define SOCKET_PATH "/var/run/notchpulse_fan.sock"
#define DAEMON_VERSION "2.1.0"
#define HEARTBEAT_TIMEOUT_SEC 15.0
#define SAFETY_OVERRIDE_TEMP 95.0f

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

typedef struct {
    float actual;
    float target;
    float min;
    float max;
    int isManual;
} FanData;

static io_connect_t g_conn = 0;
static char g_modeKeyTemplate[8] = "F%dMd";
static int g_hasFtst = 0;
static volatile int g_running = 1;
static volatile int g_manualEngaged = 0;
static volatile time_t g_lastHeartbeat = 0;
static pthread_mutex_t g_smcMutex = PTHREAD_MUTEX_INITIALIZER;

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

static float readFloatKey(const char* key) {
    uint8_t bytes[32];
    uint32_t sz = 0;
    uint32_t dataType = 0;
    if (!smcGetKeyInfo(key, &sz, &dataType) || sz == 0) {
        return 0.0f;
    }
    if (smcReadKey(key, bytes, &sz)) {
        if (dataType == fourCC("flt ") && sz >= 4) {
            float val = 0.0f;
            memcpy(&val, bytes, 4);
            return val;
        } else if ((dataType == fourCC("ioft") || sz >= 8) && sz >= 4) {
            // ioft 16.16 fixed point (ThermalForge GPU format on M3/M4/M5 Max)
            uint32_t raw = 0;
            memcpy(&raw, bytes, 4);
            float integer = (float)(raw >> 16);
            float fraction = (float)(raw & 0xFFFF) / 65536.0f;
            return integer + fraction;
        } else if ((dataType == fourCC("sp78") || dataType == fourCC("sp87")) && sz >= 2) {
            // Intel temperature fixed point: byte 0 signed integer, byte 1 fraction / 256.0f
            return (float)(int8_t)bytes[0] + ((float)bytes[1] / 256.0f);
        } else if (dataType == fourCC("fpe2") && sz >= 2) {
            // fpe2 legacy fan RPM fixed point: raw / 4.0f
            uint16_t raw = ((uint16_t)bytes[0] << 8) | (uint16_t)bytes[1];
            return (float)raw / 4.0f;
        } else if (sz == 4) {
            // Fallback for 4-byte values
            float val = 0.0f;
            memcpy(&val, bytes, 4);
            return val;
        }
    }
    return 0.0f;
}

static int writeFanTargetRPM(const char* key, float rpm) {
    uint32_t keyDataSize = 0;
    uint32_t keyDataType = 0;
    if (!smcGetKeyInfo(key, &keyDataSize, &keyDataType)) {
        return 0;
    }
    if (keyDataType == fourCC("fpe2") && keyDataSize == 2) {
        uint16_t raw = (uint16_t)(rpm * 4.0f);
        uint8_t buf[2] = { (uint8_t)(raw >> 8), (uint8_t)(raw & 0xFF) };
        return smcWriteKey(key, buf, 2);
    } else {
        float f = rpm;
        return smcWriteKey(key, (const uint8_t*)&f, 4);
    }
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
    if (g_manualEngaged) return 1;
    int count = getFanCount();
    if (count <= 0) return 0;

    if (g_hasFtst) {
        // M1-M4 path: Ftst=1 suppresses thermalmonitord (500ms match ThermalForge)
        uint8_t one = 1;
        smcWriteKey("Ftst", &one, 1);
        usleep(500000); // 500ms
    }

    // Set each fan to manual mode with retry deadline (up to 5s)
    for (int i = 0; i < count; i++) {
        char modeKey[16];
        snprintf(modeKey, sizeof(modeKey), g_modeKeyTemplate, i);
        uint8_t one = 1;
        int unlocked = 0;
        for (int retry = 0; retry < 50; retry++) {
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
    g_manualEngaged = 1;
    return 1;
}

static void resetAuto(void) {
    pthread_mutex_lock(&g_smcMutex);
    int count = getFanCount();
    uint8_t zero = 0;
    for (int i = 0; i < count; i++) {
        char modeKey[16];
        snprintf(modeKey, sizeof(modeKey), g_modeKeyTemplate, i);
        smcWriteKey(modeKey, &zero, 1);

        char targetKey[16];
        snprintf(targetKey, sizeof(targetKey), "F%dTg", i);
        writeFanTargetRPM(targetKey, 0.0f);
    }
    if (g_hasFtst) {
        smcWriteKey("Ftst", &zero, 1);
    }
    uint16_t zero16 = 0;
    smcWriteKey("FS! ", (const uint8_t*)&zero16, 2);
    g_manualEngaged = 0;
    pthread_mutex_unlock(&g_smcMutex);
}

static int setFanMax(void) {
    pthread_mutex_lock(&g_smcMutex);
    int count = getFanCount();
    if (count <= 0) {
        pthread_mutex_unlock(&g_smcMutex);
        return 0;
    }
    if (!g_manualEngaged) {
        if (!unlockFans()) {
            pthread_mutex_unlock(&g_smcMutex);
            return 0;
        }
    }

    for (int i = 0; i < count; i++) {
        char maxKey[16];
        snprintf(maxKey, sizeof(maxKey), "F%dMx", i);
        float maxRPM = readFloatKey(maxKey);
        if (maxRPM <= 0.0f) maxRPM = 6550.0f;

        char targetKey[16];
        snprintf(targetKey, sizeof(targetKey), "F%dTg", i);
        writeFanTargetRPM(targetKey, maxRPM);
    }
    g_manualEngaged = 1;
    g_lastHeartbeat = time(NULL);
    pthread_mutex_unlock(&g_smcMutex);
    return 1;
}

static int setFanRPM(float rpm) {
    pthread_mutex_lock(&g_smcMutex);
    int count = getFanCount();
    if (count <= 0) {
        pthread_mutex_unlock(&g_smcMutex);
        return 0;
    }
    if (!g_manualEngaged) {
        if (!unlockFans()) {
            pthread_mutex_unlock(&g_smcMutex);
            return 0;
        }
    }

    for (int i = 0; i < count; i++) {
        char minKey[16];
        snprintf(minKey, sizeof(minKey), "F%dMn", i);
        float minRPM = readFloatKey(minKey);
        if (minRPM <= 0.0f) minRPM = 2000.0f;

        char maxKey[16];
        snprintf(maxKey, sizeof(maxKey), "F%dMx", i);
        float maxRPM = readFloatKey(maxKey);
        if (maxRPM <= 0.0f) maxRPM = 6550.0f;

        float clamped = rpm;
        if (clamped < minRPM) clamped = minRPM;
        if (clamped > maxRPM) clamped = maxRPM;

        char targetKey[16];
        snprintf(targetKey, sizeof(targetKey), "F%dTg", i);
        writeFanTargetRPM(targetKey, clamped);
    }
    g_manualEngaged = 1;
    g_lastHeartbeat = time(NULL);
    pthread_mutex_unlock(&g_smcMutex);
    return 1;
}

static int setSingleFanRPM(int fanIndex, float rpm) {
    pthread_mutex_lock(&g_smcMutex);
    int count = getFanCount();
    if (fanIndex < 0 || fanIndex >= count) {
        pthread_mutex_unlock(&g_smcMutex);
        return 0;
    }
    if (!g_manualEngaged) {
        if (!unlockFans()) {
            pthread_mutex_unlock(&g_smcMutex);
            return 0;
        }
    }

    char minKey[16];
    snprintf(minKey, sizeof(minKey), "F%dMn", fanIndex);
    float minRPM = readFloatKey(minKey);
    if (minRPM <= 0.0f) minRPM = 2000.0f;

    char maxKey[16];
    snprintf(maxKey, sizeof(maxKey), "F%dMx", fanIndex);
    float maxRPM = readFloatKey(maxKey);
    if (maxRPM <= 0.0f) maxRPM = 6550.0f;

    float clamped = rpm;
    if (clamped < minRPM) clamped = minRPM;
    if (clamped > maxRPM) clamped = maxRPM;

    char targetKey[16];
    snprintf(targetKey, sizeof(targetKey), "F%dTg", fanIndex);
    writeFanTargetRPM(targetKey, clamped);

    g_manualEngaged = 1;
    g_lastHeartbeat = time(NULL);
    pthread_mutex_unlock(&g_smcMutex);
    return 1;
}

static float getPeakTemperature(void) {
    // ThermalForge safety sensor keys
    static const char* tempKeys[] = {
        "TCDX", "TCHP", "TCMb",
        "Tp01", "Tp02", "Tp03", "Tp04", "Tp05", "Tp06", "Tp07", "Tp08",
        "Tp09", "Tp0A", "Tp0B", "Tp0C", "Tp0D", "Tp0W", "Tp0X", "Tp0b",
        "Tg05", "Tg0D", "Tg0L", "Tg0j", "TG0B", "TG0H", "TG0V"
    };
    int numKeys = sizeof(tempKeys) / sizeof(tempKeys[0]);
    float peak = 0.0f;
    for (int i = 0; i < numKeys; i++) {
        float t = readFloatKey(tempKeys[i]);
        if (t > 0.0f && t < 125.0f && t > peak) {
            peak = t;
        }
    }
    return peak;
}

// ThermalForge Heartbeat Watchdog & Safety Floor thread
static void* watchdogThread(void* arg) {
    (void)arg;
    while (g_running) {
        sleep(2);
        if (!g_running) break;

        // 1. Safety floor: if temperature > 95°C, force max fans immediately
        float peakTemp = getPeakTemperature();
        if (peakTemp >= SAFETY_OVERRIDE_TEMP) {
            setFanMax();
            continue;
        }

        // 2. Heartbeat watchdog: if manual hold has expired, revert to auto
        if (g_manualEngaged) {
            time_t now = time(NULL);
            if (difftime(now, g_lastHeartbeat) > HEARTBEAT_TIMEOUT_SEC) {
                resetAuto();
            }
        }
    }
    return NULL;
}

static void sigHandler(int sig) {
    (void)sig;
    g_running = 0;
}

int main(int argc, char** argv) {
    if (argc > 1 && (strcmp(argv[1], "version") == 0 || strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-v") == 0)) {
        printf("%s\n", DAEMON_VERSION);
        return 0;
    }

    // CRITICAL: Ignore SIGPIPE so writing to disconnected client never terminates the daemon
    signal(SIGPIPE, SIG_IGN);
    signal(SIGTERM, sigHandler);
    signal(SIGINT, sigHandler);

    initHardware();

    pthread_t wdThread;
    pthread_create(&wdThread, NULL, watchdogThread, NULL);

    unlink(SOCKET_PATH);
    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) return 1;

    // Do not generate SIGPIPE on this socket
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_NOSIGPIPE, &opt, sizeof(opt));

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCKET_PATH, sizeof(addr.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(server_fd);
        return 1;
    }

    chmod(SOCKET_PATH, 0666);
    listen(server_fd, 16);

    while (g_running) {
        int client_fd = accept(server_fd, NULL, NULL);
        if (client_fd < 0) {
            if (!g_running) break;
            continue;
        }

        setsockopt(client_fd, SOL_SOCKET, SO_NOSIGPIPE, &opt, sizeof(opt));

        char buf[256];
        ssize_t n = read(client_fd, buf, sizeof(buf) - 1);
        if (n > 0) {
            buf[n] = '\0';
            // Trim trailing newline or whitespace
            while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r' || buf[n - 1] == ' ')) {
                buf[--n] = '\0';
            }

            if (strcmp(buf, "auto") == 0) {
                resetAuto();
                write(client_fd, "OK\n", 3);
            } else if (strcmp(buf, "max") == 0) {
                setFanMax();
                write(client_fd, "OK\n", 3);
            } else if (strncmp(buf, "set ", 4) == 0) {
                float rpm = (float)atof(buf + 4);
                if (rpm > 0.0f) {
                    setFanRPM(rpm);
                }
                write(client_fd, "OK\n", 3);
            } else if (strncmp(buf, "setfan ", 7) == 0) {
                int fanIdx = 0;
                float rpm = 0.0f;
                if (sscanf(buf + 7, "%d %f", &fanIdx, &rpm) == 2 && rpm > 0.0f) {
                    setSingleFanRPM(fanIdx, rpm);
                }
                write(client_fd, "OK\n", 3);
            } else if (strcmp(buf, "heartbeat") == 0) {
                g_lastHeartbeat = time(NULL);
                write(client_fd, "OK\n", 3);
            } else if (strcmp(buf, "version") == 0) {
                write(client_fd, DAEMON_VERSION "\n", strlen(DAEMON_VERSION) + 1);
            } else if (strncmp(buf, "upgrade ", 8) == 0) {
                const char* srcPath = buf + 8;
                struct stat st;
                if (stat(srcPath, &st) == 0 && S_ISREG(st.st_mode)) {
                    char cmd[1024];
                    snprintf(cmd, sizeof(cmd), "cp -f \"%s\" /Library/PrivilegedHelperTools/notchpulse-fanhelper && chmod 755 /Library/PrivilegedHelperTools/notchpulse-fanhelper && chown root:wheel /Library/PrivilegedHelperTools/notchpulse-fanhelper", srcPath);
                    int ret = system(cmd);
                    if (ret == 0) {
                        write(client_fd, "OK\n", 3);
                        close(client_fd);
                        close(server_fd);
                        unlink(SOCKET_PATH);
                        exit(0); // launchd KeepAlive restarts with the updated binary
                    } else {
                        write(client_fd, "ERR\n", 4);
                    }
                } else {
                    write(client_fd, "ERR\n", 4);
                }
            } else if (strcmp(buf, "ping") == 0) {
                write(client_fd, "PONG\n", 5);
            } else if (strcmp(buf, "status") == 0) {
                int count = getFanCount();
                float peakT = getPeakTemperature();
                char reply[512];
                int offset = snprintf(reply, sizeof(reply), "{\"fans\":[");
                for (int i = 0; i < count; i++) {
                    char acKey[16], tgKey[16], mnKey[16], mxKey[16], mdKey[16];
                    snprintf(acKey, sizeof(acKey), "F%dAc", i);
                    snprintf(tgKey, sizeof(tgKey), "F%dTg", i);
                    snprintf(mnKey, sizeof(mnKey), "F%dMn", i);
                    snprintf(mxKey, sizeof(mxKey), "F%dMx", i);
                    snprintf(mdKey, sizeof(mdKey), g_modeKeyTemplate, i);

                    float actual = readFloatKey(acKey);
                    float target = readFloatKey(tgKey);
                    float minRPM = readFloatKey(mnKey);
                    float maxRPM = readFloatKey(mxKey);

                    uint8_t mdBytes[8];
                    uint32_t mdSz = 0;
                    int isMan = 0;
                    if (smcReadKey(mdKey, mdBytes, &mdSz) && mdSz >= 1) {
                        isMan = (mdBytes[0] == 1);
                    }

                    offset += snprintf(reply + offset, sizeof(reply) - offset,
                        "%s{\"index\":%d,\"actual\":%d,\"target\":%d,\"min\":%d,\"max\":%d,\"manual\":%d}",
                        (i > 0 ? "," : ""), i, (int)actual, (int)target, (int)minRPM, (int)maxRPM, isMan);
                }
                snprintf(reply + offset, sizeof(reply) - offset, "],\"temp\":%.1f,\"manual_engaged\":%d}\n", peakT, g_manualEngaged);
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
