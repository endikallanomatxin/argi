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

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <wchar.h>
#include <io.h>
#include <fcntl.h>

// Argi paths are UTF-8 regardless of the process ANSI code page. Encoding
// buffers stay within the foreign call and never back a returned reference.
static wchar_t *wide_string(const char *text) {
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
    if (!count) { errno = EILSEQ; return NULL; }
    wchar_t *wide = malloc((size_t)count * sizeof(wchar_t));
    if (!wide) { errno = ENOMEM; return NULL; }
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, wide, count)) {
        free(wide);
        errno = EILSEQ;
        return NULL;
    }
    return wide;
}

FILE *_argi_fopen_utf8(const char *path, const char *mode) {
    wchar_t *wide_path = wide_string(path);
    if (!wide_path) return NULL;
    wchar_t *wide_mode = wide_string(mode);
    if (!wide_mode) { free(wide_path); return NULL; }
    FILE *stream = _wfopen(wide_path, wide_mode);
    free(wide_mode);
    free(wide_path);
    return stream;
}

int32_t _argi_remove_utf8(const char *path) {
    wchar_t *wide = wide_string(path);
    if (!wide) return -1;
    int status = _wremove(wide);
    free(wide);
    return status;
}

int32_t _argi_rename_utf8(const char *old_path, const char *new_path) {
    wchar_t *old_wide = wide_string(old_path);
    if (!old_wide) return -1;
    wchar_t *new_wide = wide_string(new_path);
    if (!new_wide) { free(old_wide); return -1; }
    int status = _wrename(old_wide, new_wide);
    free(new_wide);
    free(old_wide);
    return status;
}

int32_t _argi_access_utf8(const char *path, int32_t mode) {
    wchar_t *wide = wide_string(path);
    if (!wide) return -1;
    int status = _waccess(wide, mode);
    free(wide);
    return status;
}

FILE *_argi_fdopen(int32_t descriptor, const char *mode) {
    FILE *stream = _fdopen(descriptor, mode);
    // Reader/Writer expose bytes: the CRT must not translate LF or Ctrl-Z.
    if (stream && _setmode(descriptor, _O_BINARY) == -1) {
        fclose(stream);
        return NULL;
    }
    return stream;
}
