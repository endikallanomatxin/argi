#include "../../../../core/platforms/shared/task.h"
#include "../../../../core/platforms/shared/atomic.h"
#include "../../../../core/platforms/shared/thread.h"
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

struct input { uintptr_t gate; uintptr_t entered; int value; };
static void calculate(uintptr_t task) {
    struct input input;
    if (_argi_task_read_input(task, (uintptr_t)&input, sizeof(input))) abort();
    if (!_argi_task_read_input(task, (uintptr_t)&input, sizeof(input) - 1)) abort();
    _argi_atomic_u32_store(input.entered, 1);
    while (!_argi_atomic_u32_load(input.gate)) {}
    int result = input.value * 2;
    if (_argi_task_write_output(task, (uintptr_t)&result, sizeof(result))) abort();
    if (!_argi_task_write_output(task, (uintptr_t)&result, sizeof(result))) abort();
}
static void empty(uintptr_t task) {
    if (_argi_task_read_input(task, 0, 0)) abort();
    if (_argi_task_write_output(task, 0, 0)) abort();
}
static void buffers(uintptr_t input, uintptr_t output) {
    if (!input || !output || input % 64 || output % 64) abort();
    *(int *)output = *(const int *)input * 2;
}
static void empty_buffers(uintptr_t input, uintptr_t output) {
    if (!input || !output || input % 64 || output % 64) abort();
}
struct destroy_job { uintptr_t task; uintptr_t entered; int result; };
static void destroy_task(void *context) {
    struct destroy_job *job = context;
    _argi_atomic_u32_store(job->entered, 1);
    job->result = _argi_task_destroy(job->task);
}

int32_t argi_task_probe(void) {
    if (_argi_task_create(NULL, 0, 0, 0)) return 1;
    int original = 21;
    if (_argi_task_create_buffers(NULL, (uintptr_t)&original, sizeof(original), sizeof(original), 64, 64)) abort();
    if (_argi_task_create_buffers(buffers, (uintptr_t)&original, sizeof(original), sizeof(original), 3, 64)) abort();
    if (_argi_task_create_buffers(buffers, (uintptr_t)&original, sizeof(original), sizeof(original), 64, 0)) abort();
    if (_argi_task_create_buffers(buffers, 0, sizeof(original), sizeof(original), 64, 64)) abort();
    if (_argi_task_create_buffers(buffers, (uintptr_t)&original, UINTPTR_MAX, sizeof(original), 64, 64)) abort();
    uintptr_t buffer_task = _argi_task_create_buffers(buffers, (uintptr_t)&original, sizeof(original), sizeof(original), 64, 64);
    if (!buffer_task) abort();
    original = 0;
    int buffer_result = 0;
    if (_argi_task_await(buffer_task, (uintptr_t)&buffer_result, sizeof(buffer_result)) || buffer_result != 42) abort();
    if (_argi_task_join_result(buffer_task, sizeof(buffer_result))) abort();
    if (_argi_task_destroy(buffer_task)) abort();
    original = 21;
    buffer_task = _argi_task_create_buffers(buffers, (uintptr_t)&original, sizeof(original), sizeof(original), 64, 64);
    if (!buffer_task) abort();
    if (_argi_task_join_result(buffer_task, sizeof(original) - 1)) abort();
    uintptr_t result_address = _argi_task_join_result(buffer_task, sizeof(original));
    if (!result_address || result_address % 64 || *(int *)result_address != 42) abort();
    if (_argi_task_join_result(buffer_task, sizeof(original))) abort();
    if (!_argi_task_await(buffer_task, (uintptr_t)&buffer_result, sizeof(buffer_result))) abort();
    if (_argi_task_destroy(buffer_task)) abort();
    if (_argi_task_join_result(0, 0)) abort();
    buffer_task = _argi_task_create_buffers(empty_buffers, 0, 0, 0, 64, 64);
    if (!buffer_task) abort();
    result_address = _argi_task_join_result(buffer_task, 0);
    if (!result_address || result_address % 64 || _argi_task_destroy(buffer_task)) abort();
    if (_argi_task_create(empty, 0, 1, 0)) return 2;
    uintptr_t gate = _argi_atomic_u32_create(0), entered = _argi_atomic_u32_create(0);
    if (!gate || !entered) abort();
    struct input source = { gate, entered, 21 };
    uintptr_t task = _argi_task_create(calculate, (uintptr_t)&source, sizeof(source), sizeof(int));
    if (!task) abort();
    source.value = 0;
    while (!_argi_atomic_u32_load(entered)) {}
    uintptr_t moved = task;
    task = 0;
    int result = 0;
    if (!_argi_task_await(moved, (uintptr_t)&result, sizeof(result) - 1)) abort();
    _argi_atomic_u32_store(gate, 1);
    if (_argi_task_await(moved, (uintptr_t)&result, sizeof(result)) || result != 42) abort();
    if (!_argi_task_await(moved, (uintptr_t)&result, sizeof(result))) abort();
    if (_argi_task_destroy(moved)) abort();
    uintptr_t zero = _argi_task_create(empty, 0, 0, 0);
    if (!zero || _argi_task_await(zero, 0, 0) || _argi_task_destroy(zero)) abort();

    _argi_atomic_u32_store(gate, 0);
    _argi_atomic_u32_store(entered, 0);
    source.value = 5;
    task = _argi_task_create(calculate, (uintptr_t)&source, sizeof(source), sizeof(int));
    if (!task) abort();
    while (!_argi_atomic_u32_load(entered)) {}
    uintptr_t destroying = _argi_atomic_u32_create(0);
    if (!destroying) abort();
    struct destroy_job job = { task, destroying, -1 };
    uintptr_t joiner = _argi_thread_create(destroy_task, &job);
    if (!joiner) abort();
    while (!_argi_atomic_u32_load(destroying)) {}
    _argi_atomic_u32_store(gate, 1);
    if (_argi_thread_join(joiner)) abort();
    if (job.result || _argi_thread_destroy(joiner)) abort();
    _argi_atomic_u32_destroy(destroying);
    _argi_atomic_u32_destroy(entered);
    _argi_atomic_u32_destroy(gate);
    return 0;
}
