/* Addresses and OS descriptors remain private native state. Each exported
   operation copies bounded bytes and returns no reference to native storage. */
#ifndef _WIN32
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#include <sys/socket.h>
#include <sys/time.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
typedef int argi_socket;
#define ARGI_INVALID_SOCKET (-1)
#define argi_close_socket close
#else
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET argi_socket;
#define ARGI_INVALID_SOCKET INVALID_SOCKET
#define argi_close_socket closesocket
#endif
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>

#include "network.h"
struct argi_net_socket { argi_socket descriptor; int datagram; };
struct argi_net_addresses { struct addrinfo *first; uintptr_t count; };
_Static_assert(sizeof(struct sockaddr_storage) <= 128, "socket address exceeds bounded storage");

int32_t _argi_network_init(void) {
#ifdef _WIN32
    WSADATA data;
    return WSAStartup(MAKEWORD(2, 2), &data) ? -1 : 0;
#else
    return 0;
#endif
}
void _argi_network_deinit(void) {
#ifdef _WIN32
    WSACleanup();
#endif
}
static int argi_net_interrupted(void) {
#ifdef _WIN32
    return WSAGetLastError() == WSAEINTR;
#else
    return errno == EINTR;
#endif
}
static int argi_net_address_copy(struct argi_net_address *out, const struct sockaddr *address, size_t size) {
    if (!out || !address || size > sizeof(out->bytes)) return -1;
    memset(out, 0, sizeof(*out));
    memcpy(out->bytes, address, size);
    out->length = (uint32_t)size;
    return 0;
}
static int argi_net_address_load(const struct argi_net_address *address, struct sockaddr_storage *out) {
    if (!address || address->length > sizeof(*out) || address->length < sizeof(struct sockaddr)) return -1;
    memset(out, 0, sizeof(*out));
    memcpy(out, address->bytes, address->length);
    if (out->ss_family == AF_INET && address->length == sizeof(struct sockaddr_in)) return 0;
    if (out->ss_family == AF_INET6 && address->length == sizeof(struct sockaddr_in6)) return 0;
    return -1;
}
int32_t _argi_network_resolve(const uint8_t *host, uintptr_t length, uint16_t port,
                             int32_t family, int32_t datagram, int32_t passive,
                             uintptr_t *handle) {
    *handle = 0;
    if (length > 253 || (length && (!host || memchr(host, 0, length))) || family < 0 || family > 2) return -2;
    char name[254], service[6];
    if (length) memcpy(name, host, length);
    name[length] = 0;
    snprintf(service, sizeof(service), "%u", (unsigned)port);
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = family == 1 ? AF_INET : family == 2 ? AF_INET6 : AF_UNSPEC;
    hints.ai_socktype = datagram ? SOCK_DGRAM : SOCK_STREAM;
    hints.ai_protocol = datagram ? IPPROTO_UDP : IPPROTO_TCP;
    hints.ai_flags = AI_NUMERICSERV | (passive ? AI_PASSIVE : 0);
    struct argi_net_addresses *addresses = calloc(1, sizeof(*addresses));
    if (!addresses) return -3;
    int status = getaddrinfo(length ? name : NULL, service, &hints, &addresses->first);
    if (status) { free(addresses); return status == EAI_MEMORY ? -3 : -1; }
    for (struct addrinfo *item = addresses->first; item; item = item->ai_next)
        if ((item->ai_family == AF_INET || item->ai_family == AF_INET6) && item->ai_addrlen <= 128) addresses->count++;
    if (!addresses->count) { freeaddrinfo(addresses->first); free(addresses); return -1; }
    *handle = (uintptr_t)addresses;
    return 0;
}
uintptr_t _argi_network_address_count(uintptr_t handle) {
    return handle ? ((struct argi_net_addresses *)handle)->count : 0;
}
int32_t _argi_network_address_get(uintptr_t handle, uintptr_t index, struct argi_net_address *out) {
    if (!handle) return -1;
    for (struct addrinfo *item = ((struct argi_net_addresses *)handle)->first; item; item = item->ai_next) {
        if ((item->ai_family != AF_INET && item->ai_family != AF_INET6) || item->ai_addrlen > 128) continue;
        if (!index--) return argi_net_address_copy(out, item->ai_addr, item->ai_addrlen);
    }
    return -1;
}
void _argi_network_addresses_free(uintptr_t handle) {
    if (!handle) return;
    struct argi_net_addresses *addresses = (struct argi_net_addresses *)handle;
    freeaddrinfo(addresses->first);
    free(addresses);
}
static int argi_net_prepare(argi_socket socket) {
#ifdef _WIN32
    return SetHandleInformation((HANDLE)socket, HANDLE_FLAG_INHERIT, 0) ? 0 : -1;
#else
    if (fcntl(socket, F_SETFD, FD_CLOEXEC)) return -1;
#ifdef SO_NOSIGPIPE
    int enabled = 1;
    if (setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled))) return -1;
