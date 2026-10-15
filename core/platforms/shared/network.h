#ifndef ARGI_NETWORK_H
#define ARGI_NETWORK_H
#include <stdint.h>

/* Private C adapter ABI. Addresses are copied, not pointers into resolver
   storage. The Argi facade does not expose these fields or native handles. */
struct argi_net_address { uint8_t bytes[128]; uint32_t length; };
int32_t _argi_network_init(void);
void _argi_network_deinit(void);
int32_t _argi_network_resolve(const uint8_t *, uintptr_t, uint16_t, int32_t, int32_t, int32_t, uintptr_t *);
uintptr_t _argi_network_address_count(uintptr_t);
int32_t _argi_network_address_get(uintptr_t, uintptr_t, struct argi_net_address *);
void _argi_network_addresses_free(uintptr_t);
int32_t _argi_network_socket(const struct argi_net_address *, int32_t, uintptr_t *);
int32_t _argi_network_accept(uintptr_t, uintptr_t *);
int32_t _argi_network_local_address(uintptr_t, struct argi_net_address *);
uint16_t _argi_network_port(const struct argi_net_address *);
int32_t _argi_network_close(uintptr_t);
int32_t _argi_network_timeout(uintptr_t, uint32_t);
int32_t _argi_network_send(uintptr_t, const uint8_t *, uintptr_t, const struct argi_net_address *, uintptr_t *);
int32_t _argi_network_receive(uintptr_t, uint8_t *, uintptr_t, struct argi_net_address *, uintptr_t *);
int32_t _argi_network_shutdown_write(uintptr_t);
#endif
