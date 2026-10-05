/* Darwin's timestamps and temporary directories require its extension namespace
   alongside the POSIX interfaces used by the shared runtime adapters. */
#ifdef __APPLE__
#define _DARWIN_C_SOURCE
#endif
#define _POSIX_C_SOURCE 200809L
#include <unistd.h>
#include <fcntl.h>
#include <spawn.h>
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>
#include <time.h>
#include "../shared/process_arguments.h"
extern char **environ;
struct argi_child { pid_t pid; int finished, failed; uint32_t code, signal; };

/* Move owned descriptors beyond the standard streams before arranging dup2
   actions. This also works when a parent standard descriptor was closed. */
static int argi_owned_fd(int fd) {
    if (fd < 0) return -1;
    int owned = fcntl(fd, F_DUPFD_CLOEXEC, 3);
    close(fd);
    return owned;
}
int32_t _argi_process_spawn(uintptr_t address, int32_t input, int32_t output, int32_t error,
                           uintptr_t *handle, uintptr_t *in, uintptr_t *out, uintptr_t *err) {
    struct argi_launch *launch = (struct argi_launch *)address;
    *handle = *in = *out = *err = 0;
    if (!launch || !launch->count) return -2;
    int modes[3] = { input, output, error }, child[3] = { -1, -1, -1 }, parent[3] = { -1, -1, -1 };
    struct argi_child *process = calloc(1, sizeof(*process));
    if (!process) return -3;
    posix_spawn_file_actions_t actions;
    if (posix_spawn_file_actions_init(&actions)) { free(process); return -1; }
    int status = -1;
    for (int i = 0; i < 3; ++i) {
        if (modes[i] < 0 || modes[i] > 2) { status = -2; goto done; }
        if (modes[i] == 0) continue;
        if (modes[i] == 1) {
            int pair[2];
            if (pipe(pair)) goto done;
            int read_fd = argi_owned_fd(pair[0]), write_fd = argi_owned_fd(pair[1]);
            child[i] = i == 0 ? read_fd : write_fd;
            parent[i] = i == 0 ? write_fd : read_fd;
            if (read_fd < 0 || write_fd < 0) goto done;
        } else {
            child[i] = argi_owned_fd(open("/dev/null", i == 0 ? O_RDONLY : O_WRONLY));
            if (child[i] < 0) goto done;
        }
        if (posix_spawn_file_actions_adddup2(&actions, child[i], i) ||
            posix_spawn_file_actions_addclose(&actions, child[i])) goto done;
        if (parent[i] >= 0 && posix_spawn_file_actions_addclose(&actions, parent[i])) goto done;
    }
    int spawn_status = posix_spawnp(&process->pid, launch->arguments[0], &actions, NULL, launch->arguments, environ);
    if (spawn_status) { status = spawn_status == ENOMEM ? -3 : -1; goto done; }
    *handle = (uintptr_t)process;
    if (parent[0] >= 0) *in = (uintptr_t)parent[0] + 1;
    if (parent[1] >= 0) *out = (uintptr_t)parent[1] + 1;
    if (parent[2] >= 0) *err = (uintptr_t)parent[2] + 1;
    status = 0;
done:
    posix_spawn_file_actions_destroy(&actions);
    for (int i = 0; i < 3; ++i) {
        if (child[i] >= 0) close(child[i]);
        if (status && parent[i] >= 0) close(parent[i]);
    }
    if (status) free(process);
    return status;
}
static int argi_child_wait(struct argi_child *child, int options) {
    if (child->finished) return child->failed ? -1 : 0;
    int status;
    pid_t result;
    do { result = waitpid(child->pid, &status, options); } while (result < 0 && errno == EINTR);
    if (result == 0) return 1;
    if (result < 0) {
        /* ECHILD relinquishes the pid: external reaping must not turn cleanup
           into a signal to a subsequently reused process identifier. */
        if (errno == ECHILD) { child->finished = 1; child->failed = 1; }
        return -1;
    }
    child->finished = 1;
    if (WIFEXITED(status)) child->code = (uint32_t)WEXITSTATUS(status);
    else if (WIFSIGNALED(status)) child->signal = (uint32_t)WTERMSIG(status);
    else { child->failed = 1; return -1; }
    return 0;
}
int32_t _argi_process_wait(uintptr_t handle, uint32_t *code, uint32_t *signal) {
    struct argi_child *child = (struct argi_child *)handle;
    if (!child || argi_child_wait(child, 0)) return -1;
    *code = child->code;
    *signal = child->signal;
    return 0;
}
int32_t _argi_process_terminate(uintptr_t handle) {
    struct argi_child *child = (struct argi_child *)handle;
    if (!child) return -1;
    int status = argi_child_wait(child, WNOHANG);
    if (status <= 0) return status;
    return kill(child->pid, SIGKILL) == 0 || errno == ESRCH ? 0 : -1;
}
void _argi_process_free(uintptr_t handle) {
    struct argi_child *child = (struct argi_child *)handle;
    if (!child) return;
    if (!child->finished) {
        if (argi_child_wait(child, WNOHANG) == 1) {
            if (kill(child->pid, SIGKILL) == 0 || errno == ESRCH) argi_child_wait(child, 0);
        }
    }
    free(child);
}
int32_t _argi_process_stream_close(uintptr_t handle) {
    /* Do not retry close after EINTR: the descriptor may already be released. */
    return handle && close((int)(handle - 1)) ? -1 : 0;
}
int32_t _argi_process_stream_read(uintptr_t handle, uint8_t *byte) {
    ssize_t count;
    do { count = read((int)(handle - 1), byte, 1); } while (count < 0 && errno == EINTR);
    return count < 0 ? -1 : (int32_t)count;
}
int32_t _argi_process_stream_write(uintptr_t handle, uint8_t byte) {
    /* TODO: Use pthread_sigmask when the core adds multithreaded execution;
       sigprocmask's contract is for the synchronous single-thread runtime. */
    /* A broken pipe is a Writer error, not termination of the parent. Block
       SIGPIPE for this operation and consume only a newly generated instance;
       leave an already pending signal and the caller's mask untouched. */
    sigset_t blocked, old, pending;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGPIPE);
    if (sigprocmask(SIG_BLOCK, &blocked, &old)) return -1;
    if (sigpending(&pending)) { sigprocmask(SIG_SETMASK, &old, NULL); return -1; }
    int already_pending = sigismember(&pending, SIGPIPE);
    ssize_t count;
    do { count = write((int)(handle - 1), &byte, 1); } while (count < 0 && errno == EINTR);
    if (count < 0 && errno == EPIPE && !already_pending) {
        /* The write generated SIGPIPE while blocked. sigwait is available on
           both Darwin and Linux; it is called only when that signal is pending. */
        if (!sigpending(&pending) && sigismember(&pending, SIGPIPE)) {
            int received;
            sigwait(&blocked, &received);
        }
    }
    if (sigprocmask(SIG_SETMASK, &old, NULL)) return -1;
    return count == 1 ? 0 : -1;
}

#include "../shared/network.c"
#include "../shared/filesystem.c"

#include "../shared/atomic.c"
