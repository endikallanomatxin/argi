#include <windows.h>
#include <malloc.h>
#include <stdint.h>

uintptr_t _argi_page_size(void) {
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return info.dwPageSize;
}

uintptr_t _argi_page_acquire(uintptr_t length, uintptr_t alignment) {
    uintptr_t page_size = _argi_page_size();
    if (!length || !alignment || (alignment & (alignment - 1))) return UINTPTR_MAX;
    if (alignment < page_size) alignment = page_size;
    if (alignment - 1 > UINTPTR_MAX - sizeof(void *)) return UINTPTR_MAX;
    uintptr_t padding = alignment - 1 + sizeof(void *);
    if (length > UINTPTR_MAX - padding) return UINTPTR_MAX;
    void *reservation = VirtualAlloc(NULL, length + padding,
                                    MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (!reservation) return UINTPTR_MAX;
    uintptr_t address = ((uintptr_t)reservation + padding) & ~(alignment - 1);
    // The exposed range is page aligned and excludes this private header. A
    // release uses the original reservation, never a partial VirtualFree.
    ((void **)address)[-1] = reservation;
    return address;
}

int32_t _argi_page_release(uintptr_t address, uintptr_t length) {
    (void)length;
    if (!address || address == UINTPTR_MAX) return -1;
    void *reservation = ((void **)address)[-1];
    return VirtualFree(reservation, 0, MEM_RELEASE) ? 0 : -1;
}

void *_argi_aligned_alloc(uintptr_t alignment, uintptr_t size) {
    return _aligned_malloc(size, alignment);
}
