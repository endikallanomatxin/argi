#ifndef ARGI_PROCESS_ARGUMENTS_H
#define ARGI_PROCESS_ARGUMENTS_H
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Native launch storage is temporary and never exposed as a safe reference.
   Every argument is copied before launch; child lifetime does not borrow argv. */
struct argi_launch {
    char **arguments;
    size_t count;
};
static int argi_argument_utf8(const uint8_t *bytes, size_t length) {
    size_t i = 0;
    while (i < length) {
        uint32_t value = bytes[i++], minimum;
        size_t continuation;
        if (value < 128) continue;
        if (value >= 194 && value <= 223) { continuation = 1; minimum = 128; value &= 31; }
        else if (value >= 224 && value <= 239) { continuation = 2; minimum = 2048; value &= 15; }
        else if (value >= 240 && value <= 244) { continuation = 3; minimum = 65536; value &= 7; }
        else return 0;
        if (continuation > length - i) return 0;
        while (continuation--) {
            uint8_t byte = bytes[i++];
            if ((byte & 192) != 128) return 0;
            value = (value << 6) | (byte & 63);
        }
        if (value < minimum || value > 1114111 || (value >= 55296 && value <= 57343)) return 0;
    }
    return 1;
}
uintptr_t _argi_process_builder(void) {
    return (uintptr_t)calloc(1, sizeof(struct argi_launch));
}
int32_t _argi_process_argument(uintptr_t address, const uint8_t *bytes, uintptr_t length) {
    struct argi_launch *launch = (struct argi_launch *)address;
    if (!launch || (!launch->count && !length) || memchr(bytes, 0, length) ||
        !argi_argument_utf8(bytes, length)) return -2;
    if (length == SIZE_MAX || launch->count > SIZE_MAX / sizeof(char *) - 2) return -3;
    char *text = malloc(length + 1);
    if (!text) return -3;
    memcpy(text, bytes, length);
    text[length] = 0;
    char **grown = realloc(launch->arguments, (launch->count + 2) * sizeof(char *));
    if (!grown) { free(text); return -3; }
    launch->arguments = grown;
    launch->arguments[launch->count++] = text;
    launch->arguments[launch->count] = NULL;
    return 0;
}
void _argi_process_builder_free(uintptr_t address) {
    struct argi_launch *launch = (struct argi_launch *)address;
    if (!launch) return;
    for (size_t i = 0; i < launch->count; ++i) free(launch->arguments[i]);
    free(launch->arguments);
    free(launch);
}
#endif
