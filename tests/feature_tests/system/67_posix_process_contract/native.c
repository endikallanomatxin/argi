#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
uintptr_t _argi_process_builder(void);
int32_t _argi_process_argument(uintptr_t, const uint8_t *, uintptr_t);
void _argi_process_builder_free(uintptr_t);
int32_t _argi_process_spawn(uintptr_t, int32_t, int32_t, int32_t, uintptr_t *, uintptr_t *, uintptr_t *, uintptr_t *);
int32_t _argi_process_wait(uintptr_t, uint32_t *, uint32_t *);
void _argi_process_free(uintptr_t);
int32_t _argi_process_stream_read(uintptr_t, uint8_t *);
int32_t _argi_process_stream_write(uintptr_t, uint8_t);
int32_t _argi_process_stream_close(uintptr_t);

static int descriptors(void) {
    int count = 0;
    for (int i = 0; i < 1024; ++i) if (fcntl(i, F_GETFD) >= 0) ++count;
    return count;
}
static int argument(uintptr_t builder, const char *text) {
    return _argi_process_argument(builder, (const uint8_t *)text, strlen(text));
}
int32_t argi_posix_process_probe(void) {
    int before = descriptors();
    for (int i = 0; i < 30; ++i) {
        uintptr_t builder = _argi_process_builder(), handle, in, out, err;
        if (!builder || argument(builder, "argi-nonexistent-executable-87a6d")) return 1;
        int32_t status = _argi_process_spawn(builder, 1, 1, 1, &handle, &in, &out, &err);
        _argi_process_builder_free(builder);
        if (status != -1 || handle || in || out || err) return 2;
        if (descriptors() != before) return 3;
    }
    uintptr_t builder = _argi_process_builder(), handle, in, out, err;
    if (!builder || argument(builder, "sh") || argument(builder, "-c") ||
        argument(builder, "printf R; printf E >&2; exit 9")) return 4;
    int saved = dup(STDIN_FILENO);
    close(STDIN_FILENO);
    int32_t status = _argi_process_spawn(builder, 1, 1, 1, &handle, &in, &out, &err);
    if (saved >= 0) { dup2(saved, STDIN_FILENO); close(saved); }
    _argi_process_builder_free(builder);
    if (status || !handle || !in || !out || !err) return 5;
    if (!(fcntl((int)in - 1, F_GETFD) & FD_CLOEXEC) ||
        !(fcntl((int)out - 1, F_GETFD) & FD_CLOEXEC) ||
        !(fcntl((int)err - 1, F_GETFD) & FD_CLOEXEC)) return 6;
    uint8_t byte;
    if (_argi_process_stream_read(out, &byte) != 1 || byte != 'R' ||
        _argi_process_stream_read(err, &byte) != 1 || byte != 'E') return 7;
    uint32_t code, signal;
    if (_argi_process_wait(handle, &code, &signal) || code != 9 || signal) return 8;
    sigset_t old, blocked, pending;
    sigemptyset(&blocked); sigaddset(&blocked, SIGPIPE);
    if (sigprocmask(SIG_BLOCK, &blocked, &old)) return 9;
    /* Preserve a pre-existing pending SIGPIPE, even after another broken write. */
    raise(SIGPIPE);
    if (_argi_process_stream_write(in, 1) != -1 || sigpending(&pending) ||
        !sigismember(&pending, SIGPIPE)) return 10;
    int received;
    if (sigwait(&blocked, &received) || received != SIGPIPE || sigprocmask(SIG_SETMASK, &old, NULL)) return 11;
    if (_argi_process_stream_write(in, 1) != -1) return 12;
    _argi_process_stream_close(in); _argi_process_stream_close(out); _argi_process_stream_close(err);
    _argi_process_free(handle);
    return descriptors() == before ? 0 : 13;
}
