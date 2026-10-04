/* Bounded path inputs are copied before native calls. Directory entries never
   lend pointers into OS enumeration storage to the Argi facade. */
#ifndef _WIN32
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#else
#include <windows.h>
#include <io.h>
#endif
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <limits.h>
#include "filesystem.h"

static int32_t argi_fs_errno(void) {
    switch (errno) {
        case ENOENT: return -4;
        case EACCES: case EPERM: return -5;
        case EEXIST: return -6;
        case ENOTDIR: return -7;
        case ENOMEM: return -3;
        default: return -1;
    }
}
#ifdef _WIN32
static int32_t argi_fs_windows_error(void) {
    switch (GetLastError()) {
        case ERROR_FILE_NOT_FOUND: case ERROR_PATH_NOT_FOUND: return -4;
        case ERROR_ACCESS_DENIED: return -5;
        case ERROR_ALREADY_EXISTS: case ERROR_FILE_EXISTS: return -6;
        case ERROR_DIRECTORY: return -7;
        case ERROR_NOT_ENOUGH_MEMORY: return -3;
        default: return -1;
    }
}
#endif
static char *argi_fs_path(const uint8_t *bytes, uintptr_t length, int32_t *status) {
    *status = -2;
    if (!length || !bytes || length == UINTPTR_MAX || memchr(bytes, 0, length)) return NULL;
    char *path = malloc(length + 1);
    if (!path) { *status = -3; return NULL; }
    memcpy(path, bytes, length);
    path[length] = 0;
    *status = 0;
    return path;
}
#ifdef _WIN32
static wchar_t *argi_fs_wide(const char *path, int32_t *status) {
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    if (!count) { *status = -2; return NULL; }
    wchar_t *wide = malloc((size_t)count * sizeof(*wide));
    if (!wide) { *status = -3; return NULL; }
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, count)) { free(wide); *status = -2; return NULL; }
    return wide;
}
#endif
int32_t _argi_fs_mkdir(const uint8_t *bytes, uintptr_t length) {
    int32_t status;
    char *path = argi_fs_path(bytes, length, &status);
    if (!path) return status;
#ifdef _WIN32
    wchar_t *wide = argi_fs_wide(path, &status);
    if (wide) { status = CreateDirectoryW(wide, NULL) ? 0 : argi_fs_windows_error(); free(wide); }
#else
    status = mkdir(path, 0700) ? argi_fs_errno() : 0;
#endif
    free(path);
    return status;
}
int32_t _argi_fs_rmdir(const uint8_t *bytes, uintptr_t length) {
    int32_t status;
    char *path = argi_fs_path(bytes, length, &status);
    if (!path) return status;
#ifdef _WIN32
    wchar_t *wide = argi_fs_wide(path, &status);
    if (wide) { status = RemoveDirectoryW(wide) ? 0 : argi_fs_windows_error(); free(wide); }
#else
    status = rmdir(path) ? argi_fs_errno() : 0;
#endif
    free(path);
    return status;
}
int32_t _argi_fs_metadata(const uint8_t *bytes, uintptr_t length, int32_t *kind, uint64_t *size, int64_t *seconds, uint32_t *nanoseconds) {
    *kind = 0; *size = 0; *seconds = 0; *nanoseconds = 0;
    int32_t status;
    char *path = argi_fs_path(bytes, length, &status);
    if (!path) return status;
#ifdef _WIN32
    wchar_t *wide = argi_fs_wide(path, &status);
    if (wide) {
        WIN32_FILE_ATTRIBUTE_DATA info;
        if (!GetFileAttributesExW(wide, GetFileExInfoStandard, &info)) status = argi_fs_windows_error();
        else {
            *kind = info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY ? 2 : 1;
            *size = ((uint64_t)info.nFileSizeHigh << 32) | info.nFileSizeLow;
            uint64_t ticks = ((uint64_t)info.ftLastWriteTime.dwHighDateTime << 32) | info.ftLastWriteTime.dwLowDateTime;
            *seconds = (int64_t)(ticks / 10000000) - INT64_C(11644473600);
            *nanoseconds = (uint32_t)(ticks % 10000000) * 100;
        }
        free(wide);
    }
#else
    struct stat info;
    if (stat(path, &info)) status = argi_fs_errno();
    else {
        *kind = S_ISREG(info.st_mode) ? 1 : S_ISDIR(info.st_mode) ? 2 : 0;
        *size = info.st_size < 0 ? 0 : (uint64_t)info.st_size;
#ifdef __APPLE__
        *seconds = info.st_mtimespec.tv_sec; *nanoseconds = (uint32_t)info.st_mtimespec.tv_nsec;
#else
        *seconds = info.st_mtim.tv_sec; *nanoseconds = (uint32_t)info.st_mtim.tv_nsec;
#endif
    }
#endif
    free(path);
    return status;
}
struct argi_fs_directory {
#ifdef _WIN32
    HANDLE search;
    WIN32_FIND_DATAW entry;
    int first;
    char name[4 * MAX_PATH];
#else
    DIR *directory;
    const char *name;
#endif
};
int32_t _argi_fs_directory_open(const uint8_t *bytes, uintptr_t length, uintptr_t *handle) {
    *handle = 0;
    int32_t status;
    char *path = argi_fs_path(bytes, length, &status);
    if (!path) return status;
    struct argi_fs_directory *owner = calloc(1, sizeof(*owner));
    if (!owner) { free(path); return -3; }
#ifdef _WIN32
    wchar_t *wide = argi_fs_wide(path, &status);
    if (wide) {
        DWORD attributes = GetFileAttributesW(wide);
        if (attributes == INVALID_FILE_ATTRIBUTES) status = argi_fs_windows_error();
        else if (!(attributes & FILE_ATTRIBUTE_DIRECTORY)) status = -7;
        else {
            size_t count = wcslen(wide);
            wchar_t *pattern = malloc((count + 3) * sizeof(*pattern));
            if (!pattern) status = -3;
            else {
                memcpy(pattern, wide, count * sizeof(*pattern));
                pattern[count] = L'\\'; pattern[count + 1] = L'*'; pattern[count + 2] = 0;
                owner->search = FindFirstFileW(pattern, &owner->entry);
                if (owner->search == INVALID_HANDLE_VALUE) status = argi_fs_windows_error();
                else owner->first = 1;
                free(pattern);
            }
        }
        free(wide);
    }
#else
    owner->directory = opendir(path);
    if (!owner->directory) status = argi_fs_errno();
#endif
    free(path);
    if (status) { free(owner); return status; }
    *handle = (uintptr_t)owner;
    return 0;
}
int32_t _argi_fs_directory_next(uintptr_t handle, uintptr_t *length) {
    *length = 0;
    if (!handle) return -1;
    struct argi_fs_directory *owner = (struct argi_fs_directory *)handle;
    for (;;) {
#ifdef _WIN32
        if (!owner->first && !FindNextFileW(owner->search, &owner->entry))
            return GetLastError() == ERROR_NO_MORE_FILES ? 1 : argi_fs_windows_error();
        owner->first = 0;
        if (!wcscmp(owner->entry.cFileName, L".") || !wcscmp(owner->entry.cFileName, L"..")) continue;
        if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, owner->entry.cFileName, -1, owner->name, sizeof(owner->name), NULL, NULL)) return -2;
