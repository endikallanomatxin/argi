/* Compile the real adapter under private symbols and deterministic syscall
   outcomes. No production hooks or signal scheduling are involved. */
#ifndef _WIN32
#include <sys/socket.h>
#include <netinet/in.h>
#include <errno.h>

static struct { int mode, calls, invalid; } transfer_probe;
static ssize_t transfer_result(int descriptor, size_t count) {
    transfer_probe.calls++;
    if (descriptor != 42 || count != 3) transfer_probe.invalid = 1;
    if (transfer_probe.calls <= 2) { errno = EINTR; return -1; }
    if (transfer_probe.mode == 1) { errno = EIO; return -1; }
    if (transfer_probe.mode == 2) return 0;
    return 1; /* Partial progress is returned, never retried by the adapter. */
}
static ssize_t transfer_send(int descriptor, const void *bytes, size_t count, int flags) {
    (void)flags;
    if (!bytes || *(const unsigned char *)bytes != 65) transfer_probe.invalid = 1;
    return transfer_result(descriptor, count);
}
static ssize_t transfer_sendto(int descriptor, const void *bytes, size_t count, int flags,
                               const struct sockaddr *peer, socklen_t length) {
    if (!peer || length != sizeof(struct sockaddr_in) || peer->sa_family != AF_INET)
        transfer_probe.invalid = 1;
    return transfer_send(descriptor, bytes, count, flags);
}
static ssize_t transfer_recv(int descriptor, void *bytes, size_t count, int flags) {
    (void)flags;
    ssize_t result = transfer_result(descriptor, count);
    if (result > 0) *(unsigned char *)bytes = 66;
    return result;
}
static ssize_t transfer_recvmsg(int descriptor, struct msghdr *message, int flags) {
    if (message->msg_iovlen != 1 || !message->msg_name) transfer_probe.invalid = 1;
    ssize_t result = transfer_recv(descriptor, message->msg_iov[0].iov_base,
                                   message->msg_iov[0].iov_len, flags);
    if (result >= 0) {
        struct sockaddr_in peer;
        memset(&peer, 0, sizeof(peer));
        peer.sin_family = AF_INET;
        memcpy(message->msg_name, &peer, sizeof(peer));
        message->msg_namelen = sizeof(peer);
        message->msg_flags = transfer_probe.mode == 3 ? MSG_TRUNC : 0;
    }
    return result;
}

#define send transfer_send
#define sendto transfer_sendto
#define recv transfer_recv
#define recvmsg transfer_recvmsg
#define _argi_network_init transfer_network_init
#define _argi_network_deinit transfer_network_deinit
#define _argi_network_resolve transfer_network_resolve
#define _argi_network_address_count transfer_network_address_count
#define _argi_network_address_get transfer_network_address_get
#define _argi_network_addresses_free transfer_network_addresses_free
#define _argi_network_socket transfer_network_socket
#define _argi_network_accept transfer_network_accept
#define _argi_network_local_address transfer_network_local_address
#define _argi_network_port transfer_network_port
#define _argi_network_close transfer_network_close
#define _argi_network_timeout transfer_network_timeout
#define _argi_network_send transfer_network_send
#define _argi_network_receive transfer_network_receive
#define _argi_network_shutdown_write transfer_network_shutdown_write
#include "../../../../core/platforms/shared/network.c"
#undef _argi_network_init
#undef _argi_network_deinit
#undef _argi_network_resolve
#undef _argi_network_address_count
#undef _argi_network_address_get
#undef _argi_network_addresses_free
#undef _argi_network_socket
#undef _argi_network_accept
#undef _argi_network_local_address
#undef _argi_network_port
#undef _argi_network_close
#undef _argi_network_timeout
#undef _argi_network_send
#undef _argi_network_receive
#undef _argi_network_shutdown_write
#undef send
#undef sendto
#undef recv
#undef recvmsg

static int probe_transfer_interrupts(void) {
    struct argi_net_socket owner = { 42, 0 };
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    struct argi_net_address peer;
    if (argi_net_address_copy(&peer, (const struct sockaddr *)&address, sizeof(address))) return 28;
    const uint8_t bytes[3] = { 65, 0, 67 };
    for (int datagram = 0; datagram != 2; datagram++) {
        owner.datagram = datagram;
        for (int mode = 0; mode != 4; mode++) {
            uintptr_t count = 99;
            memset(&transfer_probe, 0, sizeof(transfer_probe));
            transfer_probe.mode = mode;
            int result = transfer_network_send((uintptr_t)&owner, bytes, 3, datagram ? &peer : NULL, &count);
            if (result != (mode == 1 ? -1 : 0) || count != (uintptr_t)(mode == 1 || mode == 2 ? 0 : 1)) return 29;
            if (transfer_probe.calls != 3 || transfer_probe.invalid) return 30;
            uint8_t output[3] = { 99, 99, 99 };
            memset(&transfer_probe, 0, sizeof(transfer_probe));
            transfer_probe.mode = mode;
            count = 99;
            result = transfer_network_receive((uintptr_t)&owner, output, 3, &peer, &count);
            int expected = mode == 1 ? -1 : datagram && mode == 3 ? -2 : 0;
            if (result != expected || count != (uintptr_t)(expected || mode == 2 ? 0 : 1)) return 31;
            if (transfer_probe.calls != 3 || transfer_probe.invalid) return 32;
            if (output[0] != (mode == 1 || mode == 2 ? 99 : 66) || output[1] != 99 || output[2] != 99) return 33;
        }
    }
    return 0;
}
#endif
