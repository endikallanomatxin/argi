#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0602
#endif
#include <windows.h>
#include <shellapi.h>
#include <malloc.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <wchar.h>
#include <string.h>
#include <io.h>
#include <fcntl.h>
#include "time.c"

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

static UINT original_input_code_page;
static UINT original_output_code_page;

static void configure_console_utf8(int32_t descriptor) {
    if (descriptor < 0 || descriptor > 2) return;
    HANDLE handle = (HANDLE)_get_osfhandle(descriptor);
    DWORD mode;
    if (handle == INVALID_HANDLE_VALUE || !GetConsoleMode(handle, &mode)) return;
    if (descriptor == 0 && !original_input_code_page) {
        UINT original = GetConsoleCP();
        if (original && SetConsoleCP(CP_UTF8)) original_input_code_page = original;
    } else if (descriptor != 0 && !original_output_code_page) {
        UINT original = GetConsoleOutputCP();
        if (original && SetConsoleOutputCP(CP_UTF8)) original_output_code_page = original;
    }
}

FILE *_argi_fdopen(int32_t descriptor, const char *mode) {
    FILE *stream = _fdopen(descriptor, mode);
    // Reader/Writer expose bytes: the CRT must not translate LF or Ctrl-Z.
    if (stream && _setmode(descriptor, _O_BINARY) == -1) {
        fclose(stream);
        return NULL;
    }
    if (stream) configure_console_utf8(descriptor);
    return stream;
}

static char *utf8_string(const wchar_t *text) {
    int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, -1, NULL, 0, NULL, NULL);
    if (!count) { errno = EILSEQ; return NULL; }
    char *bytes = malloc((size_t)count);
    if (!bytes) { errno = ENOMEM; return NULL; }
    if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, -1, bytes, count, NULL, NULL)) {
        free(bytes);
        errno = EILSEQ;
        return NULL;
    }
    return bytes;
}

static char **process_arguments;
static uintptr_t process_argument_count;

// Windows CRT narrow argv uses a process code page. Obtain OS wide arguments and
// retain UTF-8 copies for the generated entry scope, without wildcard expansion.
static void prepare_arguments(void) {
    if (process_arguments) return;
    int count;
    wchar_t **wide_arguments = CommandLineToArgvW(GetCommandLineW(), &count);
    if (!wide_arguments || count < 0) goto failed;
    process_arguments = calloc((size_t)count + 1, sizeof(char *));
    if (!process_arguments) goto failed;
    for (int i = 0; i < count; ++i) {
        process_arguments[i] = utf8_string(wide_arguments[i]);
        if (!process_arguments[i]) goto failed;
        process_argument_count++;
    }
    LocalFree(wide_arguments);
    return;
failed:
    fputs("Cannot encode process arguments as UTF-8.\n", stderr);
    exit(EXIT_FAILURE);
}

uintptr_t _argi_runtime_argc(void) {
    prepare_arguments();
    return process_argument_count;
}

uintptr_t _argi_runtime_argv(void) {
    prepare_arguments();
    return (uintptr_t)process_arguments;
}

struct environment_value {
    struct environment_value *next;
    char *bytes;
};
static struct environment_value *environment_values;

char *_argi_getenv_utf8(const char *name) {
    wchar_t *wide_name = wide_string(name);
    if (!wide_name) return NULL;
    SetLastError(ERROR_SUCCESS);
    DWORD count = GetEnvironmentVariableW(wide_name, NULL, 0);
    if (!count) {
        DWORD error = GetLastError();
        free(wide_name);
        return error == ERROR_SUCCESS ? "" : NULL;
    }
    wchar_t *wide_value = malloc((size_t)count * sizeof(wchar_t));
    if (!wide_value) { free(wide_name); return NULL; }
    wide_value[0] = 0;
    SetLastError(ERROR_SUCCESS);
    DWORD written = GetEnvironmentVariableW(wide_name, wide_value, count);
    free(wide_name);
    if (written >= count) { free(wide_value); return NULL; }
    // An environment value may disappear between the size query and the read.
    if (!written && GetLastError() != ERROR_SUCCESS) { free(wide_value); return NULL; }
    char *bytes = utf8_string(wide_value);
    free(wide_value);
    if (!bytes) return NULL;
    // Keep returned views stable even if a later foreign call changes the
    // environment. Reuse equal values; release all retained copies at entry exit.
    for (struct environment_value *item = environment_values; item; item = item->next) {
        if (strcmp(item->bytes, bytes) == 0) { free(bytes); return item->bytes; }
    }
    struct environment_value *item = malloc(sizeof(*item));
    if (!item) { free(bytes); return NULL; }
    item->bytes = bytes;
    item->next = environment_values;
    environment_values = item;
    return bytes;
}

void _argi_process_cleanup(void) {
    if (original_input_code_page) SetConsoleCP(original_input_code_page);
    if (original_output_code_page) SetConsoleOutputCP(original_output_code_page);
    original_input_code_page = 0;
    original_output_code_page = 0;
    for (uintptr_t i = 0; i < process_argument_count; ++i) free(process_arguments[i]);
    free(process_arguments);
    process_arguments = NULL;
    process_argument_count = 0;
    while (environment_values) {
        struct environment_value *next = environment_values->next;
        free(environment_values->bytes);
        free(environment_values);
        environment_values = next;
    }
}
