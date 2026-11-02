/* Deterministic syscall outcomes exercise the private POSIX completion policy.
   No real connection, signal timing, or production injection hook is needed. */
#ifndef _WIN32
#include <errno.h>
#include <poll.h>
#include <sys/socket.h>

static struct { int mode, connects, polls, checks; } connect_probe;

static int probe_connect(int descriptor, const struct sockaddr *address, socklen_t length) {
    (void)descriptor; (void)address; (void)length;
    connect_probe.connects++;
    if (!connect_probe.mode) return 0;
    errno = connect_probe.connects == 1 ? EINTR : EALREADY;
    return -1;
}
static int probe_poll(struct pollfd *fds, nfds_t count, int timeout) {
    connect_probe.polls++;
    if (count != 1 || fds[0].fd != 42 || fds[0].events != POLLOUT || timeout != -1) {
        errno = EINVAL;
        return -1;
    }
    if (connect_probe.mode == 3) { errno = EINVAL; return -1; }
    if (connect_probe.polls <= 2) { errno = EINTR; return -1; }
    fds[0].revents = connect_probe.mode == 2 ? POLLERR : POLLOUT;
    return 1;
}
static int probe_getsockopt(int descriptor, int level, int option, void *value, socklen_t *length) {
    connect_probe.checks++;
    if (descriptor != 42 || level != SOL_SOCKET || option != SO_ERROR || *length != sizeof(int)) {
        errno = EINVAL;
        return -1;
    }
    *(int *)value = connect_probe.mode == 2 ? ECONNREFUSED : 0;
    return 0;
}

#define connect probe_connect
#define poll probe_poll
#define getsockopt probe_getsockopt
#include "../../../../core/platforms/shared/network_connect.h"
#undef connect
#undef poll
#undef getsockopt

static int probe_connect_interrupts(void) {
    for (int mode = 0; mode != 4; mode++) {
        memset(&connect_probe, 0, sizeof(connect_probe));
        connect_probe.mode = mode;
        int status = argi_net_connect(42, NULL, 0);
        if (mode < 2 && status != 0) return 22;
        if (mode >= 2 && status == 0) return 23;
        if (connect_probe.connects != 1) return 24;
        if (connect_probe.polls != (mode == 0 ? 0 : mode == 3 ? 1 : 3)) return 25;
        if (connect_probe.checks != (mode == 1 || mode == 2 ? 1 : 0)) return 26;
        if (mode == 2 && errno != ECONNREFUSED) return 27;
    }
    return 0;
}
#endif
