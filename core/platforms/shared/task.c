#include "task.h"
#include "thread.h"
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#ifdef _WIN32
#include <malloc.h>
#endif

struct argi_task {
    argi_task_start start;
    argi_task_buffer_start buffer_start;
    int aligned_buffers;
    uintptr_t thread;
    void *input;
    void *output;
    uintptr_t input_size;
    uintptr_t output_size;
    int joined;
    int completed;
    int taken;
};

static void argi_task_entry(void *context) {
    struct argi_task *task = context;
    if (task->buffer_start) {
        task->buffer_start((uintptr_t)task->input, (uintptr_t)task->output);
        task->completed = 1;
    } else {
        task->start((uintptr_t)task);
    }
}

uintptr_t _argi_task_create(argi_task_start start, uintptr_t input, uintptr_t input_size, uintptr_t output_size) {
    if (!start || (input_size && !input)) return 0;
    /* malloc and calloc supply alignment suitable for ordinary scalar values. */
    struct argi_task *task = calloc(1, sizeof(*task));
    if (!task) return 0;
    task->start = start;
    task->input_size = input_size;
    task->output_size = output_size;
    if (input_size) {
        task->input = malloc(input_size);
        if (!task->input) goto failed;
        memcpy(task->input, (const void *)input, input_size);
    }
    task->output = calloc(1, output_size ? output_size : 1);
    if (!task->output) goto failed;
    task->thread = _argi_thread_create(argi_task_entry, task);
    if (!task->thread) goto failed;
    return (uintptr_t)task;
failed:
    free(task->output);
    free(task->input);
    free(task);
    return 0;
}

/* Allocate at least one byte even for an empty value, so the callback receives
   a stable, aligned address for the complete duration of its invocation. */
static void *argi_task_aligned_buffer(uintptr_t size, uintptr_t alignment) {
    if (!alignment || (alignment & (alignment - 1))) return NULL;
    if (alignment < sizeof(void *)) alignment = sizeof(void *);
    uintptr_t actual = size ? size : 1;
    if (actual > UINTPTR_MAX - (alignment - 1)) return NULL;
    uintptr_t rounded = (actual + alignment - 1) & ~(alignment - 1);
#ifdef _WIN32
    return _aligned_malloc(rounded, alignment);
#else
    return aligned_alloc(alignment, rounded);
#endif
}

static void argi_task_aligned_free(void *buffer) {
#ifdef _WIN32
    _aligned_free(buffer);
#else
    free(buffer);
#endif
}

uintptr_t _argi_task_create_buffers(argi_task_buffer_start start, uintptr_t input, uintptr_t input_size, uintptr_t output_size, uintptr_t input_alignment, uintptr_t output_alignment) {
    if (!start || (input_size && !input) || !input_alignment || !output_alignment ||
        (input_alignment & (input_alignment - 1)) || (output_alignment & (output_alignment - 1))) return 0;
    struct argi_task *task = calloc(1, sizeof(*task));
    if (!task) return 0;
    task->buffer_start = start;
    task->aligned_buffers = 1;
    task->input_size = input_size;
    task->output_size = output_size;
    task->input = argi_task_aligned_buffer(input_size, input_alignment);
    if (!task->input) goto failed_buffers;
    task->output = argi_task_aligned_buffer(output_size, output_alignment);
    if (!task->output) goto failed_buffers;
    if (input_size) memcpy(task->input, (const void *)input, input_size);
    if (output_size) memset(task->output, 0, output_size);
    task->thread = _argi_thread_create(argi_task_entry, task);
    if (!task->thread) goto failed_buffers;
    return (uintptr_t)task;
failed_buffers:
    argi_task_aligned_free(task->output);
    argi_task_aligned_free(task->input);
    free(task);
    return 0;
}

int32_t _argi_task_read_input(uintptr_t handle, uintptr_t destination, uintptr_t size) {
    if (!handle) return -1;
    struct argi_task *task = (struct argi_task *)handle;
    if (size != task->input_size || (size && !destination)) return -1;
    if (size) memcpy((void *)destination, task->input, size);
    return 0;
}

int32_t _argi_task_write_output(uintptr_t handle, uintptr_t source, uintptr_t size) {
    if (!handle) return -1;
    struct argi_task *task = (struct argi_task *)handle;
    if (task->completed || size != task->output_size || (size && !source)) return -1;
    if (size) memcpy(task->output, (const void *)source, size);
    task->completed = 1;
    return 0;
}

static int argi_task_join(struct argi_task *task) {
    if (task->joined) return 0;
    if (_argi_thread_join(task->thread)) return -1;
    task->joined = 1;
    return 0;
}

uintptr_t _argi_task_join_result(uintptr_t handle, uintptr_t size) {
    if (!handle) return 0;
    struct argi_task *task = (struct argi_task *)handle;
    if (size != task->output_size || task->taken) return 0;
    if (argi_task_join(task) || !task->completed || !task->output) return 0;
    task->taken = 1;
    return (uintptr_t)task->output;
}

int32_t _argi_task_await(uintptr_t handle, uintptr_t destination, uintptr_t size) {
    if (!handle) return -1;
    struct argi_task *task = (struct argi_task *)handle;
    if (size != task->output_size || (size && !destination) || task->taken) return -1;
    if (argi_task_join(task) || !task->completed) return -1;
    if (size) memcpy((void *)destination, task->output, size);
    task->taken = 1;
    return 0;
}

int32_t _argi_task_destroy(uintptr_t handle) {
    if (!handle) return -1;
    struct argi_task *task = (struct argi_task *)handle;
    if (argi_task_join(task)) return -1;
    if (_argi_thread_destroy(task->thread)) return -1;
    if (task->aligned_buffers) {
        argi_task_aligned_free(task->output);
        argi_task_aligned_free(task->input);
    } else {
        free(task->output);
        free(task->input);
    }
    free(task);
    return 0;
}
