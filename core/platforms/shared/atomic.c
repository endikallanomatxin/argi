/* The allocation has a stable native address while its Argi owner moves.
   Handles never expose this storage as ordinary Argi references. */
#include <stdatomic.h>
#include <stdlib.h>
#include "atomic.h"
struct argi_atomic_u32 { _Atomic(uint32_t) value; };
uintptr_t _argi_atomic_u32_create(uint32_t initial) {
    struct argi_atomic_u32 *cell = malloc(sizeof(*cell));
    if (!cell) return 0;
    atomic_init(&cell->value, initial);
    return (uintptr_t)cell;
}
void _argi_atomic_u32_destroy(uintptr_t handle) { free((void *)handle); }
uint32_t _argi_atomic_u32_load(uintptr_t handle) {
    return atomic_load_explicit(&((struct argi_atomic_u32 *)handle)->value, memory_order_seq_cst);
}
void _argi_atomic_u32_store(uintptr_t handle, uint32_t value) {
    atomic_store_explicit(&((struct argi_atomic_u32 *)handle)->value, value, memory_order_seq_cst);
}
uint32_t _argi_atomic_u32_exchange(uintptr_t handle, uint32_t value) {
    return atomic_exchange_explicit(&((struct argi_atomic_u32 *)handle)->value, value, memory_order_seq_cst);
}
uint32_t _argi_atomic_u32_fetch_add(uintptr_t handle, uint32_t value) {
    return atomic_fetch_add_explicit(&((struct argi_atomic_u32 *)handle)->value, value, memory_order_seq_cst);
}
uint64_t _argi_atomic_u32_compare_exchange(uintptr_t handle, uint32_t expected, uint32_t desired) {
    uint32_t observed = expected;
    int swapped = atomic_compare_exchange_strong_explicit(
        &((struct argi_atomic_u32 *)handle)->value, &observed, desired,
        memory_order_seq_cst, memory_order_seq_cst);
    return (uint64_t)observed | ((uint64_t)(swapped != 0) << 32);
}
