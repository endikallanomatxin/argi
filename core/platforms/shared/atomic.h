#ifndef ARGI_ATOMIC_H
#define ARGI_ATOMIC_H
#include <stdint.h>
uintptr_t _argi_atomic_u32_create(uint32_t initial);
void _argi_atomic_u32_destroy(uintptr_t handle);
uint32_t _argi_atomic_u32_load(uintptr_t handle);
void _argi_atomic_u32_store(uintptr_t handle, uint32_t value);
uint32_t _argi_atomic_u32_exchange(uintptr_t handle, uint32_t value);
uint32_t _argi_atomic_u32_fetch_add(uintptr_t handle, uint32_t value);
uint64_t _argi_atomic_u32_compare_exchange(uintptr_t handle, uint32_t expected, uint32_t desired);
#endif
