#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

/* Keep the FILE object valid, with buffered output, but make its next native
   write/close fail with EBADF. No descriptor is opened again before fclose. */
uintptr_t argi_test_failed_file(void) {
    FILE *stream = tmpfile();
    if (!stream) return 0;
    if (setvbuf(stream, NULL, _IOFBF, 4096) != 0 || fputc(65, stream) == EOF) {
        fclose(stream);
        return 0;
    }
    if (close(fileno(stream)) != 0) {
        fclose(stream);
        return 0;
    }
    return (uintptr_t)stream;
}
