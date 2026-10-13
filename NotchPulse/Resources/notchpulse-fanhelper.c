//
//  notchpulse-fanhelper.c
//  NotchPulse
//
//  Lightweight, standalone privileged daemon for Apple Silicon and Intel fan control.
//  Zero-dependency, native IOKit C binary. Runs as root via launchd.
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
    uint32_t key;
    uint8_t vers[6];
    uint16_t _pad0;
    uint8_t pLimitData[16];
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
    uint8_t _pad1[3];
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint8_t _pad2;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParamStruct;
#pragma pack(pop)

static uint32_t fourCC(const char* s) {
    uint32_t ans = 0;
    for (int i = 0; i < 4; i++) ans = (ans << 8) | (uint8_t)s[i];
    return ans;
}

static io_connect_t g_conn = 0;

static int smcOpen(void) {
    if (g_conn != 0) return 1;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    kern_return_t kr = IOServiceOpen(service, mach_task_self_, 0, &g_conn);
    IOObjectRelease(service);
    return (kr == 0 && g_conn != 0);
}

static int smcWrite(const char* key, const void* data, uint32_t size) {
    if (!smcOpen()) return 0;
    SMCParamStruct in, out;
    size_t inSize = sizeof(SMCParamStruct), outSize = sizeof(SMCParamStruct);
    memset(&in, 0, sizeof(in));
    in.key = fourCC(key);
    in.dataSize = size;
    in.data8 = 6;
    memcpy(in.bytes, data, size);
    kern_return_t kr = IOConnectCallStructMethod(g_conn, 2, &in, inSize, &out, &outSize);
    return (kr == 0 && out.result == 0);
}

static void unlockFans(void) {
    uint8_t one = 1;
    smcWrite("Ftst", &one, 1);
    usleep(250000); // 250ms
    smcWrite("F0Md", &one, 1);
    smcWrite("F1Md", &one, 1);
    smcWrite("F0md", &one, 1);
    smcWrite("F1md", &one, 1);
}

static void setFanRPM(float rpm) {
    unlockFans();
    smcWrite("F0Tg", &rpm, 4);
    smcWrite("F1Tg", &rpm, 4);
}

static void resetAuto(void) {
    uint8_t zero = 0;
    float zeroF = 0.0f;
    uint16_t zero16 = 0;
    smcWrite("F0Md", &zero, 1);
    smcWrite("F1Md", &zero, 1);
    smcWrite("F0md", &zero, 1);
    smcWrite("F1md", &zero, 1);
    smcWrite("F0Tg", &zeroF, 4);
    smcWrite("F1Tg", &zeroF, 4);
    smcWrite("Ftst", &zero, 1);
    smcWrite("FS! ", &zero16, 2);
}

static volatile int g_running = 1;
static void sigHandler(int sig) {
    (void)sig;
    g_running = 0;
}

int main(int argc, char** argv) {
    (void)argc; (void)argv;
    signal(SIGTERM, sigHandler);
    signal(SIGINT, sigHandler);

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
    listen(server_fd, 5);

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
                if (rpm > 0) {
                    setFanRPM(rpm);
                }
                write(client_fd, "OK\n", 3);
            } else if (strncmp(buf, "ping", 4) == 0) {
                write(client_fd, "PONG\n", 5);
            }
        }
        close(client_fd);
    }

    resetAuto();
    unlink(SOCKET_PATH);
    close(server_fd);
    if (g_conn != 0) {
        IOServiceClose(g_conn);
    }
    return 0;
}
