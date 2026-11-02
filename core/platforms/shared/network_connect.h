#ifndef ARGI_NETWORK_CONNECT_H
#define ARGI_NETWORK_CONNECT_H

#include <errno.h>
#include <poll.h>
#include <sys/socket.h>

/* Private POSIX connection completion; the caller still owns the descriptor. */
static int argi_net_connect(int descriptor, const struct sockaddr *address, socklen_t length) {
    if (connect(descriptor, address, length) == 0) return 0;
    if (errno != EINTR) return -1;

    /* POSIX leaves an interrupted connection in progress. Wait for its result
       instead of issuing another connect against the same socket. */
    struct pollfd pending = { descriptor, POLLOUT, 0 };
    int ready;
    do { ready = poll(&pending, 1, -1); } while (ready < 0 && errno == EINTR);
    if (ready <= 0 || (pending.revents & POLLNVAL)) return -1;

    int error = 0;
    socklen_t size = sizeof(error);
    if (getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &size)) return -1;
    if (error) { errno = error; return -1; }
    return 0;
}

#endif