#endif
    return 0;
#endif
}
int32_t _argi_network_socket(const struct argi_net_address *address, int32_t operation, uintptr_t *handle) {
    *handle = 0;
    struct sockaddr_storage native;
    if (argi_net_address_load(address, &native) || operation < 0 || operation > 2) return -1;
    struct argi_net_socket *owner = calloc(1, sizeof(*owner));
    if (!owner) return -3;
    owner->datagram = operation == 2;
    owner->descriptor = socket(native.ss_family, owner->datagram ? SOCK_DGRAM : SOCK_STREAM, 0);
    if (owner->descriptor == ARGI_INVALID_SOCKET) { free(owner); return -1; }
    if (argi_net_prepare(owner->descriptor)) goto failed;
    if (operation == 0) {
        int status;
        do { status = connect(owner->descriptor, (struct sockaddr *)&native, (int)address->length); }
        while (status && argi_net_interrupted());
        if (status) goto failed;
    } else {
        if (bind(owner->descriptor, (struct sockaddr *)&native, (int)address->length)) goto failed;
        if (operation == 1 && listen(owner->descriptor, 16)) goto failed;
    }
    *handle = (uintptr_t)owner;
    return 0;
failed:
    argi_close_socket(owner->descriptor);
    free(owner);
    return -1;
}
int32_t _argi_network_accept(uintptr_t handle, uintptr_t *accepted) {
    *accepted = 0;
    if (!handle) return -1;
    struct argi_net_socket *owner = calloc(1, sizeof(*owner));
    if (!owner) return -3;
    do { owner->descriptor = accept(((struct argi_net_socket *)handle)->descriptor, NULL, NULL); }
    while (owner->descriptor == ARGI_INVALID_SOCKET && argi_net_interrupted());
    if (owner->descriptor == ARGI_INVALID_SOCKET) { free(owner); return -1; }
    if (argi_net_prepare(owner->descriptor)) { argi_close_socket(owner->descriptor); free(owner); return -1; }
    *accepted = (uintptr_t)owner;
    return 0;
}
int32_t _argi_network_local_address(uintptr_t handle, struct argi_net_address *out) {
    if (!handle) return -1;
    struct sockaddr_storage address;
#ifdef _WIN32
    int size = sizeof(address);
#else
    socklen_t size = sizeof(address);
#endif
    if (getsockname(((struct argi_net_socket *)handle)->descriptor, (struct sockaddr *)&address, &size)) return -1;
    return argi_net_address_copy(out, (struct sockaddr *)&address, size);
}
uint16_t _argi_network_port(const struct argi_net_address *address) {
    struct sockaddr_storage native;
    if (argi_net_address_load(address, &native)) return 0;
    return ntohs(native.ss_family == AF_INET ? ((struct sockaddr_in *)&native)->sin_port : ((struct sockaddr_in6 *)&native)->sin6_port);
}
int32_t _argi_network_close(uintptr_t handle) {
    if (!handle) return 0;
    struct argi_net_socket *owner = (struct argi_net_socket *)handle;
    /* Never retry close: an interrupted POSIX close may already release the
       descriptor, and another operation could reuse its numeric identity. */
    int status = argi_close_socket(owner->descriptor);
    free(owner);
    return status ? -1 : 0;
}
int32_t _argi_network_timeout(uintptr_t handle, uint32_t milliseconds) {
    if (!handle) return -1;
#ifdef _WIN32
    DWORD timeout = milliseconds;
#else
    struct timeval timeout = { milliseconds / 1000, (milliseconds % 1000) * 1000 };
#endif
    argi_socket socket = ((struct argi_net_socket *)handle)->descriptor;
    if (setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, (const char *)&timeout, sizeof(timeout))) return -1;
    return setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, (const char *)&timeout, sizeof(timeout)) ? -1 : 0;
}
int32_t _argi_network_send(uintptr_t handle, const uint8_t *bytes, uintptr_t length,
                          const struct argi_net_address *peer, uintptr_t *sent) {
    *sent = 0;
    if (!handle || (length && !bytes)) return -1;
    struct argi_net_socket *owner = (struct argi_net_socket *)handle;
    if (owner->datagram && (length > 65507 || !peer)) return -2;
    int count = length > INT_MAX ? INT_MAX : (int)length;
    int flags = 0;
#ifdef MSG_NOSIGNAL
    flags = MSG_NOSIGNAL;
#endif
    struct sockaddr_storage address;
    if (peer && argi_net_address_load(peer, &address)) return -1;
#ifdef _WIN32
    int status;
#else
    ssize_t status;
#endif
    do {
        status = peer ? sendto(owner->descriptor, (const char *)bytes, count, flags, (struct sockaddr *)&address, (int)peer->length)
                      : send(owner->descriptor, (const char *)bytes, count, flags);
    } while (status < 0 && argi_net_interrupted());
    if (status < 0) return -1;
    *sent = (uintptr_t)status;
    return 0;
}
int32_t _argi_network_receive(uintptr_t handle, uint8_t *bytes, uintptr_t capacity,
                             struct argi_net_address *peer, uintptr_t *received) {
    *received = 0;
    if (!handle || (capacity && !bytes)) return -1;
    struct argi_net_socket *owner = (struct argi_net_socket *)handle;
    int count = capacity > INT_MAX ? INT_MAX : (int)capacity;
    if (owner->datagram) {
        struct sockaddr_storage address;
#ifdef _WIN32
        int size = sizeof(address), status;
        do { status = recvfrom(owner->descriptor, (char *)bytes, count, 0, (struct sockaddr *)&address, &size); }
        while (status < 0 && argi_net_interrupted());
        if (status < 0) return WSAGetLastError() == WSAEMSGSIZE ? -2 : -1;
#else
        struct iovec buffer = { bytes, (size_t)count };
        struct msghdr message;
        memset(&message, 0, sizeof(message));
        message.msg_name = &address;
        message.msg_namelen = sizeof(address);
        message.msg_iov = &buffer;
        message.msg_iovlen = 1;
        ssize_t status;
        do { status = recvmsg(owner->descriptor, &message, 0); } while (status < 0 && argi_net_interrupted());
        if (status < 0) return -1;
        if (message.msg_flags & MSG_TRUNC) return -2;
        socklen_t size = message.msg_namelen;
#endif
        if (argi_net_address_copy(peer, (struct sockaddr *)&address, size)) return -1;
        *received = (uintptr_t)status;
        return 0;
    }
    if (!capacity) return 0;
#ifdef _WIN32
    int status;
#else
    ssize_t status;
#endif
    do { status = recv(owner->descriptor, (char *)bytes, count, 0); } while (status < 0 && argi_net_interrupted());
    if (status < 0) return -1;
    *received = (uintptr_t)status;
    return 0;
}
int32_t _argi_network_shutdown_write(uintptr_t handle) {
    if (!handle) return -1;
#ifdef _WIN32
    return shutdown(((struct argi_net_socket *)handle)->descriptor, SD_SEND) ? -1 : 0;
#else
    return shutdown(((struct argi_net_socket *)handle)->descriptor, SHUT_WR) ? -1 : 0;
#endif
}
