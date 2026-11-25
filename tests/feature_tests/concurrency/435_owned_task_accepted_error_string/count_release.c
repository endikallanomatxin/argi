#include <stdint.h>
#include <stdlib.h>

static unsigned releases;

void __real__argi_c_aligned_release(uintptr_t address);

void __wrap__argi_c_aligned_release(uintptr_t address) {
    if (++releases != 1) abort();
    __real__argi_c_aligned_release(address);
}

static void __attribute__((destructor)) require_one_release(void) {
    if (releases != 1) abort();
}
