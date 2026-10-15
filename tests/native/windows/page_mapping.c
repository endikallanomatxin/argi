#include <windows.h>
#include <malloc.h>
#include <stdint.h>
#include <assert.h>

uintptr_t _argi_page_size(void);
uintptr_t _argi_page_acquire(uintptr_t length, uintptr_t alignment);
int32_t _argi_page_release(uintptr_t address, uintptr_t length);
void *_argi_aligned_alloc(uintptr_t alignment, uintptr_t size);

int main(void) {
    uintptr_t page = _argi_page_size();
    assert(page != 0);
    const uintptr_t alignments[] = {1, page, page * 4, page * 32};
    for (unsigned i = 0; i < sizeof(alignments) / sizeof(alignments[0]); ++i) {
        uintptr_t address = _argi_page_acquire(page + 1, alignments[i]);
        assert(address != UINTPTR_MAX);
        assert(address % alignments[i] == 0 && address % page == 0);
        ((unsigned char *)address)[0] = 1;
        ((unsigned char *)address)[page] = 2;
        MEMORY_BASIC_INFORMATION info;
        assert(VirtualQuery((void *)address, &info, sizeof(info)) != 0);
        void *reservation = info.AllocationBase;
        assert(_argi_page_release(address, page + 1) == 0);
        assert(VirtualQuery(reservation, &info, sizeof(info)) != 0);
        assert(info.State == MEM_FREE);
    }
    assert(_argi_page_acquire(1, 0) == UINTPTR_MAX);
    assert(_argi_page_acquire(1, 3) == UINTPTR_MAX);
    assert(_argi_page_acquire(UINTPTR_MAX, page) == UINTPTR_MAX);
    void *heap = _argi_aligned_alloc(64, 64);
    assert(heap && (uintptr_t)heap % 64 == 0);
    _aligned_free(heap);
    return 0;
}