#else
        errno = 0;
        struct dirent *entry = readdir(owner->directory);
        if (!entry) return errno ? argi_fs_errno() : 1;
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        owner->name = entry->d_name;
#endif
        *length = strlen(owner->name);
        return 0;
    }
}
int32_t _argi_fs_directory_copy(uintptr_t handle, uint8_t *bytes, uintptr_t capacity) {
    if (!handle) return -1;
    struct argi_fs_directory *owner = (struct argi_fs_directory *)handle;
#ifndef _WIN32
    if (!owner->name) return -2;
#endif
    if (capacity < strlen(owner->name)) return -2;
    memcpy(bytes, owner->name, strlen(owner->name));
    return 0;
}
void _argi_fs_directory_close(uintptr_t handle) {
    if (!handle) return;
    struct argi_fs_directory *owner = (struct argi_fs_directory *)handle;
#ifdef _WIN32
    FindClose(owner->search);
#else
    closedir(owner->directory);
#endif
    free(owner);
}
int32_t _argi_fs_seek(uintptr_t stream, int64_t offset, int32_t origin, uint64_t *position) {
    *position = 0;
    if (!stream || origin < 0 || origin > 2) return -2;
    FILE *file = (FILE *)stream;
    int whence = origin == 0 ? SEEK_SET : origin == 1 ? SEEK_CUR : SEEK_END;
#ifdef _WIN32
    if (_fseeki64(file, offset, whence)) return argi_fs_errno();
    int64_t result = _ftelli64(file);
#else
    off_t converted = (off_t)offset;
    if ((int64_t)converted != offset) return -2;
    if (fseeko(file, converted, whence)) return argi_fs_errno();
    off_t result = ftello(file);
#endif
    if (result < 0) return argi_fs_errno();
    *position = (uint64_t)result;
    return 0;
}
int32_t _argi_fs_truncate(uintptr_t stream, uint64_t size) {
    if (!stream || size > INT64_MAX) return -2;
    FILE *file = (FILE *)stream;
    if (fflush(file)) return argi_fs_errno();
#ifdef _WIN32
    errno_t status = _chsize_s(_fileno(file), size);
    if (status) { errno = status; return argi_fs_errno(); }
#else
    off_t converted = (off_t)size;
    if (converted < 0 || (uint64_t)converted != size) return -2;
    if (ftruncate(fileno(file), converted)) return argi_fs_errno();
#endif
    return 0;
}

