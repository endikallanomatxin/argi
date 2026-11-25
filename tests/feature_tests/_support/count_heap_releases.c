#include <stdint.h>
#include <stdatomic.h>
#include <stdlib.h>

#ifndef EXPECTED_RELEASES
#define EXPECTED_RELEASES 1
#endif

static _Atomic unsigned releases;

void __real__argi_c_aligned_release(uintptr_t address);

void __wrap__argi_c_aligned_release(uintptr_t address) {
    if (++releases > EXPECTED_RELEASES) abort();
    __real__argi_c_aligned_release(address);
}

static void __attribute__((destructor)) require_expected_releases(void) {
    if (releases != EXPECTED_RELEASES) abort();
}
