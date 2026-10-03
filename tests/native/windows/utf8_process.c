#include <windows.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

uintptr_t _argi_runtime_argc(void);
uintptr_t _argi_runtime_argv(void);
char *_argi_getenv_utf8(const char *name);
void _argi_process_cleanup(void);

int main(void) {
    assert(_argi_runtime_argc() == 3);
    char **arguments = (char **)_argi_runtime_argv();
    assert(strcmp(arguments[1], "\xc3\xb1-\xe6\x96\x87") == 0);
    assert(strcmp(arguments[2], "*.tmp") == 0);
    assert(arguments[3] == NULL);
    assert(SetEnvironmentVariableW(L"ARGI_UTF8_TEST", L"\x00f1-\x6587"));
    char *first = _argi_getenv_utf8("ARGI_UTF8_TEST");
    assert(first && strcmp(first, "\xc3\xb1-\xe6\x96\x87") == 0);
    assert(SetEnvironmentVariableW(L"ARGI_UTF8_TEST", L"second"));
    char *second = _argi_getenv_utf8("ARGI_UTF8_TEST");
    assert(second && strcmp(second, "second") == 0);
    assert(strcmp(first, "\xc3\xb1-\xe6\x96\x87") == 0);
    assert(SetEnvironmentVariableW(L"ARGI_UTF8_TEST", NULL));
    assert(_argi_getenv_utf8("ARGI_UTF8_TEST") == NULL);
    assert(SetEnvironmentVariableW(L"ARGI_UTF8_EMPTY", L""));
    char *empty = _argi_getenv_utf8("ARGI_UTF8_EMPTY");
    assert(empty && empty[0] == 0);
    assert(SetEnvironmentVariableW(L"ARGI_UTF8_EMPTY", NULL));
    _argi_process_cleanup();
    return 0;
}