#ifdef _WIN32
int32_t _argi_system_entropy(unsigned char *, uintptr_t);
#endif
int32_t _argi_fs_temp_create(const uint8_t *parent, uintptr_t parent_length,
                            const uint8_t *prefix, uintptr_t prefix_length,
                            uintptr_t *handle) {
    *handle = 0;
    int32_t status;
    char *base = argi_fs_path(parent, parent_length, &status);
    if (!base) return status;
    if (prefix_length > 32 || (prefix_length && (!prefix || memchr(prefix, 0, prefix_length) ||
        memchr(prefix, '/', prefix_length) || memchr(prefix, '\\', prefix_length) || memchr(prefix, ':', prefix_length)))) {
        free(base); return -2;
    }
    if (parent_length > UINTPTR_MAX - prefix_length - 34) { free(base); return -2; }
    char *path = malloc(parent_length + prefix_length + 34);
    if (!path) { free(base); return -3; }
    memcpy(path, base, parent_length);
    free(base);
    path[parent_length] = '/';
    if (prefix_length) memcpy(path + parent_length + 1, prefix, prefix_length);
    char *suffix = path + parent_length + 1 + prefix_length;
#ifdef _WIN32
    for (int attempt = 0; attempt < 128; attempt++) {
        unsigned char random[16];
        if (_argi_system_entropy(random, sizeof(random))) { free(path); return -1; }
        static const char hex[] = "0123456789abcdef";
        for (int i = 0; i < 16; i++) { suffix[2 * i] = hex[random[i] >> 4]; suffix[2 * i + 1] = hex[random[i] & 15]; }
        suffix[32] = 0;
        wchar_t *wide = argi_fs_wide(path, &status);
        if (!wide) { free(path); return status; }
        if (CreateDirectoryW(wide, NULL)) { free(wide); *handle = (uintptr_t)path; return 0; }
        status = argi_fs_windows_error();
        free(wide);
        if (status != -6) { free(path); return status; }
    }
    free(path);
    return -6;
#else
    memcpy(suffix, "XXXXXX", 7);
    if (!mkdtemp(path)) { status = argi_fs_errno(); free(path); return status; }
    *handle = (uintptr_t)path;
    return 0;
#endif
}
uintptr_t _argi_fs_temp_length(uintptr_t handle) { return handle ? strlen((char *)handle) : 0; }
int32_t _argi_fs_temp_copy(uintptr_t handle, uint8_t *bytes, uintptr_t capacity) {
    if (!handle || !bytes || capacity < strlen((char *)handle)) return -2;
    memcpy(bytes, (char *)handle, strlen((char *)handle));
    return 0;
}
int32_t _argi_fs_temp_close(uintptr_t handle) {
    if (!handle) return 0;
    char *path = (char *)handle;
    int32_t status = _argi_fs_rmdir((const uint8_t *)path, strlen(path));
    if (!status) free(path);
    return status;
}
void _argi_fs_temp_cleanup(uintptr_t handle) {
    if (!handle) return;
    char *path = (char *)handle;
    (void)_argi_fs_rmdir((const uint8_t *)path, strlen(path));
    free(path);
}
