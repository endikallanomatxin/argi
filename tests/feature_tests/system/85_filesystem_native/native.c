#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#include <unistd.h>
#endif
#include "../../../../core/platforms/shared/filesystem.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int32_t argi_filesystem_probe(void) {
    uintptr_t temporary = 0, directory = 0, length = 0;
    FILE *file = NULL;
    char *path = NULL, *child = NULL, *link_path = NULL;
    int result = 0, child_exists = 0, link_exists = 0;
    const uint8_t invalid[3] = {'a', 0, 'b'};
    if (_argi_fs_mkdir(invalid, 3) != -2 || _argi_fs_mkdir(invalid, 0) != -2) return 1;
    if (_argi_fs_temp_create((const uint8_t *)".", 1, (const uint8_t *)"argi-native-", 12, &temporary)) return 2;
    length = _argi_fs_temp_length(temporary);
    path = calloc(length + 1, 1);
    child = calloc(length + 7, 1);
    if (!path || !child) { result = 3; goto done; }
    if (_argi_fs_temp_copy(temporary, (uint8_t *)path, length)) { result = 4; goto done; }
    memcpy(child, path, length);
    memcpy(child + length, "/child", 7);
    if (_argi_fs_mkdir((uint8_t *)child, length + 6)) { result = 5; goto done; }
    child_exists = 1;
    if (_argi_fs_temp_close(temporary) == 0) { temporary = 0; result = 6; goto done; }
    int32_t kind = 0;
    uint64_t size = 0;
    int64_t seconds = 0;
    uint32_t nanoseconds = 0;
    if (_argi_fs_metadata((uint8_t *)path, length, &kind, &size, &seconds, &nanoseconds) || kind != 2 || nanoseconds >= 1000000000) { result = 7; goto done; }
    if (_argi_fs_directory_open((uint8_t *)path, length, &directory)) { result = 8; goto done; }
    uintptr_t name_length = 0;
    uint8_t name[6] = {0};
    if (_argi_fs_directory_next(directory, &name_length) || name_length != 5) { result = 9; goto done; }
    if (_argi_fs_directory_copy(directory, name, 4) != -2 || name[0]) { result = 10; goto done; }
    if (_argi_fs_directory_copy(directory, name, 5) || strcmp((char *)name, "child")) { result = 11; goto done; }
    if (_argi_fs_directory_next(directory, &name_length) != 1) { result = 12; goto done; }
    _argi_fs_directory_close(directory);
    directory = 0;
    file = tmpfile();
    if (!file || fwrite("abcd", 1, 4, file) != 4) { result = 13; goto done; }
    uint64_t position = 0;
    if (_argi_fs_seek((uintptr_t)file, 1, 0, &position) || position != 1) { result = 14; goto done; }
    if (_argi_fs_truncate((uintptr_t)file, 2) || _argi_fs_seek((uintptr_t)file, 0, 2, &position) || position != 2) { result = 15; goto done; }
    if (_argi_fs_truncate((uintptr_t)file, UINT64_MAX) != -2 || _argi_fs_seek(0, 0, 0, &position) != -2) { result = 16; goto done; }
#ifndef _WIN32
    link_path = calloc(length + 6, 1);
    if (!link_path) { result = 20; goto done; }
    memcpy(link_path, path, length);
    memcpy(link_path + length, "/link", 6);
    if (symlink("child", link_path)) { result = 21; goto done; }
    link_exists = 1;
    if (_argi_fs_metadata_nofollow((uint8_t *)link_path, strlen(link_path), &kind, &size, &seconds, &nanoseconds) || kind != 0) { result = 22; goto done; }
    if (_argi_fs_metadata((uint8_t *)link_path, strlen(link_path), &kind, &size, &seconds, &nanoseconds) || kind != 2) { result = 23; goto done; }
    if (unlink(link_path)) { result = 24; goto done; }
    link_exists = 0;
#endif
    if (_argi_fs_rmdir((uint8_t *)child, strlen(child))) { result = 17; goto done; }
    child_exists = 0;
    if (_argi_fs_temp_close(temporary)) { result = 18; goto done; }
    temporary = 0;
    if (_argi_fs_metadata((uint8_t *)path, strlen(path), &kind, &size, &seconds, &nanoseconds) != -4) result = 19;
done:
    if (file) fclose(file);
    _argi_fs_directory_close(directory);
#ifndef _WIN32
    if (link_exists) (void)unlink(link_path);
#endif
    free(link_path);
    if (child_exists) (void)_argi_fs_rmdir((uint8_t *)child, strlen(child));
    _argi_fs_temp_cleanup(temporary);
    free(child);
    free(path);
    return result;
}
#ifdef ARGI_FILESYSTEM_PROBE_MAIN
int main(void) { return argi_filesystem_probe(); }
#endif
