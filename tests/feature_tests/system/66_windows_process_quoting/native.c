#include "../../../../core/platforms/windows/process_command.h"
#include <string.h>

/* Decode one quoted argument independently, following even/odd backslashes
   before quotes rather than reproducing the encoder's output construction. */
static int round_trip(wchar_t **arguments, size_t count) {
    wchar_t *command = argi_process_command(arguments, count);
    if (!command) return -1;
    const wchar_t *p = command;
    for (size_t arg = 0; arg < count; ++arg) {
        size_t index = 0;
        int quoted = 0;
        while (*p == L' ') ++p;
        while (*p && (quoted || *p != L' ')) {
            size_t slashes = 0;
            while (*p == L'\\') { ++slashes; ++p; }
            size_t literal = *p == L'"' ? slashes / 2 : slashes;
            while (literal--) if (arguments[arg][index++] != L'\\') goto failed;
            if (*p == L'"') {
                if (slashes % 2) { if (arguments[arg][index++] != L'"') goto failed; }
                else quoted = !quoted;
                ++p;
            } else if (*p && (quoted || *p != L' ')) {
                if (arguments[arg][index++] != *p++) goto failed;
            }
        }
        if (quoted || arguments[arg][index]) goto failed;
    }
    while (*p == L' ') ++p;
    if (*p) goto failed;
    free(command);
    return 0;
failed:
    free(command);
    return -1;
}
int32_t argi_windows_process_quote_probe(void) {
    wchar_t *edge[] = { L"tool.exe", L"", L"a b", L"a\"b", L"trail\\", L"\\\\\"", L"á;$(no)", L"\\" };
    if (round_trip(edge, sizeof(edge) / sizeof(edge[0]))) return 1;
    wchar_t *small[] = { L"tool", L"", L"a\"b", L"tail\\" };
    wchar_t *encoded = argi_process_command(small, 4);
    if (!encoded || wcscmp(encoded, L"\"tool\" \"\" \"a\\\"b\" \"tail\\\\\"")) { free(encoded); return 2; }
    free(encoded);
    uint32_t random = 7139;
    wchar_t text[3][100], alphabet[] = L" ab\\\"xy";
    wchar_t *args[] = { text[0], text[1], text[2] };
    for (int sample = 0; sample < 2000; ++sample) {
        for (int arg = 0; arg < 3; ++arg) {
            random = random * 1664525u + 1013904223u;
            size_t length = random % 99;
            for (size_t i = 0; i < length; ++i) {
                random = random * 1664525u + 1013904223u;
                text[arg][i] = alphabet[random % 7];
            }
            text[arg][length] = 0;
        }
        if (round_trip(args, 3)) return 3;
    }
    wchar_t *long_argument = malloc(32766 * sizeof(wchar_t));
    if (!long_argument) return 4;
    for (int i = 0; i < 32765; ++i) long_argument[i] = L'x';
    long_argument[32764] = 0;
    wchar_t *long_args[] = { long_argument };
    encoded = argi_process_command(long_args, 1);
    if (!encoded || wcslen(encoded) != 32766) { free(encoded); free(long_argument); return 5; }
    free(encoded);
    long_argument[32764] = L'x'; long_argument[32765] = 0;
    encoded = argi_process_command(long_args, 1);
    free(long_argument);
    if (encoded) { free(encoded); return 6; }
    return 0;
}
