#define _GNU_SOURCE
#include <stdint.h>
#include <errno.h>
#include <stdio.h>
#include <unistd.h>

/* Exercise real stdio error indicators without signal timing or invalid FILEs.
   Linux and Darwin expose different APIs for supplying native stream hooks. */
static uintptr_t interrupted_reads, interrupted_closes;
#ifdef __APPLE__
static int interrupted_read(void *cookie, char *buffer, int count) {
#else
static ssize_t interrupted_read(void *cookie, char *buffer, size_t count) {
#endif
    (void)cookie; (void)buffer; (void)count;
    interrupted_reads++;
    errno = EINTR;
    return -1;
}
static int interrupted_close(void *cookie) {
    (void)cookie;
    interrupted_closes++;
    return 0;
}
uintptr_t argi_test_interrupted_input(void) {
    interrupted_reads = interrupted_closes = 0;
#ifdef __APPLE__
    FILE *stream = funopen(NULL, interrupted_read, NULL, NULL, interrupted_close);
#else
    cookie_io_functions_t hooks = { .read = interrupted_read, .close = interrupted_close };
    FILE *stream = fopencookie(NULL, "r", hooks);
#endif
    return (uintptr_t)stream;
}
uintptr_t argi_test_interrupted_reads(void) { return interrupted_reads; }
uintptr_t argi_test_interrupted_closes(void) { return interrupted_closes; }

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
