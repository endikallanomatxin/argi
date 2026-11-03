#include "../../../../core/platforms/shared/thread.h"
#include <stdlib.h>

struct task {
    int (*callback)(int);
    int input;
    int result;
};

static void run_worker(void *context) {
    struct task *task = context;
    task->result = task->callback(task->input);
}

int argi_generated_thread_task(int (*callback)(int), int value) {
    if (!callback) abort();
    struct task task = { callback, value, 0 };
    uintptr_t thread = _argi_thread_create(run_worker, &task);
    if (!thread) abort();
    /* A failed join cannot release the stack context while a worker may use it. */
    if (_argi_thread_join(thread)) abort();
    int result = task.result;
    if (_argi_thread_destroy(thread)) abort();
    return result;
}
