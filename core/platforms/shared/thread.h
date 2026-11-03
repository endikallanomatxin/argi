#ifndef ARGI_THREAD_H
#define ARGI_THREAD_H
#include <stdint.h>

typedef void (*argi_thread_start)(void *context);

/* The handle has one owner; operations on it must not run concurrently.
   The callback context must stay live until a successful join. Join retains
   the handle on failure. Destroy never joins or detaches and succeeds only
   after a successful join. */
uintptr_t _argi_thread_create(argi_thread_start start, void *context);
int32_t _argi_thread_join(uintptr_t handle);
int32_t _argi_thread_destroy(uintptr_t handle);
#endif
