#include "task.h"
#include "thread.h"
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#ifdef _WIN32
#include <malloc.h>
#endif

struct argi_task_output {
    argi_task_buffer_start entry;
    void *published;
    enum { OUTPUT_EMPTY, OUTPUT_SUBMITTED, OUTPUT_PUBLISHED, OUTPUT_CLAIMED } state;
};

struct argi_task {
    struct argi_task_output *caller_output;
    argi_task_buffer_start buffer_start;
    uintptr_t thread;
    void *input;
    void *output;
    uintptr_t input_size;
    uintptr_t output_size;
    uintptr_t input_alignment, output_alignment;
    int joined;
    argi_task_result_cleanup result_cleanup;
    int owner_claimed;
};

static void argi_task_entry(void *context) {
    struct argi_task *task = context;
    struct argi_execution_invocation invocation = {
        (uintptr_t)task, (uintptr_t)task->input, (uintptr_t)task->output,
        task->input_size, task->output_size,
        task->input_alignment, task->output_alignment
    };
    task->result_cleanup = task->buffer_start(invocation);
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

static struct argi_task *argi_task_prepare(argi_task_buffer_start start, const void *input, uintptr_t input_size, uintptr_t output_size, uintptr_t input_alignment, uintptr_t output_alignment) {
    if (!start || (input_size && !input) || !input_alignment || !output_alignment ||
        (input_alignment & (input_alignment - 1)) || (output_alignment & (output_alignment - 1))) return 0;
    struct argi_task *task = calloc(1, sizeof(*task));
    if (!task) return 0;
    task->buffer_start = start;
    task->input_size = input_size;
    task->output_size = output_size;
    task->input_alignment = input_alignment;
    task->output_alignment = output_alignment;
    task->input = argi_task_aligned_buffer(input_size, input_alignment);
    if (!task->input) goto failed_buffers;
    task->output = argi_task_aligned_buffer(output_size, output_alignment);
    if (!task->output) goto failed_buffers;
    if (input_size) memcpy(task->input, input, input_size);
    if (output_size) memset(task->output, 0, output_size);
    return task;
failed_buffers:
    argi_task_aligned_free(task->output);
    argi_task_aligned_free(task->input);
    free(task);
    return 0;
}

static uintptr_t argi_task_start(struct argi_task *task, int inline_run) {
    if (inline_run) {
        argi_task_entry(task);
        task->joined = 1;
        return (uintptr_t)task;
    }
    task->thread = _argi_thread_create(argi_task_entry, task);
    if (!task->thread) {
        /* The thread adapter guarantees that failure leaves no worker. */
        argi_task_aligned_free(task->output);
        argi_task_aligned_free(task->input);
        free(task);
        return 0;
    }
    return (uintptr_t)task;
}

uintptr_t _argi_task_create_buffers(argi_task_buffer_start start, const void *input, uintptr_t input_size, uintptr_t output_size, uintptr_t input_alignment, uintptr_t output_alignment) {
    struct argi_task *task = argi_task_prepare(start, input, input_size, output_size, input_alignment, output_alignment);
    if (!task) return 0;
    return argi_task_start(task, 0);
}

uintptr_t _argi_task_create_inline_buffers(argi_task_buffer_start start, const void *input, uintptr_t input_size, uintptr_t output_size, uintptr_t input_alignment, uintptr_t output_alignment) {
    struct argi_task *task = argi_task_prepare(start, input, input_size, output_size, input_alignment, output_alignment);
    if (!task) return 0;
    return argi_task_start(task, 1);
}

uintptr_t _argi_task_output_create(argi_task_buffer_start entry) {
    if (!entry) return 0;
    struct argi_task_output *slot = calloc(1, sizeof(*slot));
    if (slot) slot->entry = entry;
    return (uintptr_t)slot;
}

int32_t _argi_task_output_accepted(uintptr_t storage, argi_task_buffer_start entry) {
    const struct argi_task_output *slot = (const struct argi_task_output *)storage;
    return slot && slot->entry == entry && slot->state != OUTPUT_EMPTY;
}

uintptr_t _argi_task_start_buffers(uintptr_t storage, int32_t inline_run,
    argi_task_buffer_start entry, const void *input, uintptr_t input_size,
    uintptr_t output_size, uintptr_t input_alignment, uintptr_t output_alignment) {
    struct argi_task_output *slot = (struct argi_task_output *)storage;
    if (slot && (entry != slot->entry || slot->state != OUTPUT_EMPTY)) return 0;
    struct argi_task *task = argi_task_prepare(entry, input, input_size, output_size, input_alignment, output_alignment);
    if (!task) return 0;
    task->caller_output = slot;
    uintptr_t handle = argi_task_start(task, inline_run);
    if (handle && slot) slot->state = OUTPUT_SUBMITTED;
    return handle;
}

uintptr_t _argi_task_output_take(uintptr_t storage, argi_task_buffer_start entry) {
    struct argi_task_output *slot = (struct argi_task_output *)storage;
    if (!slot || entry != slot->entry || slot->state != OUTPUT_PUBLISHED) return 0;
    slot->state = OUTPUT_CLAIMED;
    return (uintptr_t)slot->published;
}

int32_t _argi_task_output_destroy(uintptr_t storage) {
    struct argi_task_output *slot = (struct argi_task_output *)storage;
    if (!slot || slot->state == OUTPUT_SUBMITTED || slot->state == OUTPUT_PUBLISHED) return -1;
    argi_task_aligned_free(slot->published);
    free(slot);
    return 0;
}

static int argi_task_join(struct argi_task *task) {
    if (task->joined) return 0;
    if (_argi_thread_join(task->thread)) return -1;
    task->joined = 1;
    return 0;
}

int32_t _argi_execution_reclaim(uintptr_t handle) {
    if (!handle) return -1;
    return argi_task_join((struct argi_task *)handle);
}

uintptr_t _argi_task_take_owned_result(uintptr_t handle, argi_task_result_cleanup cleanup) {
    struct argi_task *task = (struct argi_task *)handle;
    if (!task || task->caller_output || !cleanup || argi_task_join(task)) return 0;
    if (task->result_cleanup != cleanup || task->owner_claimed) return 0;
    task->owner_claimed = 1;
    return (uintptr_t)task->output;
}

uintptr_t _argi_task_join_result(uintptr_t handle, uintptr_t size) {
    if (!handle) return 0;
    struct argi_task *task = (struct argi_task *)handle;
    if (task->caller_output || size != task->output_size) return 0;
    if (argi_task_join(task) || task->result_cleanup || !task->output) return 0;
    return (uintptr_t)task->output;
}

struct argi_task_result_block _argi_task_result_block(uintptr_t handle, uintptr_t offset) {
    struct argi_task_result_block result = {{0}, 0};
    if (!handle) return result;
    const struct argi_task *task = (const struct argi_task *)handle;
    if (task->caller_output || !task->joined || task->result_cleanup || offset >= task->output_size) return result;
    uintptr_t count = task->output_size - offset;
    if (count > sizeof(result.bytes)) count = sizeof(result.bytes);
    memcpy(result.bytes, (const unsigned char *)task->output + offset, count);
    result.count = count;
    return result;
}

static int32_t argi_task_destroy(uintptr_t handle, int allow_cleanup) {
    if (!handle) return -1;
    struct argi_task *task = (struct argi_task *)handle;
    if (argi_task_join(task)) return -1;
    if (!task->caller_output && !allow_cleanup && task->result_cleanup && !task->owner_claimed) return -1;
    if (task->thread && _argi_thread_destroy(task->thread)) return -1;
    if (task->caller_output) {
        task->caller_output->published = task->output;
        task->caller_output->state = OUTPUT_PUBLISHED;
        task->output = NULL;
    } else if (task->result_cleanup && !task->owner_claimed)
        task->result_cleanup((uintptr_t)task->output);
    argi_task_aligned_free(task->output);
    argi_task_aligned_free(task->input);
    free(task);
    return 0;
}

int32_t _argi_task_release_storage(uintptr_t handle) {
    return argi_task_destroy(handle, 0);
}

int32_t _argi_task_destroy(uintptr_t handle) {
    return argi_task_destroy(handle, 1);
}
