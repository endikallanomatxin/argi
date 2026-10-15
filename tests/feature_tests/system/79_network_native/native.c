#include "../../../../core/platforms/shared/network.h"
#include <stdlib.h>
#include <string.h>

static int probe_family(int family) {
    const char *host = family == 1 ? "127.0.0.1" : "::1";
    uintptr_t addresses = 0, listener = 0, client = 0, server = 0, udp = 0;
    struct argi_net_address address, bound, peer;
    int result = 0;
    uint8_t *large = NULL;
    if (_argi_network_resolve((const uint8_t *)host, strlen(host), 0, family, 0, 1, &addresses))
        return family == 2 ? 0 : 1;
    if (!_argi_network_address_count(addresses) || _argi_network_address_get(addresses, 0, &address)) { result = 2; goto done; }
    _argi_network_addresses_free(addresses);
    addresses = 0;
    if (_argi_network_socket(&address, 1, &listener)) { result = family == 2 ? 0 : 3; goto done; }
    if (_argi_network_local_address(listener, &bound) || !_argi_network_port(&bound)) { result = 4; goto done; }
    if (_argi_network_socket(&bound, 0, &client) || _argi_network_accept(listener, &server)) { result = 5; goto done; }
    if (_argi_network_close(listener)) { listener = 0; result = 6; goto done; }
    listener = 0;
    if (_argi_network_timeout(server, 5000)) { result = 7; goto done; }
    const uint8_t bytes[3] = { 65, 0, 66 };
    uint8_t output[3] = { 0 };
    uintptr_t written = 0, received = 0, count = 0;
    while (written < sizeof(bytes)) {
        if (_argi_network_send(client, bytes + written, sizeof(bytes) - written, NULL, &count) || !count) { result = 8; goto done; }
        written += count;
    }
    if (_argi_network_shutdown_write(client)) { result = 9; goto done; }
    while (received < sizeof(output)) {
        if (_argi_network_receive(server, output + received, sizeof(output) - received, &peer, &count) || !count) { result = 10; goto done; }
        received += count;
    }
    if (memcmp(bytes, output, sizeof(bytes)) || _argi_network_receive(server, output, sizeof(output), &peer, &count) || count) { result = 11; goto done; }
    if (_argi_network_socket(&address, 2, &udp) || _argi_network_local_address(udp, &bound) || _argi_network_timeout(udp, 5000)) { result = 12; goto done; }
    large = calloc(65508, 1);
    if (!large) { result = 13; goto done; }
    if (_argi_network_send(udp, large, 65508, &bound, &count) != -2 || count) { result = 14; goto done; }
    if (_argi_network_send(udp, bytes, sizeof(bytes), &bound, &count) || count != sizeof(bytes)) { result = 15; goto done; }
    if (_argi_network_receive(udp, output, 1, &peer, &count) != -2 || count) { result = 16; goto done; }
    if (_argi_network_send(udp, bytes, 0, &bound, &count) || count) { result = 17; goto done; }
    if (_argi_network_receive(udp, output, sizeof(output), &peer, &count) || count) { result = 18; goto done; }
    if (_argi_network_port(&peer) != _argi_network_port(&bound)) { result = 19; goto done; }
done:
    free(large);
    _argi_network_addresses_free(addresses);
    _argi_network_close(listener);
    _argi_network_close(client);
    _argi_network_close(server);
    _argi_network_close(udp);
    return result;
}
int32_t argi_network_probe(void) {
    if (_argi_network_init()) return 20;
    uintptr_t addresses = 99;
    const uint8_t invalid[3] = { 'a', 0, 'b' };
    int result = 0;
    if (_argi_network_resolve(invalid, 3, 0, 1, 0, 0, &addresses) != -2 || addresses) result = 21;
    if (!result) result = probe_family(1);
    if (!result) result = probe_family(2);
    _argi_network_deinit();
    return result;
}
#ifdef ARGI_NETWORK_PROBE_MAIN
int main(void) { return argi_network_probe(); }
#endif
