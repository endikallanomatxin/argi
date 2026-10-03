#ifndef ARGI_PROCESS_COMMAND_H
#define ARGI_PROCESS_COMMAND_H
#include <stdint.h>
#include <stdlib.h>
#include <wchar.h>
#include <errno.h>

/* Encode separate argv entries for the Windows CRT command-line decoder. */
static wchar_t *argi_process_command(wchar_t **args, size_t count) {
    size_t capacity = 1;
    for (size_t i = 0; i < count; ++i) {
        size_t length = wcslen(args[i]);
        if (capacity > SIZE_MAX - 3 || length > (SIZE_MAX - capacity - 3) / 2) { errno = E2BIG; return NULL; }
        capacity += 2 * length + 3;
    }
    /* CreateProcessW limits the entire command line to 32767 UTF-16 units. */
    if (capacity > SIZE_MAX / sizeof(wchar_t)) { errno = E2BIG; return NULL; }
    wchar_t *command = malloc(capacity * sizeof(wchar_t));
    if (!command) { errno = ENOMEM; return NULL; }
    size_t used = 0;
    for (size_t i = 0; i < count; ++i) {
        if (i) command[used++] = L' ';
        command[used++] = L'"';
        size_t slashes = 0;
        for (const wchar_t *p = args[i]; ; ++p) {
            if (*p == L'\\') { ++slashes; continue; }
            size_t repetitions = (*p == L'"' || !*p) ? 2 * slashes : slashes;
            while (repetitions--) command[used++] = L'\\';
            slashes = 0;
            if (!*p) break;
            if (*p == L'"') command[used++] = L'\\';
            command[used++] = *p;
        }
        command[used++] = L'"';
    }
    command[used] = 0;
    if (used >= 32767) { free(command); errno = E2BIG; return NULL; }
    return command;
}
#endif
