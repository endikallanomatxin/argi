#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

FILE *_argi_fopen_utf8(const char *path, const char *mode);
int32_t _argi_access_utf8(const char *path, int32_t mode);
int32_t _argi_rename_utf8(const char *old_path, const char *new_path);
int32_t _argi_remove_utf8(const char *path);

int main(void) {
    const char *path = "argi-\xc3\xb1-\xe6\x96\x87.tmp";
    const char *renamed = "argi-\xc3\xb1-renamed.tmp";
    const char bytes[] = {'a', '\n', 0x1a, 'b'};
    FILE *file = _argi_fopen_utf8(path, "wb");
    assert(file != NULL);
    assert(fwrite(bytes, 1, sizeof(bytes), file) == sizeof(bytes));
    assert(fclose(file) == 0);
    assert(_argi_access_utf8(path, 0) == 0);
    assert(_argi_rename_utf8(path, renamed) == 0);
    file = _argi_fopen_utf8(renamed, "rb");
    assert(file != NULL);
    char readback[sizeof(bytes)];
    assert(fread(readback, 1, sizeof(readback), file) == sizeof(readback));
    assert(memcmp(readback, bytes, sizeof(bytes)) == 0);
    assert(fclose(file) == 0);
    assert(_argi_remove_utf8(renamed) == 0);
    assert(_argi_access_utf8(renamed, 0) == -1);
    assert(_argi_fopen_utf8("argi-\xff.tmp", "wb") == NULL);
    return 0;
}
