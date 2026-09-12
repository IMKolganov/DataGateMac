//
//  CrashSignalHook.c
//  DataGateMac
//
//  Async-signal-safe stub next to Windows MiniDumpWriteDump: write a tiny
//  pending_signal.txt, then re-raise so Apple's crash reporter still runs.
//

#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

static char g_path[1024];
static volatile sig_atomic_t g_handling;

static void datagate_write_literal(int fd, const char *s) {
    if (fd < 0 || s == NULL) {
        return;
    }
    size_t n = strlen(s);
    (void)write(fd, s, n);
}

static void datagate_write_int(int fd, int value) {
    char tmp[16];
    char buf[16];
    int t = 0;
    int i = 0;
    int v = value;

    if (v < 0) {
        datagate_write_literal(fd, "-");
        v = -v;
    }
    if (v == 0) {
        datagate_write_literal(fd, "0");
        return;
    }
    while (v > 0 && t < (int)sizeof(tmp)) {
        tmp[t++] = (char)('0' + (v % 10));
        v /= 10;
    }
    while (t > 0) {
        buf[i++] = tmp[--t];
    }
    (void)write(fd, buf, (size_t)i);
}

static void datagate_crash_signal(int sig) {
    if (g_handling) {
        signal(sig, SIG_DFL);
        raise(sig);
        return;
    }
    g_handling = 1;

    if (g_path[0] != '\0') {
        int fd = open(g_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
        if (fd >= 0) {
            datagate_write_literal(fd, "kind=fatal\n");
            datagate_write_literal(fd, "process=imkolganov.DataGateMac\n");
            datagate_write_literal(fd, "signal=");
            datagate_write_int(fd, sig);
            datagate_write_literal(fd, "\n");
            const char *name = NULL;
            switch (sig) {
                case SIGSEGV: name = "SIGSEGV"; break;
                case SIGBUS: name = "SIGBUS"; break;
                case SIGILL: name = "SIGILL"; break;
                case SIGFPE: name = "SIGFPE"; break;
                case SIGABRT: name = "SIGABRT"; break;
                case SIGTRAP: name = "SIGTRAP"; break;
                default: break;
            }
            if (name != NULL) {
                datagate_write_literal(fd, "signal_name=");
                datagate_write_literal(fd, name);
                datagate_write_literal(fd, "\n");
            }
            datagate_write_literal(fd, "message=uncaught signal\n");
            (void)close(fd);
        }
    }

    signal(sig, SIG_DFL);
    raise(sig);
}

void DataGateInstallCrashSignalHandler(const char *path) {
    if (path == NULL) {
        return;
    }
    (void)strlcpy(g_path, path, sizeof(g_path));
    signal(SIGSEGV, datagate_crash_signal);
    signal(SIGBUS, datagate_crash_signal);
    signal(SIGILL, datagate_crash_signal);
    signal(SIGFPE, datagate_crash_signal);
    signal(SIGABRT, datagate_crash_signal);
    signal(SIGTRAP, datagate_crash_signal);
}
