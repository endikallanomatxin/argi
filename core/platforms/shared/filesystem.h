#ifndef ARGI_FILESYSTEM_H
#define ARGI_FILESYSTEM_H
#include <stdint.h>
/* Private native adapter ABI; all path and entry bytes cross by bounded copy. */
int32_t _argi_fs_mkdir(const uint8_t *, uintptr_t);
int32_t _argi_fs_rmdir(const uint8_t *, uintptr_t);
int32_t _argi_fs_metadata_nofollow(const uint8_t *, uintptr_t, int32_t *, uint64_t *, int64_t *, uint32_t *);
int32_t _argi_fs_metadata(const uint8_t *, uintptr_t, int32_t *, uint64_t *, int64_t *, uint32_t *);
int32_t _argi_fs_directory_open(const uint8_t *, uintptr_t, uintptr_t *);
int32_t _argi_fs_directory_next(uintptr_t, uintptr_t *);
int32_t _argi_fs_directory_copy(uintptr_t, uint8_t *, uintptr_t);
void _argi_fs_directory_close(uintptr_t);
int32_t _argi_fs_seek(uintptr_t, int64_t, int32_t, uint64_t *);
int32_t _argi_fs_truncate(uintptr_t, uint64_t);
int32_t _argi_fs_temp_create(const uint8_t *, uintptr_t, const uint8_t *, uintptr_t, uintptr_t *);
uintptr_t _argi_fs_temp_length(uintptr_t);
int32_t _argi_fs_temp_copy(uintptr_t, uint8_t *, uintptr_t);
int32_t _argi_fs_temp_close(uintptr_t);
void _argi_fs_temp_cleanup(uintptr_t);
#endif
